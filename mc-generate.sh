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
    echo -e "[DEBUG] - $message"
}

# Handle responses when requesting data 
function receivedData() {
    local message=$1
    if [[ $EXIT_CODE -ne 0 ]]; then
        logError "Failed to get $message" $EXIT_CODE
    fi
}

function testResponseStatus() {
    local responseStatus=$1
    if [[ $responseStatus == "" || $responseStatus == "null" ]] ;then
        logInfo "No response status received from successful 0 exit code, assuming it's fine..."
    elif [[ $responseStatus -lt 200 || $responseStatus -gt 299 ]]; then
        logError "Non-200 response code '$responseStatus' received from successful 0 exit code! Quitting..." $responseStatus
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

if [[ $DEBUG == "true" && -f $TEST_DATA ]]; then
    logDebug "Using data from '$TEST_DATA'..."
    HTML=$(<$TEST_DATA)
    EXIT_CODE=$? receivedData 'HTML test data'
    logDebug "Data:\n$HTML"
else
    logInfo "Sourcing data from '$EMAIL_CONTENT_URL'"
    HTML=$(curl -s "$EMAIL_CONTENT_URL")
    EXIT_CODE=$? receivedData 'HTML data'
fi

logInfo "Encoding HTML data as a JSON-safe string"
HTML_ENCODED=$(jq -Rs <<< "$HTML")
EXIT_CODE=$? receivedData 'HTML to JSON-safe string'

# Replace the quote wrappers with single quotes so it's valid JSON for Mailchimp
HTML_ENCODED="'${HTML_ENCODED:1:-1}'"

logInfo "Submitting encoded HTML data to Mailchimp to create a new Template..."
MAILCHIMP_TEMPLATE_RESPONSE=$(curl -sX POST \
  "https://${MAILCHIMP_SERVER_PREFIX}.api.mailchimp.com/3.0/templates" \
  --user "anystring:${MAILCHIMP_API_KEY}" \
  -d "{\"name\":\"$MAILCHIMP_EMAIL_SHORT_NAME template - $DATE\",\"folder_id\":\"\",\"html\": \"$HTML_ENCODED\"}")
EXIT_CODE=$? receivedData 'Template creation response'

MAILCHIMP_TEMPLATE_STATUS=$(echo $MAILCHIMP_TEMPLATE_RESPONSE | jq -r ".status")

# Test the Mailchimp response was successful, as it may return a 0 exit code
# then include an error response
testResponseStatus $MAILCHIMP_TEMPLATE_STATUS

MAILCHIMP_TEMPLATE_ID=$(echo $MAILCHIMP_TEMPLATE_RESPONSE | jq -r ".id")
EXIT_CODE=$? receivedData "Template ID $MAILCHIMP_TEMPLATE_ID"

# curl -X GET \
#   "https://${MAILCHIMP_SERVER_PREFIX}.api.mailchimp.com/3.0/templates/$MAILCHIMP_TEMPLATE_ID" \
#   --user "anystring:${MAILCHIMP_API_KEY}"

# MAILCHIMP_EMAIL=$(curl -X GET \
#   "https://${MAILCHIMP_SERVER_PREFIX}.api.mailchimp.com/3.0/templates/$MAILCHIMP_TEMPLATE_ID" \
#   --user "anystring:${MAILCHIMP_API_KEY}")
# EXIT_CODE=$? receivedData 'Email creation response'



# TODO:
# 1. Get template ID
# 2. Generate new Campaign with ID, schedule to send
# 3. Confrim Campaign is created, check content within
# 5. Delete the Template

logInfo "$FULL_NAME completed successfully!"

exit 0