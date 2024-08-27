#!/bin/bash

### MAILCHIMP RECURRING HTML EMAIL GENERATOR

# ====================
# Author: Tim Fletcher
# Date: 2024-08-16
# Licence: GPL-3.0
# Source location: https://github.com/T-Fletcher/mailchimp-recurring-html-email-generator
# ====================

# @TODO:
#
# 1. Validate incoming HTML via Tidy
# 2. Expand scheduling options to include weekly, fortnightly and monthly
# 3. Map out Exit codes in README

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

function useDate() {
    if date --version >/dev/null 2>&1 ; then
        # OS uses GNU date
        TZ="$TIMEZONE" date "$@"
    else
        # OS uses non-GNU date, sending date command to gdate
        # https://apple.stackexchange.com/questions/231224/how-to-have-gnus-date-in-os-x
        gdate --version >/dev/null 2>&1
        EXIT_CODE=$?
        if [[ $EXIT_CODE -ne 0 ]]; then
            logWarning "GNU date not found, date commands may not work as expected"
            logWarning "See https://apple.stackexchange.com/questions/231224/how-to-have-gnus-date-in-os-x"
        fi
        TZ="$TIMEZONE" gdate "$@"
    fi
}

# NOTE: All times are in UTC unless the TIMEZONE env var is set
NOW=$(useDate -u +"%Y%m%dT%H:%M:%S%z")
NOW_EPOCH=$(useDate +"%s")
TIME_OFFSET=$(useDate +"%z");

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
        return 1
    else 
        return 0
    fi
}

