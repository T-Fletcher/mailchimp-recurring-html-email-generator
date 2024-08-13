#!/bin/sh

# Some snippets for quickly testing various API calls
#* Offical Mailchimp API doco: https://mailchimp.com/developer/marketing/api

if [[ -f "../.env" ]]; then
    source "../.env"
    if [[ $DEBUG == "true" ]]; then
        echo -e "[DEBUG] - DEBUG mode is enabled"
    fi
else
    echo -e "[ERROR] - Environment variable file '.env' does not exist in the project root directory.
    You can create one by copying '.env.example'.";
    exit 1
fi

MAILCHIMP_SERVER_PREFIX=$MAILCHIMP_SERVER_PREFIX
MAILCHIMP_API_KEY=$MAILCHIMP_API_KEY
MAILCHIMP_TARGET_AUDIENCE_ID=$MAILCHIMP_TARGET_AUDIENCE_ID
CAMPAIGN_ID=""
JOURNEY_ID=""

##* Uncomment whatever command you want to test

# Get all email Campaigns

# curl -sX GET \
# "https://${MAILCHIMP_SERVER_PREFIX}.api.mailchimp.com/3.0/campaigns/" \
# --user "anystring:${MAILCHIMP_API_KEY}" \
# -d '{"email_address":""}'  | jq -r ".campaigns[]"


# Get specific Journey/automation

# curl -sX GET \
#   "https://${MAILCHIMP_SERVER_PREFIX}.api.mailchimp.com/3.0/customer-journeys/journeys/${JOURNEY_ID}/" \
#   --user "anystring:${MAILCHIMP_API_KEY}" \
#   -d '{"email_address":""}'  | jq -r "."


# Get all email Campaigns since X date

# curl -sX GET \
#   "https://${MAILCHIMP_SERVER_PREFIX}.api.mailchimp.com/3.0/campaigns/?since_create_time=2024-08-07T00:00:00+00:00" \
#   --user "anystring:${MAILCHIMP_API_KEY}" \
#   -d '{"email_address":""}'  | jq -r ".campaigns[]"


# Get all Automation emails

# curl -sX GET \
#   "https://${MAILCHIMP_SERVER_PREFIX}.api.mailchimp.com/3.0/campaigns/?type=automation-email" \
#   --user "anystring:${MAILCHIMP_API_KEY}" \
#   -d '{"email_address":""}'  | jq -r ".campaigns[]"


# Get a Campaign's data

# curl -sX GET \
#   "https://${MAILCHIMP_SERVER_PREFIX}.api.mailchimp.com/3.0/campaigns/$CAMPAIGN_ID" \
#   --user "anystring:${MAILCHIMP_API_KEY}"  | jq -r "."


# Get a Campaign's  email content

# curl -sX GET \
#   "https://${MAILCHIMP_SERVER_PREFIX}.api.mailchimp.com/3.0/campaigns/$CAMPAIGN_ID/content" \
#   --user "anystring:${MAILCHIMP_API_KEY}" | jq -r "."


# Get all email Lists/Audiences

# curl -sX GET \
# "https://${MAILCHIMP_SERVER_PREFIX}.api.mailchimp.com/3.0/lists/" \
# --user "anystring:${MAILCHIMP_API_KEY}" \
# -d '{"email_address":""}'  | jq -r "."


# Update an existing Campaign

# curl -sX PATCH \
#   "https://${MAILCHIMP_SERVER_PREFIX}.api.mailchimp.com/3.0/campaigns/$CAMPAIGN_ID/" \
#   --user "anystring:${MAILCHIMP_API_KEY}" \
#   -d '{"settings": {"title":"TESTING"}}'  | jq -r "."


# Schedule a Campaign

# curl -sX POST \
# "https://${MAILCHIMP_SERVER_PREFIX}.api.mailchimp.com/3.0/campaigns/$CAMPAIGN_ID/actions/schedule" \
#   --user "anystring:${MAILCHIMP_API_KEY}" \
#   -d '{"schedule_time":"2024-08-08T03:45:00+00:00","timewarp":false,"batch_delivery":{"batch_delay":5,"batch_count":2}}' \
#   | jq -r "."


# Create a new Template

# curl -sX POST \
#   "https://${MAILCHIMP_SERVER_PREFIX}.api.mailchimp.com/3.0/templates" \
#   --user "anystring:${MAILCHIMP_API_KEY}" \
#   -d "{\"name\":\"TEST Template\",\"folder_id\":\"\",\"html\": \"$CONTENT\"}"


# Get all email Campaign folders

# curl -sX GET \
# "https://${MAILCHIMP_SERVER_PREFIX}.api.mailchimp.com/3.0/campaign-folders/?count=1000" \
# --user "anystring:${MAILCHIMP_API_KEY}" \
# -d '{"email_address":""}'  | jq -r "."