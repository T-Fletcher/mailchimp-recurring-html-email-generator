#!/bin/bash

### MAILCHIMP RECURRING HTML EMAIL GENERATOR

# ====================
# Author: Tim Fletcher
# Date: 2024-08-09
# Licence: GPL-3.0
# Source location: https://github.com/T-Fletcher/mailchimp-recurring-html-email-generator
# ====================

# NOTE: Times are in UTC
NOW=$(date -u +"%Y%m%dT%H:%M:%S%z")
NOW_EPOCH=$(date +%s)

# Better logging
function logError() {
    local message=$1
    local errorCode=$2
    echo -e "[ERROR] - $message"
    exit $errorCode
}

function logInfo() {
    echo -e "[INFO] - $@"
}

function logWarning() {
    echo -e "[WARNING] - $@"
}

function logDebug() {
    if [[ $DEBUG == "true" ]]; then
        echo -e "[DEBUG] - $@"
    fi
}

# Handle responses when requesting data 
function receivedData() {
    local message=$1
    if [[ $EXIT_CODE -ne 0 ]]; then
        logError "Failed to get $message" $EXIT_CODE
    fi
}

function testMailchimpResponse() {
    #* Mailchimp API errors doco: 
    #* https://mailchimp.com/developer/marketing/docs/errors/

    local response=$@
    local responseType=$(jq -r ".type" <<<$response)
    local responseStatus=$(jq -r ".status" <<<$response)

    if [[ $reponseType == 'https://mailchimp.com/developer/marketing/docs/errors/' ]];then
        logError "Error response received from MailChimp, quitting..." $response
        # If the response status is a number AND a non-200 HTTP code
    elif [[ $responseStatus =~ ^[0-9]+$ ]]; then
        if [[ $responseStatus -lt 200 || $responseStatus -gt 299 ]]; then
            logWarning "Received HTTP response '$responseStatus' from Mailchimp! Quitting..."
            logError "$response"
        fi
    else 
        logInfo "Response from Mailchimp:"
        echo -e "$response"
    fi
}

function testLogin() {
    local SERVICE=$1
    if [[ $EXIT_CODE -ne 0 ]]; then
        logError "Could not log into $SERVICE (Exit code $EXIT_CODE), quitting..." 1
    else
        logInfo "$SERVICE login successful!"
    fi
}

function replaceLogFolder() {
    local DIRECTORY=$1
    if [[ $EXIT_CODE -ne 0 ]]; then
        logError "Failed to remove $DIRECTORY, exit code $EXIT_CODE. Quitting..." 2
    fi
}

function tidyErrors() {
    local ERRORS=$1
    if [[ $EXIT_CODE -ne 0 ]]; then
      logError "Tidy found errors with the HTML file. Exit code: $EXIT_CODE" $EXIT_CODE
    fi
}

# Load env variables before doing anything else
if [[ -f ".env" ]]; then
    source ".env"
    if [[ $DEBUG == "true" ]]; then
        logDebug "DEBUG mode is enabled"
    fi
else
    logError "Environment variable file '.env' does not exist.
    You can create one by copying '.env.example'." 1;
fi

# Set up folder structure and logs names
ROOT_DIR=$(pwd)
FULL_NAME="Mailchimp $MAILCHIMP_EMAIL_SHORT_NAME Email Generator"
URL_NAME="mailchimp-$MAILCHIMP_EMAIL_SHORT_NAME-email-generator"
TEMP_DIR="$ROOT_DIR/$URL_NAME-logs-$NOW"
MAILCHIMP_LOGS_DIR="$ROOT_DIR/$URL_NAME-logs"
MAILCHIMP_EXECUTION_LOG_FILENAME="$URL_NAME-history.log"
MAILCHIMP_SCRIPT_LOGFILE="$MAILCHIMP_LOGS_DIR/$URL_NAME-output-$NOW.log"
TEST_DATA="../test/test-data.html"

if [[ ! -d $MAILCHIMP_LOGS_DIR ]]; then
    mkdir $MAILCHIMP_LOGS_DIR
fi

# Send script output to the logs
echo -e "Saving output logs to $MAILCHIMP_SCRIPT_LOGFILE..."
exec > $MAILCHIMP_SCRIPT_LOGFILE 2>&1

# Prefix 'TEST--' to emails if debugging is enabled
if [[ $DEBUG == "true" ]]; then
    MAILCHIMP_EMAIL_SHORT_NAME=$(echo "TEST--$MAILCHIMP_EMAIL_SHORT_NAME")
fi

logInfo "$FULL_NAME starting..."

if [[ -z $MAILCHIMP_SERVER_PREFIX || -z $MAILCHIMP_API_KEY || -z $EMAIL_CONTENT_URL || -z $MAILCHIMP_EMAIL_SHORT_NAME ]]; then
    logError "Required environment variables are missing.
    See '.env.example' for required variables." 2;
fi

if [[ -z $MAILCHIMP_TARGET_AUDIENCE_ID ]]; then
    logWarning "Target Mailchimp Audience ID environment variable is missing! 
    The Template will still be generated but no emails will be created or sent."