function testMailchimpResponse() {
    #* Mailchimp API errors doco: 
    #* https://mailchimp.com/developer/marketing/docs/errors/

    local response=$@

    if [[ "$@" == "" && -z $1 ]];then
        logInfo "Successful empty response received from Mailchimp"
        return 0
    fi

    local responseType=$(jq -r ".type" <<<$response)
    local responseStatus=$(jq -r ".status" <<<$response)

    if [[ $reponseType == 'https://mailchimp.com/developer/marketing/docs/errors/' ]];then
        logError "Error response received from MailChimp, quitting..." $response
        return 1
        # If the response status is a number AND a non-200 HTTP code
    elif [[ $responseStatus =~ ^[0-9]+$ ]]; then
        if [[ $responseStatus -lt 200 || $responseStatus -gt 299 ]]; then
            logWarning "Received HTTP response '$responseStatus' from Mailchimp! Quitting..."
            logError "$response"
            return 1
        fi
        return 0
    else 
        logInfo "Response from Mailchimp:"
        echo -e "$response"
        return 0
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

function isDateValidISO8601() {    
    useDate "+%Y-%m-%dT%H:%M:%S%z" -d $1
    EXIT_CODE=$? 

    if [[ $EXIT_CODE -ne 0 ]]; then
        logWarning "Invalid ISO 8601 date format: '$1', expected 'Y-m-dTH:M:Sz'"
        return 1
    else 
        return 0
    fi
}

function hasDatePassed() {
    isDateValidISO8601 $1
    EXIT_CODE=$? 
    if [[ $EXIT_CODE -ne 0 ]]; then
        logError "Invalid date provided, quitting..."
    fi

    local NOW=$(useDate -u +%s);
    local GIVEN_DATE=$(useDate -d $1 +%s);

    # Check if NOW is greater, so it fails if an invalid date is passed in
    if [[ $NOW -gt $GIVEN_DATE ]]; then
        logWarning "'$1' is in the past!"
        return 1
    else 
        return 0
    fi
}


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

if [[ -z $TIMEZONE ]]; then
    logWarning "No TZ code in TIMEZONE environment variable is not set, defaulting to UTC"
    TIMEZONE="UTC"
else 
    echo -e "Timezone set to: $TIMEZONE"
fi

if [[ -z $MAILCHIMP_EMAIL_DAILY_SEND_TIME ]]; then
    logError "No send time set in MAILCHIMP_EMAIL_DAILY_SEND_TIME environment variable, quitting..." 3
fi

if [[ -z $MAILCHIMP_TARGET_AUDIENCE_ID ]]; then
    logWarning "Target Mailchimp Audience ID environment variable is missing! 
    The Template will still be generated but no emails will be created or sent."
fi

if [[ -z $DRUPAL_TERMINUS_SITE ]]; then
    logWarning "Terminus site environment variable is not set!
    Let's assume your URL isn't from a Pantheon Drupal website."
    if [[ -z $INCLUDE_CACHEBUSTER ]]; then
        logWarning "You apparently aren't using Pantheon Drupal OR including a cachebuster suffix. 
        You can proceed but will need to handle clearing your website's 
        cache some other way, or you may recieve stale data."
    logWarning "You can add a timestamp cachebuster to the initial HTML data curl request 
        by setting INCLUDE_CACHEBUSTER=\"true\" in your environment variables"
    fi
fi

if [[ ! -z $INCLUDE_CACHEBUSTER && $INCLUDE_CACHEBUSTER == "true" ]]; then
    logInfo "Adding a cachebuster suffix to the initial HTML data curl request"
    EMAIL_CONTENT_URL="${EMAIL_CONTENT_URL}?cachebuster=$(useDate +%s)"
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
        logInfo "$(useDate -u +"%Y%m%dT%H:%M:%S%z") - [FAIL] - $FULL_NAME failed to complete, exit code: $EXIT_CODE.\n See $MAILCHIMP_SCRIPT_LOGFILE for more details." >> $MAILCHIMP_EXECUTION_LOG_FILENAME
    else
        logInfo "$(useDate -u +"%Y%m%dT%H:%M:%S%z") - [SUCCESS] - $FULL_NAME completed successfully.\n See $MAILCHIMP_SCRIPT_LOGFILE for more details." >> $MAILCHIMP_EXECUTION_LOG_FILENAME
    fi
    
    rm -rf $TEMP_DIR;
    rm -rf "html.tmp"

    if [[ ! -z $MAILCHIMP_TEMPLATE_ID && -z $DELETE_TEMPLATE_ON_CLEANUP || $DELETE_TEMPLATE_ON_CLEANUP == "true" ]]; then
        logInfo "Removing Mailchimp Templates created by the script, whether by testing or not"
        curl -sX DELETE \
        "https://${MAILCHIMP_SERVER_PREFIX}.api.mailchimp.com/3.0/templates/$MAILCHIMP_TEMPLATE_ID" \
        --user "anystring:${MAILCHIMP_API_KEY}"
    fi

    logInfo "Clean up complete!"
    
    COMPLETE_TIME=$(useDate +%s)
    logInfo "Finished $FULL_NAME in $(($COMPLETE_TIME - $NOW_EPOCH)) seconds, at $(useDate -u +"%Y%m%dT%H:%M:%S%z")"
    
    if [[ $DEBUG == "true" ]]; then
        if ! code >/dev/null 2>&1; then
            logDebug "Opening log file from this run (requires 'code' alias to open your editor of choice)..."
            code $MAILCHIMP_SCRIPT_LOGFILE
        fi
    fi
    return 0
}

function deleteEmail() {
    EMAIL_ID=$1
    logInfo "Deleting Email Campaign..."

    curl -sX DELETE \
    "https://${MAILCHIMP_SERVER_PREFIX}.api.mailchimp.com/3.0/campaigns/$EMAIL_ID" \
    --user "anystring:${MAILCHIMP_API_KEY}"
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

DATE=$(useDate +"%d %h %Y")
DATETIME=$(useDate +"%d %h %Y %H:%M:%S")

logInfo "Using '$DATE' for the email subject line and '$DATETIME' for the email name."

if [[ $DEBUG == "true" && -f $TEST_DATA ]]; then
    logDebug "Using data from '$TEST_DATA'..."
    logWarning "Note if $TEST_DATA contains broken HTML, unexpected things may happen..."
    HTML=$(<$TEST_DATA)
    EXIT_CODE=$? receivedData 'HTML test data'
else    
    logInfo "Sourcing data from '$EMAIL_CONTENT_URL'"
    HTML=$(curl -sf "$EMAIL_CONTENT_URL")
    EXIT_CODE=$? receivedData 'HTML data'
fi

logInfo "Data:\n$HTML"

# TODO: HTML validation before proceeding with template generation

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
    "name": '\""$MAILCHIMP_EMAIL_SHORT_NAME template - $DATETIME"\"',
    "folder_id": "",
    "html": '$HTML_ENCODED'
}'

