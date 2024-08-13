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
    local message=$1
    echo -e "[INFO] - $message"
}

function logWarning() {
    local message=$1
    echo -e "[WARNING] - $message"
}

function logDebug() {
    local message=$1
    if [[ $DEBUG == "true" ]]; then
        echo -e "[DEBUG] - $message"
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
DIR="$ROOT_DIR/$URL_NAME-logs-$NOW"
MAILCHIMP_ACTIVITY_DIR="$ROOT_DIR/$URL_NAME"
MAILCHIMP_EXECUTION_LOG_FILENAME="$URL_NAME-history.log"
MAILCHIMP_SCRIPT_LOGFILE="$MAILCHIMP_ACTIVITY_DIR/$URL_NAME-output-$NOW.log"
TEST_DATA="../test/test-data.html"

# Send script output to the logs, unless debug mode is enabled
if [[ ! $DEBUG == "true" ]]; then
    echo -e "Saving output logs to $MAILCHIMP_SCRIPT_LOGFILE..."
    exec > $MAILCHIMP_SCRIPT_LOGFILE 2>&1
else 
    MAILCHIMP_EMAIL_SHORT_NAME=$(echo "TEST--$MAILCHIMP_EMAIL_SHORT_NAME")
fi

logInfo "$FULL_NAME starting..."

if [[ ! -d $MAILCHIMP_ACTIVITY_DIR ]]; then
    mkdir $MAILCHIMP_ACTIVITY_DIR
fi

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

    # Remove Mailchimp Templates created by the script, whether by testing or not
    if [[ ! -z $MAILCHIMP_TEMPLATE_ID ]]; then
        curl -sX DELETE \
        "https://${MAILCHIMP_SERVER_PREFIX}.api.mailchimp.com/3.0/templates/$MAILCHIMP_TEMPLATE_ID" \
        --user "anystring:${MAILCHIMP_API_KEY}"
    fi

    rm -rf $DIR;
    rm -rf "$URL_NAME-logs*"
    rm -rf "html.tmp"
    
    logInfo "Clean up complete!"
    
    COMPLETE_TIME=$(date +%s)
    logInfo "Finished $FULL_NAME in $(($COMPLETE_TIME - $NOW_EPOCH)) seconds, at $(date -u +"%Y%m%dT%H:%M:%S%z")"
    code $MAILCHIMP_SCRIPT_LOGFILE
}

# Test log locations exist
if [[ ! -d $MAILCHIMP_ACTIVITY_DIR ]]; then
    logError "$MAILCHIMP_ACTIVITY_DIR directory not found, quitting..." 6
fi

if [[ -d $DIR ]]; then
    logInfo "Log folder '$DIR' already exists, deleting it to start fresh..."
    rm -rf $DIR
    EXIT_CODE=$? replaceLogFolder $DIR
    mkdir $DIR
else
    logInfo "Log folder not found, creating '$DIR'..."
    mkdir $DIR
fi

if [[ ! -d $DIR ]]; then
    logError "No $DIR found, quitting..." 3
fi

cd $DIR

logInfo "Switching to $DIR"

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

#TODO: Date should be in UTC, then converted to AEST
DATE=$(date "+%d %h %Y %H:%M:%S")
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
HTML_ENCODED=$(jq -Rs <<< "$HTML")
EXIT_CODE=$? receivedData 'HTML to JSON-safe string'

# Replace the quote wrappers with single quotes so it's valid JSON for Mailchimp
HTML_ENCODED="'${HTML_ENCODED:1:-1}'"

logInfo "Submitting encoded HTML data to Mailchimp to create a new Template..."
MAILCHIMP_CREATE_TEMPLATE=$(curl -sX POST \
  "https://${MAILCHIMP_SERVER_PREFIX}.api.mailchimp.com/3.0/templates" \
  --user "anystring:${MAILCHIMP_API_KEY}" \
  -d "{\"name\":\"$MAILCHIMP_EMAIL_SHORT_NAME template - $DATE_AEST\",\"folder_id\":\"\",\"html\": \"$HTML_ENCODED\"}")
EXIT_CODE=$? receivedData 'Template creation response'

logDebug "$MAILCHIMP_CREATE_TEMPLATE"

testMailchimpResponse "$MAILCHIMP_CREATE_TEMPLATE"

MAILCHIMP_TEMPLATE_ID=$(echo -e $MAILCHIMP_CREATE_TEMPLATE | jq -r ".id")
EXIT_CODE=$? receivedData "Template ID $MAILCHIMP_TEMPLATE_ID"


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
        "template_id": '"$MAILCHIMP_TEMPLATE_ID"'
    },
        "content_type": "template"
    }')
EXIT_CODE=$? receivedData 'Email Campaign creation response'

logDebug "$MAILCHIMP_EMAIL"

testMailchimpResponse "$MAILCHIMP_EMAIL"

# else 
#     logDebug "Debugging is enabled, skipping email creation..."
# fi

# TODO:
# 1. Test and escape DATE before passing to curl
# 2. Populate $DATE in email title and send time
# 2. Assign to valid mailing group segment 
# 3. Schedule to send
# 4. Confrim Campaign is created, check content within

logInfo "$FULL_NAME completed successfully!"

exit 0