fi

if [[ -z $DRUPAL_TERMINUS_SITE ]]; then
    logWarning "Terminus site environment variable is not set!
    Let's assume your URL isn't from a Pantheon Drupal website.
    You can proceed but will need to handle clearing your
    website's cache some other way, or you may recieve stale data.";
fi

trap cleanUp EXIT

function cleanUp() {
    logInfo "Cleaning up script artifacts..."
    
    cd $ROOT_DIR
    logInfo "Switching to $ROOT_DIR"
    if [[ ! -f $MAILCHIMP_EXECUTION_LOG_FILENAME ]]; then
        touch $MAILCHIMP_EXECUTION_LOG_FILENAME
    fi
    
    # Track the daily success/failure of the script, in a place that isn't
    # affected by the cleanup steps
    if [[ $EXIT_CODE -ne 0 ]]; then
        logInfo "$(date -u +"%Y%m%dT%H:%M:%S%z") - [FAIL] - $FULL_NAME failed to complete, exit code: $EXIT_CODE" >> $MAILCHIMP_EXECUTION_LOG_FILENAME
    else
        logInfo "$(date -u +"%Y%m%dT%H:%M:%S%z") - [SUCCESS] - $FULL_NAME completed successfully" >> $MAILCHIMP_EXECUTION_LOG_FILENAME
    fi

    if [[ ! -z $MAILCHIMP_TEMPLATE_ID && -z $DELETE_TEMPLATE_ON_CLEANUP || $DELETE_TEMPLATE_ON_CLEANUP == "true" ]]; then
        logInfo "Removing Mailchimp Templates created by the script, whether by testing or not"
        curl -sX DELETE \
        "https://${MAILCHIMP_SERVER_PREFIX}.api.mailchimp.com/3.0/templates/$MAILCHIMP_TEMPLATE_ID" \
        --user "anystring:${MAILCHIMP_API_KEY}"
    fi

    rm -rf $TEMP_DIR;
    rm -rf "html.tmp"
    
    logInfo "Clean up complete!"
    
    COMPLETE_TIME=$(date +%s)
    logInfo "Finished $FULL_NAME in $(($COMPLETE_TIME - $NOW_EPOCH)) seconds, at $(date -u +"%Y%m%dT%H:%M:%S%z")"
    
    if [[ $DEBUG == "true" ]]; then
        logDebug "Opening log file from this run (requires 'code' alias to open your editor of choice)..."
        code $MAILCHIMP_SCRIPT_LOGFILE
    fi
}

# Test log locations exist
if [[ ! -d $MAILCHIMP_LOGS_DIR ]]; then
    logError "$MAILCHIMP_LOGS_DIR directory not found, quitting..." 6
fi

if [[ -d $TEMP_DIR ]]; then
    logInfo "Log folder '$TEMP_DIR' already exists, deleting it to start fresh..."
    rm -rf $TEMP_DIR
    EXIT_CODE=$? replaceLogFolder $TEMP_DIR
    mkdir $TEMP_DIR
else
    logInfo "Log folder not found, creating '$TEMP_DIR'..."
    mkdir $TEMP_DIR
fi

if [[ ! -d $TEMP_DIR ]]; then
    logError "No $TEMP_DIR found, quitting..." 3
fi

cd $TEMP_DIR

logInfo "Switching to $TEMP_DIR"

# Set the required Mailchimp API variables
MAILCHIMP_SERVER_PREFIX=$MAILCHIMP_SERVER_PREFIX
MAILCHIMP_API_KEY=$MAILCHIMP_API_KEY


if [[ ! -z $DRUPAL_TERMINUS_SITE ]]; then
    logInfo "Terminus sitename provided: $DRUPAL_TERMINUS_SITE"
    logInfo "Attempting to log into Terminus via machine token to prevent session timeouts..."
    
    terminus auth:login
    EXIT_CODE=$? testLogin 'Terminus'
    
    logInfo "Testing Drush access..."
    terminus remote:drush $DRUPAL_TERMINUS_SITE -- status | grep 'Drupal bootstrap'
    EXIT_CODE=$? testLogin 'Drupal'
    
    logInfo "Flushing Drupal caches..."
    terminus remote:drush $DRUPAL_TERMINUS_SITE -- cr
    EXIT_CODE=$? receivedData 'Drupal cache flush'

    # Pause before hitting Drupal for the new content, to avoid a race
    sleep 10
fi

DATE_AEST=$(TZ=Australia/Sydney date +"%d %h %Y")

logInfo "Using the time '$DATE_AEST' for the email subject line and title"

if [[ $DEBUG == "true" && -f $TEST_DATA ]]; then
    logDebug "Using data from '$TEST_DATA'..."
    HTML=$(<$TEST_DATA)
    EXIT_CODE=$? receivedData 'HTML test data'
else
    logInfo "Sourcing data from '$EMAIL_CONTENT_URL'"
    HTML=$(curl -s "$EMAIL_CONTENT_URL")
    EXIT_CODE=$? receivedData 'HTML data'