logInfo "Data to be submitted to Mailchimp to generate the Campaign:"
logInfo $MAILCHIMP_CAMPAIGN_DATA

logInfo "Submitting encoded HTML data to Mailchimp to create a new Template..."

MAILCHIMP_CREATE_TEMPLATE=$(curl -sX POST \
  "https://${MAILCHIMP_SERVER_PREFIX}.api.mailchimp.com/3.0/templates" \
  --user "anystring:${MAILCHIMP_API_KEY}" \
  -d "${MAILCHIMP_CAMPAIGN_DATA}")
EXIT_CODE=$? receivedData 'Template creation response'

testMailchimpResponse "$MAILCHIMP_CREATE_TEMPLATE"
EXIT_CODE=$? receivedData "Mailchimp template"

MAILCHIMP_TEMPLATE_ID=$(echo -e $MAILCHIMP_CREATE_TEMPLATE | jq -r ".id")
EXIT_CODE=$? receivedData "Template ID $MAILCHIMP_TEMPLATE_ID"

logInfo "Creating new Email Campaign from the new Template..."

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
        "subject_line": '\""$MAILCHIMP_EMAIL_SUBJECT: $DATE"\"',
        "preview_text": "",
        "title": '\""$MAILCHIMP_EMAIL_TITLE - $DATETIME"\"',
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
EXIT_CODE=$? receivedData "Mailchimp email"

logInfo "Email Campaign created successfully"

MAILCHIMP_EMAIL_ID=$(echo -e "$MAILCHIMP_EMAIL" | jq -r ".id")

# Lastly, schedule the new Email Campaign to be sent

TODAY=$(useDate -u +"%Y-%m-%d")

MAILCHIMP_SCHEDULED_TIME="${TODAY}T${MAILCHIMP_EMAIL_DAILY_SEND_TIME}${TIME_OFFSET}"
logInfo "Scheduled send time in $TIMEZONE time: $MAILCHIMP_SCHEDULED_TIME"

# Only schedule the Email Campaign if debugging is disabled
# This prevents test content accidentally being sent
if [[ ! $DEBUG == "true" ]]; then
    logInfo "Checking '$MAILCHIMP_SCHEDULED_TIME' is in the future (unless you're Marty McFly)..."
    hasDatePassed $MAILCHIMP_SCHEDULED_TIME
    EXIT_CODE=$?


    if [[ $EXIT_CODE -ne 0 ]]; then
        # Note certain times will always appear to have passed relative to when
        # the script is run e.g. 7:00 UTC will always fail if the script runs at
        # 8:00 UTC. In these cases, we add +1 day as it's assumed it's meant for 
        # the following day
        logWarning "Email Campaign scheduled date is in the past, adding +1 day so it schedules for tomorrow..."
        MAILCHIMP_SCHEDULED_TIME=$(useDate -d "$MAILCHIMP_SCHEDULED_TIME +1 day" +"%Y-%m-%dT%H:%M:%S%z")
        logInfo "New scheduled date: '$MAILCHIMP_SCHEDULED_TIME'"
        
        hasDatePassed $MAILCHIMP_SCHEDULED_TIME
        EXIT_CODE=$?

        if [[ $EXIT_CODE -ne 0 ]]; then
            logWarning "$MAILCHIMP_SCHEDULED_TIME still in the past! Quitting..."
            deleteEmail $MAILCHIMP_EMAIL_ID
            exit 1
        fi
    fi

    logInfo "Scheduling the new Email Campaign..."

    MAILCHIMP_EMAIL_SCHEDULE=$(curl -sX POST \
    "https://${MAILCHIMP_SERVER_PREFIX}.api.mailchimp.com/3.0/campaigns/$MAILCHIMP_EMAIL_ID/actions/schedule" \
    --user "anystring:${MAILCHIMP_API_KEY}" \
    -d '{"schedule_time": '\""$MAILCHIMP_SCHEDULED_TIME"\"'}')
    EXIT_CODE=$? receivedData "Mailchimp email schedule"

    testMailchimpResponse $MAILCHIMP_EMAIL_SCHEDULE

    logInfo "Email Campaign scheduled successfully!"
else
    logInfo "DEBUG mode enabled, skipping scheduling email."
fi

logInfo "$FULL_NAME completed successfully!"
exit 0
