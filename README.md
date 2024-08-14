# Mailchimp recurring HTML email generator

**Gathers HTML data from a URL and creates a new email campaign with it in Mailchimp, every day.**

## Requirements

**Required:**

- bash
- jq 1.7+ (earlier versions may work, untested)
- curl

**Optional:**

 - [Pantheon's terminus](https://docs.pantheon.io/terminus)

## Purpose

This script lets you generate and schedule recurring HTML emails in Mailchimp, with fresh content every time. 

Here's how:

1. It fetches HTML data via a curl request to your desired webpage
2. It parses the HTML response and ensures it's valid
3. It creates a Mailchimp email Template containing the HTML data via the Mailchimp API
4. It creates a new Mailchimp Campaign using the new Template, and optionally saves it under a folder if you've specified one
5. It schedules it to send to your nominated Mailchimp Audience
6. It cleans up and deletes the new Template since they're single use

We do it this way for several reasons:

1. Mailchimp Campaigns don't allow sending recurring emails out of the box. The only way to do this is via RSS feeds, and while Drupal Views allows creating RSS feeds with content, if you want to include any additional content in your feed, you're stuck - RSS Views only renders the Drupal Node's fields.
2. We can trigger recurring emails in Mailchimp using their Journey/Automation feature. It allows periodically sending recurring emails with content sourced from a URL, however it caches the data after the first run so it may be stale when next sent. This is because a Journey is processed per-subscriber, and may therefore require Mailchimp to retrieve the same data thousands of times.
3. Generating a new Template via flushing Drupal's cache and retrieving the KAR data via curl guarantees the data is fresh every time, while not overloading Mailchimp.

This script uses v3.0 of the Mailchimp API as of 9 August 2024.

Mailchimp API documentation: https://mailchimp.com/developer/marketing/api/


## Quick start

1. In your terminal, run `$ bash mc-get-asset-ids.sh` to get the Mailchimp Asset IDs for your Mailchimp Audience and Campaign folder
2. Add your chosen asset IDs to the `.env` file and populate the rest of the variables
3. Run `$ bash mc-generate.sh` to generate your Mailchimp email. 

## Environment variables

All variables except `DRUPAL_TERMINUS_SITE` are required.

```
DEBUG                        - boolean - defaults to false
EMAIL_CONTENT_URL            - string - URL to the webpage containing the data
MAILCHIMP_EMAIL_SHORT_NAME   - string - Some distinctive name without spaces e.g. star-wars
MAILCHIMP_SERVER_PREFIX      - string - Mailchimp URL prefix
MAILCHIMP_API_KEY            - string - Your Mailchimp API key
MAILCHIMP_TARGET_AUDIENCE_ID - string - Your Mailchimp Audience ID, get this via the API
MAILCHIMP_EMAIL_FOLDER_ID    - string - Optional - The ID of the Mailchimp Campaign folder to store the email in
MAILCHIMP_EMAIL_FROM         - string - The name of the sender of the email
MAILCHIMP_EMAIL_REPLYTO      - string - The email address to reply to
MAILCHIMP_EMAIL_TITLE        - string - The Campaign title in Mailchimp
MAILCHIMP_EMAIL_SUBJECT      - string - The email subject line
MAILCHIMP_EMAIL_DAILY_SEND_TIME_UTC - string - Optional - The time to send the email in UTC, e.g. 10:00
DRUPAL_TERMINUS_SITE         - string - Optional - Your Drupal website's Terminus alias, if any
DELETE_TEMPLATE_ON_CLEANUP   - boolean - Optional - Delete the Mailchimp Template when the script finishes to save clutter. Defaults to "false" for easier debugging but should be "true" for production
```

Read more about where these can be found:

 - [Mailchimp server prefix](https://mailchimp.com/developer/marketing/guides/quick-start/#make-your-first-api-call)
 - [Mailchimp API key](https://mailchimp.com/developer/marketing/guides/quick-start/#generate-your-api-key)


## Testing and debugging

To speed up testing, you can save a HTML sample in a file called `/test/test-data.html`. If `DEBUG` is enabled and the file exists, this data will be used instead of sending the `curl` request.

Debugging also pushed the CLI output to the terminal rather than saving it in a log file. It also includes more verbose information, such as entire curl responses for easier debugging.