fi

logDebug "Data:\n$HTML"

# logInfo "Checking HTML is valid..."
# echo -e "$HTML" > "html.tmp"

# TIDY_HTML_OUTPUT=$(tidy -m "html.tmp" -f "html_errors.tmp")
# EXIT_CODE=$? tidyErrors html_errors.tmp

logInfo "Encoding HTML data as a JSON-safe string"
#! Do not use jq's -s option (--slurp) to grab the HTML as a single string!
#! It adds a line break at the end of the string that breaks the JSON string.
HTML_ENCODED=$(echo -e $HTML | jq -R ".")
EXIT_CODE=$? receivedData 'HTML to JSON-safe string'

MAILCHIMP_CAMPAIGN_DATA='{
    "name": '\""$MAILCHIMP_EMAIL_SHORT_NAME template - $DATE_AEST"\"',
    "folder_id": "",
    "html": '$HTML_ENCODED'
}'

if [[ $DEBUG == "true" ]]; then
    logDebug "Data to be submitted to Mailchimp to generate the Campaign:"
    logDebug $MAILCHIMP_CAMPAIGN_DATA
fi

logInfo "Submitting encoded HTML data to Mailchimp to create a new Template..."

MAILCHIMP_CREATE_TEMPLATE=$(curl -sX POST \
  "https://${MAILCHIMP_SERVER_PREFIX}.api.mailchimp.com/3.0/templates" \
  --user "anystring:${MAILCHIMP_API_KEY}" \
  -d "${MAILCHIMP_CAMPAIGN_DATA}")
EXIT_CODE=$? receivedData 'Template creation response'

testMailchimpResponse "$MAILCHIMP_CREATE_TEMPLATE"

MAILCHIMP_TEMPLATE_ID=$(echo -e $MAILCHIMP_CREATE_TEMPLATE | jq -r ".id")
EXIT_CODE=$? receivedData "Template ID $MAILCHIMP_TEMPLATE_ID"

logInfo "Creating new Email Campaign from the new Template..."
# Only create the email campaign if debugging is disabled
# if [[ ! $DEBUG == "true" ]]; then

#* See list of all Campaign options: 
#* https://mailchimp.com/developer/marketing/api/campaigns/add-campaign/

MAILCHIMP_EMAIL=$(curl -sX POST \
"https://${MAILCHIMP_SERVER_PREFIX}.api.mailchimp.com/3.0/campaigns" \
--user "anystring:${MAILCHIMP_API_KEY}" \
-d '{
    "type": "regular",
    "recipients": {
        "list_id": '\""$MAILCHIMP_TARGET_AUDIENCE_ID"\"'
    },
    "settings": {
        "subject_line": '\""$MAILCHIMP_EMAIL_SUBJECT: $DATE_AEST"\"',
        "preview_text": "",
        "title": '\""$MAILCHIMP_EMAIL_TITLE - $DATE_AEST"\"',
        "from_name": '\""$MAILCHIMP_EMAIL_FROM"\"',
        "reply_to": '\""$MAILCHIMP_EMAIL_REPLYTO"\"',
        "use_conversation": false,
        "to_name": "",
        "folder_id": '\""$MAILCHIMP_EMAIL_FOLDER_ID"\"',
        "authenticate": false,
        "auto_footer": true,
        "inline_css": false,
        "auto_tweet": false,
        "auto_fb_post": [],
        "fb_comments": false,
        "template_id": '$MAILCHIMP_TEMPLATE_ID'
    },
        "content_type": "template"
    }')
EXIT_CODE=$? receivedData 'Email Campaign creation response'

testMailchimpResponse "$MAILCHIMP_EMAIL"

logInfo "Email Campaign created successfully"

#TODO: Fix scheduling 

MAILCHIMP_EMAIL_ID=$(echo -e "$MAILCHIMP_EMAIL" | jq -r ".id")

# Lastly, schedule the new email Campaign to be sent

TODAY=$(date -I)
logDebug $TODAY

MAILCHIMP_SCHEDULED_TIME="$TODAYT$MAILCHIMP_EMAIL_SEND_TIME_UTC+0000"
logDebug "$MAILCHIMP_SCHEDULED_TIME"

MAILCHIMP_EMAIL_SCHEDULE=$(curl -sX POST \
"https://${MAILCHIMP_SERVER_PREFIX}.api.mailchimp.com/3.0/campaigns/$MAILCHIMP_EMAIL_ID/actions/schedule" \
--user "anystring:${MAILCHIMP_API_KEY}" \
  -d '{"schedule_time": '\""$MAILCHIMP_SCHEDULED_TIME"\"'}')
EXIT_CODE=$? receivedData 'Email Campaign scheduling response'

logDebug "$MAILCHIMP_EMAIL_SCHEDULE"
testMailchimpResponse "$MAILCHIMP_EMAIL_SCHEDULE"

# TODO:
# 1. Confrim Campaign is created, check content within

logInfo "$FULL_NAME completed successfully!"

exit 0
