# Mailchimp recurring HTML email generator

**A CLI tool that gathers HTML data from a URL and uses it to create and schedule a new email campaign in Mailchimp (requires an active account).**

This script is for for Mailchimp users who want to:

1. Manage their email content as a HTML webpage (such as publishing it via a CMS), and
2. Ensure their email contains the latest content every time, and 
3. Send it to a specific Audience as a recurring email.

## Contents
- [Mailchimp recurring HTML email generator](#mailchimp-recurring-html-email-generator)
  - [Contents](#contents)
  - [Introduction](#introduction)
  - [Requirements](#requirements)
  - [Quick start](#quick-start)
  - [How it works, and why bother](#how-it-works-and-why-bother)
  - [Testing and debugging](#testing-and-debugging)
  - [Environment variables](#environment-variables)

## Introduction

It automates the process of creating a regular email campaign in Mailchimp's UI via their API. A new email campaign will be created every time this script runs.

If you're using Pantheon Drupal, it integrates with Terminus to clear the cache before fetching the HTML data. If not, you can use the `INCLUDE_CACHEBUSTER` flag or handle cache clearing yourself. 

To make the email recurring e.g. hourly, daily, weekly etc, you can schedule the script to run periodically via a daily `cron` task. Note that the send time (`MAILCHIMP_EMAIL_DAILY_SEND_TIME_UTC`) must be one of 15 minute intervals for Mailchimp to schedule it i.e. `00:00`, `00:15`, `00:30`, `00:45` etc.

> The scheduled time the email is sent will be applied to whatever day the script is run, and only if it's in the future - running this script at 10am to schedule a 9am email will create the email but it won't be scheduled to send.

This script uses [v3.0 of the Mailchimp API](https://mailchimp.com/developer/marketing/api/) as of 9 August 2024.


## Requirements

**Required:**

- bash
- jq 1.7+ (earlier versions may work, untested)
- curl
- An active Mailchimp account

**Optional:**

 - [Pantheon's terminus](https://docs.pantheon.io/terminus)


## Quick start

Read more about where these can be found:

1. Rename the `.env.example` file to `.env`
2. Get your [Mailchimp server prefix](https://mailchimp.com/developer/marketing/guides/quick-start/#make-your-first-api-call) and add it to `.env`
3. Get your [Mailchimp API key](https://mailchimp.com/developer/marketing/guides/quick-start/#generate-your-api-key) and add it to `.env`
4. In your terminal, run `$ bash mc-get-asset-ids.sh` to get the Mailchimp Asset IDs for your Mailchimp Audience and Campaign folder
5. Add your chosen asset IDs to the `.env` file and populate the rest of the variables
6. Run `$ bash mc-generate.sh` to generate your Mailchimp email. 


## How it works, and why bother

This script lets you generate and schedule HTML emails in Mailchimp, with fresh content every time.

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

> If the content you wish to email will never be updated more frequently than every few days, the Mailchimp cache issue may not be a problem and Journeys are the way to go.


## Testing and debugging

To speed up testing, you can save a HTML sample in a file called `/test/test-data.html`. If `DEBUG` is enabled and the file exists, this data will be used instead of sending the `curl` request.

Debugging also pushed the CLI output to the terminal rather than saving it in a log file. It also includes more verbose information, such as entire curl responses for easier debugging.


## Environment variables

All variables are required except those marked as 'optional'.

```
DEBUG                                   - boolean - false
    Sends script output to the console 
    instead of the logs, outputs more 
    verbose info

EMAIL_CONTENT_URL                       - string
    URL to the webpage containing the
    data

MAILCHIMP_EMAIL_SHORT_NAME              - string
    Some distinctive name without 
    spaces e.g. star-wars, used in 
    file naming

MAILCHIMP_SERVER_PREFIX                 - string
    Mailchimp URL prefix

MAILCHIMP_API_KEY                       - string
    Your Mailchimp API key

MAILCHIMP_TARGET_AUDIENCE_ID            - string
    Your Mailchimp Audience ID, get
    this via running mc-get-asset-ids.sh

MAILCHIMP_EMAIL_FOLDER_ID               - string - optional
    The ID of the Mailchimp Campaign 
    folder to store the email in

MAILCHIMP_EMAIL_FROM                    - string
    The name of the sender of the email

MAILCHIMP_EMAIL_REPLYTO                 - string
    The email address to reply to

MAILCHIMP_EMAIL_TITLE                   - string
    The Campaign title in Mailchimp

MAILCHIMP_EMAIL_SUBJECT                 - string
    The email subject line

MAILCHIMP_EMAIL_DAILY_SEND_TIME_UTC     - string - optional
    The time to send the email in
    UTC, e.g. 10:00

INCLUDE_CACHEBUSTER                     - boolean - optional
    Whether to include a timestamp
    cachebuster in the URL to prevent
    HMTL email content caching

DRUPAL_TERMINUS_SITE                    - string - optional
    Your Drupal website's Terminus
    alias, if any

DELETE_TEMPLATE_ON_CLEANUP              - boolean - false
    Delete the Mailchimp Template 
    when the script finishes to save
    clutter. Defaults to "false" for
    easier debugging but should be 
    "true" for production
```
