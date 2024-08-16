# Mailchimp recurring HTML email generator

**A CLI tool that gathers HTML data from a URL and uses it to create and schedule a new email campaign in Mailchimp (requires an active account).**

This script is for for Mailchimp users who want to:

1. Manage their email content as a HTML webpage (such as via a CMS), and
2. Ensure their email contains the latest content every time, and
3. Send it to a specific Audience as a recurring email.

## Contents
- [Mailchimp recurring HTML email generator](#mailchimp-recurring-html-email-generator)
  - [Contents](#contents)
  - [Introduction](#introduction)
  - [Requirements](#requirements)
  - [Quick start](#quick-start)
  - [How it works](#how-it-works)
  - [When is this useful?](#when-is-this-useful)
  - [Gotchas](#gotchas)
  - [Testing and debugging](#testing-and-debugging)
  - [Environment variables](#environment-variables)

## Introduction

It automates the process of creating a regular email campaign in Mailchimp's UI via their API. A new email campaign will be created *every time this script successfully runs*.

If you're using Pantheon Drupal, it integrates with Terminus to clear the cache before fetching the HTML data. If not, you can use the `INCLUDE_CACHEBUSTER` flag or handle cache clearing yourself.

To make the email recurring e.g. hourly, daily, weekly etc, you can schedule the script to run periodically via a daily `cron` task. Note that the send time (`MAILCHIMP_EMAIL_DAILY_SEND_TIME_UTC`) must be one of 15 minute intervals for Mailchimp to schedule it i.e. `00:00`, `00:15`, `00:30`, `00:45` etc.

> The scheduled time the email is sent will be applied to whatever day the script is run, and only if it's in the future - running this script at 10am to schedule a 9am email won't work.

This script uses [v3.0 of the Mailchimp API](https://mailchimp.com/developer/marketing/api/) as of 9 August 2024.


## Requirements

**Required:**

- bash
- GNU date, or gdate - not BSD date
- jq 1.7+ (earlier versions may work, untested)
- curl
- An active Mailchimp account

**Optional:**

 - [Pantheon's terminus](https://docs.pantheon.io/terminus)


## Quick start

1. Rename the `.env.example` file to `.env`
2. Get your [Mailchimp server prefix](https://mailchimp.com/developer/marketing/guides/quick-start/#make-your-first-api-call) and add it to `.env`
3. Get your [Mailchimp API key](https://mailchimp.com/developer/marketing/guides/quick-start/#generate-your-api-key) and add it to `.env`
4. In your terminal, run `$ bash mc-get-asset-ids.sh` to get the Mailchimp Asset IDs for your Mailchimp Audience and Campaign folder
5. Add your chosen asset IDs to the `.env` file and populate the rest of the variables
6. Run `$ bash mc-generate.sh` to generate and schedule your Mailchimp HTML Email Campaign.


## How it works

1. It fetches HTML data via a `curl` request to your desired webpage
<!-- TODO: 2. It parses the HTML response and ensures it's valid -->
3. It creates a Mailchimp email Template containing the HTML data via the Mailchimp API
4. It creates a new Mailchimp Campaign using the new Template, and optionally saves it under an Campaign folder (if you've specified one)
5. It schedules it to send to your nominated Mailchimp Audience at a time of your choosing
6. It cleans up all script artifacts and deletes the new Template since they're single use


## When is this useful? 

Doesn't Mailchimp already offer recurring HTML emails? HTML emails yes, recurring - sort of... this solution has arisen from many small blockers:

1. The only way to send recurring HTML emails (at the time of writing) is via an RSS Feeds Campaign
   1. The only way to send a recurring 'HTML' email is to somehow serve an RSS feed that contains only one item, with all the desired email HTML within that item. Eww.
   2. If you're using Drupal to host your email webpage, Views allows creating RSS feeds with content. However if you want to include any additional content in your feed such as Blocks, you're stuck - RSS Views only renders the Drupal Node's fields and not any related entities.
      
2. Email Campaigns provide the simple 'Import content from a URL' feature, but can't be scheduled to be recurring. This *can* be done via some clever use of their Journey/Automation feature:
   1. You can create 'Journey 1', which sends the email and then adds the tag 'Journey 2'. Journey 2 is triggered by that tag and removes it, then sends the email and adds the 'Journey 1' tag again etc (as Mailchimp Journeys can't trigger themselves). You can also include a 'Delay' step 1 day to make the email daily
   2. This allows periodically sending recurring emails with content sourced from a URL, *however it caches the data after the first run so it may be stale when next sent*. This is because a Journey is processed *per-subscriber*, and may therefore require Mailchimp to retrieve the same data thousands of times - and they'd be crazy to.

There you go, all caught up.

Generating a new Mailchimp Template by flushing Drupal's cache (if you're using Drupal) and retrieving the HTML data via curl guarantees the data is fresh every time, while not overloading Mailchimp.

> Note that if the content you wish to email will never be updated more frequently than every few days, the Mailchimp cache issue may not be a problem and Journeys are the way to go - you won't need to run this script on a server somewhere.


## Gotchas

This is written to run in environments with access to GNU `date` or `gdate` (available on MacOS via the `coreutils` brew package). If you're running in a Unix environment without GNU `date` or `gdate`, `date` commands may fail due to incompatible flags.

## Testing and debugging

To speed up testing, you can save a HTML sample in a file called `/test/test-data.html`. If `DEBUG` is enabled and the file exists, this data will be used instead of sending the `curl` request.


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
