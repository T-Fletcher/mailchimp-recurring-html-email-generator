#!/bin/bash

echo -e "[INFO] - Fetch a list of your Audience and Campaign Folder IDs for use in the .env variables."
echo -e "[NOTE] - This will collect the first 1000 items of each due to Mailchimp's API limitations."

echo -e "[NOTE] - You must add your Mailchimp API key and Server Prefix to '.env' for this to work."

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


AUDIENCE_FILENAME="mc-data-audience-ids.txt"
FOLDER_FILENAME="mc-data-folder-ids.txt"

# Get Mailchimp Audience list

echo -e "[INFO] - Fetching Audience names and IDs for your Mailchimp account...\n"

curl -sX GET \
"https://${MAILCHIMP_SERVER_PREFIX}.api.mailchimp.com/3.0/lists/?count=1000" \
--user "anystring:${MAILCHIMP_API_KEY}" \
-d '{"email_address":""}' | jq -r '.lists[] | "\(.id) - \(.name) "' >> "$AUDIENCE_FILENAME"

echo -e "[INFO] - Audience names and IDs saved to $AUDIENCE_FILENAME."


# Get Mailchimp Email Folder list

echo -e "[INFO] - Fetching Campaign Folder names and IDs for your Mailchimp account...\n"

curl -sX GET \
"https://${MAILCHIMP_SERVER_PREFIX}.api.mailchimp.com/3.0/campaign-folders/?count=1000" \
--user "anystring:${MAILCHIMP_API_KEY}" \
-d '{"email_address":""}' | jq -r '.folders[] | "\(.id) - \(.name) "' >> "$FOLDER_FILENAME"

echo -e "[INFO] - Campaign folder names and IDs saved to $FOLDER_FILENAME."
