# Mailchimp recurring HTML email generator

**Gathers HTML data from a URL and creates a new email campaign with it in Mailchimp, every day.**

## Requirements

- bash
- jq 1.7+ (earlier versions may work, untested)
- [Pantheon's terminus](https://docs.pantheon.io/terminus)
- curl

## Purpose

This script does several things:

1. Fetches HTML data via curl request to the your desired webpage
2. Parses the HTML response
3. Creates a Mailchimp email Template containing the KAR data via the Mailchimp API
4. Collects the ID of the new template
5. Creates a new Mailchimp Campaign using the Template and schedules it to send to your nominated Mailchimp Audience
6. Deletes the template to clean up

We do it this way for several reasons:

1. Mailchimp Campaigns don't allow sending recurring emails out of the box. The only way to do this is via RSS feeds, and while Drupal Views allows creating RSS feeds with content, the HTML data in Drupal needs to include the KAR News block as well. RSS Views doesn't render anything other than the nodes.
2. We can trigger recurring emails in Mailchimp using their Journey/Automation feature. It allows periodically sending recurring emails with content sourced from a URL, however it caches the data after the first run so it may be stale when next sent. This is because a Journey is processed per-subscriber, and may therefore require Mailchimp to retrieve the same data thousands of times.
3. Generating a new Template via flushing Drupal's cache and retrieving the KAR data via curl guarantees the data is fresh every time, while not overloading Mailchimp.

This script uses v3.0 of the Mailchimp API as of 9 August 2024.

Mailchimp API documentation: https://mailchimp.com/developer/marketing/api/

## Environment variables

All variables except `DRUPAL_TERMINUS_SITE` are required.

```
DEBUG                        - boolean - defaults to false
EMAIL_CONTENT_URL            - string - URL to the webpage containing the data
MAILCHIMP_EMAIL_SHORT_NAME   - string - Some distinctive name without spaces e.g. star-wars
MAILCHIMP_SERVER_PREFIX      - string - Mailchimp URL prefix
MAILCHIMP_API_KEY            - string - Your Mailchimp API key
MAILCHIMP_TARGET_AUDIENCE_ID - string - Your Mailchimp Audience ID, get this via the API
DRUPAL_TERMINUS_SITE         - string - Your Drupal website's Terminus alias, if any
```

Read more about where these can be found:

 - [Mailchimp server prefix](https://mailchimp.com/developer/marketing/guides/quick-start/#make-your-first-api-call)
 - [Mailchimp API key](https://mailchimp.com/developer/marketing/guides/quick-start/#generate-your-api-key)


## Testing and debugging

To speed up testing, you can save a HTML sample in a file called `/test/test-data.html`. If `DEBUG` is enabled, this data will be used instead of sending the `curl` request.
