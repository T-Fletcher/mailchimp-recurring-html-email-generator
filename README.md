# Mailchimp recurring HTML email generator

**A CLI tool that gathers HTML data from a URL and uses it to create and schedule a new email campaign in Mailchimp (requires an active account).**

This script is for for Mailchimp users who want to:

1. Manage their email content as a HTML webpage (such as via a CMS), and
2. Ensure their email contains the latest content every time, and
3. Send it to a specific Audience as a recurring email at a certain time.
4. Saves logs to an AWS S3 bucket (optional)

## Contents
- [Mailchimp recurring HTML email generator](#mailchimp-recurring-html-email-generator)
  - [Contents](#contents)
  - [Introduction](#introduction)
  - [Requirements](#requirements)
  - [Quick start](#quick-start)
  - [How it works](#how-it-works)
  - [When is this useful?](#when-is-this-useful)
  - [Gotchas](#gotchas)
    - [Date flags](#date-flags)
    - [Scheduling emails for times that land in the past](#scheduling-emails-for-times-that-land-in-the-past)
  - [Logging](#logging)
    - [Failure notifications](#failure-notifications)
    - [Saving logs in an AWS S3 bucket](#saving-logs-in-an-aws-s3-bucket)
  - [Testing and debugging](#testing-and-debugging)
  - [Environment variables](#environment-variables)

## Introduction

It automates the process of creating a regular email campaign in Mailchimp's UI via their API. A new email campaign will be created *every time this script successfully runs*.

If you're using Pantheon Drupal, it integrates with Terminus to clear the cache before fetching the HTML data. If not, you can use the `INCLUDE_CACHEBUSTER` flag or handle cache clearing yourself.

To make the email recurring e.g. hourly, daily, weekly etc, you can schedule the script to run periodically via a daily `cron` task. Note that the send time (`MAILCHIMP_EMAIL_DAILY_SEND_TIME`) must be one of 15 minute intervals for Mailchimp to schedule it i.e. `00:00`, `00:15`, `00:30`, `00:45` etc.

Be sure to prefix your cron task with a `CRON='true'` environment variable to ensure the script captures when it's being run via cron, e.g. 

```bash
CRON='true'
28 00 * * * cd /path/to/mailchimp-recurring-html-email-generator; bash mc-generate.sh
```


> The scheduled time the email is sent will be applied to whatever day the script is run. If the scheduled time has already passed e.g. 10am to send a 9am email, the email is scheduled for 1 day in the future.

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
- aws-cli (optional, for S3 logging. Assumes you are logged into `aws-cli` as a user with `write` permissions to this bucket)


## Quick start

1. Rename the `.env.example` file to `.env`
2. Get your [Mailchimp server prefix](https://mailchimp.com/developer/marketing/guides/quick-start/#make-your-first-api-call) and add it to `.env`
3. Get your [Mailchimp API key](https://mailchimp.com/developer/marketing/guides/quick-start/#generate-your-api-key) and add it to `.env`
4. In your terminal, run `$ bash mc-get-asset-ids.sh` to get the Mailchimp Asset IDs for your Mailchimp Audience and Campaign folder
5. Add your chosen asset IDs to the `.env` file and populate the rest of the variables
6. Run `$ bash mc-generate.sh` to generate and schedule your Mailchimp HTML Email Campaign.

**For scheduling periodic emails, use a cron job:**

7. Open your crontab: `$ crontab -e`
8. Add the location of your installed tooling in a `PATH` variable, so the cron task can access them (example from an AWS EC2 instance):
    ```
    PATH=/home/ec2-user/.local/bin:/home/ec2-user/bin:/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/home/ec2-user/.composer/vendor/bin:/home/ec2-user/terminus/terminus
    ```
9. Add a variable called `CRON='true'` (this is used to determine if the script is being run via cron or manually):
    ```
    CRON='true'
    ```
10. On the next line, add a cron job to run the script at the desired interval, e.g. daily at 10am UTC:
    ```
    0 10 * * * cd /path/to/mailchimp-recurring-html-email-generator; bash mc-generate.sh
    ```

The email subject line will be the combination of `MAILCHIMP_EMAIL_SUBJECT: `, the current date in `d h Y` format, and ` MAILCHIMP_EMAIL_SUBJECT_SUFFIX` e.g.

> "A catchy subject line sent at: 2 Nov 2024 and remember, you're awesome!"

> "Our staff newsletter: 15 Feb 2025 - for internal use only"

## How it works

1. It fetches HTML data via a `curl` request to your desired webpage
2. It creates a Mailchimp email Template containing the HTML data via the Mailchimp API
3. It creates a new Mailchimp Campaign using the new Template, and optionally saves it under an Campaign folder (if you've specified one)
4. It schedules it to send to your nominated Mailchimp Audience at a time of your choosing (must be in 15 minute increments, see [Introduction](#introduction))
5. It cleans up all script artifacts and deletes the new Template since they're single use
6. Finally, it compresses the script log files and sends them to an AWS S3 bucket, should you include one in `.env`. *Note* this requires `aws-cli` installed and signed in on the script's local server


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

### Date flags

This is written to run in environments with access to GNU `date` or `gdate` (available on MacOS via the `coreutils` brew package). If you're running in a Unix environment without GNU `date` or `gdate`, `date` commands may fail due to incompatible flags.

### Scheduling emails for times that land in the past

You can't schedule emails to send in the past. 

To avoid confusion, ensure the ‘scheduled send’ time env variable uses the same timezone specified in `.env`.

Before attempting to schedule the email in Mailchimp, the script tests if the scheduled email time is in the past. If it is, it assumes the schedule is intended for tomorrow and will add `+1 day` then test it again. 

This is handles not knowing when a user may want to run the script, including when they are testing.

You may still run into problems when using dates in timezones affected by Daylight Savings (DLS) e.g. `AEST`, and if running this script at a time close to midnight e.g. `10:00 AEST` = `00:00 UTC`. This is because of how the script handles date comparisons. For example:

Running the script at 9:30am Darwin time means it runs right before midnight UTC. This means:

1. the ‘current time’ is always ‘yesterday’ in relation to the send time, as it runs at 9:28am Darwin time (23:58 UTC on the previous day)
2. the ‘scheduled time’ is therefore always considered to be in the past because it’s compared to the previous day in UTC
3. the ‘scheduled time’ hours included in .env could be in any timezone you want e.g. `AEST`

This in turn means:

1. when the script tests the date initially, it fails as it’s in the past
2. the script then adds +1 day to the scheduled time and checks it again
3. If you’ve set a timezone affected by Daylight Savings in `TIMEZONE` and DLS is active, the timezone offset will change. e.g. if using 'Australia/Sydney', the offset changes from `+1000` to `+1100` hours.

This means 10am is now considered to be *11* hours in the future from UTC, not 10.

This then bumps the new ‘scheduled’ UTC time from `00:00` ‘today’ back to `23:00` yesterday. The date checker then fails again as the date has already passed, and no email will be scheduled.
 
 > Note: If an email fails to schedule, it will still be saved as a Draft in Mailchimp.

There are a few ways to fix this:

1. Run your script at least 1 hour before after midnight to avoid DTS (may not be an option for your particular case)
2. Remove the TIMEZONE in .env and set the scheduled send time in UTC.

If running this script on a remote machine that automatically powers on/off e.g. AWS EC2 using AWS Systems Manager, pay close attention to ensure the machine will be powered on when you have configured the script to run! 

## Logging

Logs are always saved locally wherever the script runs. You can include AWS S3 bucket credentials in the `.env` file to save logs to an S3 bucket (strongly recommended - log it all, and log it elsewhere).

The script generates a unique log file each time it runs, as well as appending the outcome of that run in a single 'script history' log file in the root directory. This lets you quickly tell if a run has succeeded/failed, and know which log file to check for the output.

Log files from runs with DEBUG enabled are prefixed with `DEBUG-`, and the activity log will show `[DEBUG]` + `[CRON/MANUAL]` to indicate if the script was run manually or via cron. This is useful for picking which runs were the result of testing. 

### Failure notifications

Regular emails are easy to miss if one doesn't arrive on day. If you have set up an AWS SNS topic (and subscribe to it), add in the details as environment variables in the `.env` file, the script will attempt to send failure notifications to that Topic. Note the `AWS_USER` must have permissions to publish messages to the SNS topic.

### Saving logs in an AWS S3 bucket

> *Thou shalt save thy logs in a separate environment* - Gandalf

Saving your logs in S3 requires `aws-cli` to be installed on the server the script is running on. The aws credentials used need to have access to whichever S3 bucket you specify for the upload to work. 

You can optionally send your logs to S3 by providing your bucket name in the `AWS_S3_LOGS_BUCKET` variable in your `.env` file.

The script will then attempt to log into your AWS account via `aws-cli`.
If your AWS account has permissions to write to the S3 bucket, the log file will be copied there.

If `DEBUG` is set to `true`, the script will not compress and submit the log files to AWS S3. 

## Testing and debugging

To speed up testing, you can save a HTML sample in a file called `/test/test-data.html`. If `DEBUG` is set to `true` and the file exists, this data will be used instead of sending the `curl` request.

> **Note** - If you are running this tool in the wild with S3 logging, and point to the same bucket when testing locally, you'll overwrite the history log file if `DEBUG` is not set to `true`! Ye be warned!

## Environment variables

All variables are required except those marked as 'optional'.

```
AWS_S3_LOGS_BUCKET                      - string - optional
    The name of the S3 bucket to send 
    logs to. Assumes you are logged into
    aws-cli as a user with write access
    to this bucket

AWS_REGION                              - string - optional
    The AWS region to use for the 
    SNS topics e.g. ap-southeast-2

AWS_SNS_TOPIC_ARN                       - string - optional
    The ARN of the AWS SNS topic to send
    failure alert emails

AWS_USER                                - string - optional
    The AWS user with access to send 
    messages to SNS topics

DEBUG                                   - boolean - false
    Sends script output to the console 
    instead of the logs, outputs more 
    verbose info, disables submitting
    logs to AWS S3

DELETE_TEMPLATE_ON_CLEANUP              - boolean - false
    Delete the Mailchimp Template 
    when the script finishes to save
    clutter. Defaults to "false" for
    easier debugging but should be 
    "true" for production

DRUPAL_TERMINUS_SITE                    - string - optional
    Your Drupal website's Terminus
    alias, if any

EMAIL_CONTENT_URL                       - string
    URL to the webpage containing the
    data

INCLUDE_CACHEBUSTER                     - boolean - false - optional
    Whether to include a timestamp
    cachebuster in the URL to prevent
    HMTL email content caching

MAILCHIMP_API_KEY                       - string
    Your Mailchimp API key

MAILCHIMP_EMAIL_DAILY_SEND_TIME         - string - optional
    The time to send the email, in 
    15 minute intervals 
    e.g. 10:00:00, 02:45:00 etc.
    Defaults to UTC if no TIMEZONE
    is given. This time should be 
    relative to the TIMEZONE

MAILCHIMP_EMAIL_FOLDER_ID               - string - optional
    The ID of the Mailchimp Campaign 
    folder to store the email in

MAILCHIMP_EMAIL_FROM                    - string
    The name of the sender of the email

MAILCHIMP_EMAIL_REPLYTO                 - string
    The email address to reply to

MAILCHIMP_EMAIL_SHORT_NAME              - string
    Some distinctive name without 
    spaces e.g. star-wars, used in 
    file naming

MAILCHIMP_EMAIL_SUBJECT                 - string
    The email subject line

MAILCHIMP_EMAIL_SUBJECT_SUFFIX          - string - optional
    The final part of the email 
    subject line, useful for 
    appending security labels etc

MAILCHIMP_EMAIL_TITLE                   - string
    The Campaign title in Mailchimp

MAILCHIMP_SERVER_PREFIX                 - string
    Mailchimp URL prefix

MAILCHIMP_TARGET_AUDIENCE_ID            - string
    Your Mailchimp Audience ID, get
    this via running mc-get-asset-ids.sh

TIMEZONE                                - string - optional
    The TZ code to use for the 
    script times e.g. Australia/Sydney.
    Defaults to UTC if no code is
    provided

```
