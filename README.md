# rrweb to S3 storage

I wanted to have a play with Kinesis and Firehose to see what it can do, and see
if there's a light touch way of storing rrweb sessions in S3 at low maintenance
costs.

We define an API via AWS API Gateway which looks roughly like the 
[OpenAPI spec](openapi.yaml) which includes endpoints for:

 1. Creating a recording, stored in DynamoDB. This includes a screenshot which
    at the moment we use html2canvas to generate.
 2. Listing the recordings stored in DynamoDB.
 3. Adding rrweb events to a recording. These are then placed in a Kinesis Data
    Stream and delivered to S3 via Firehose, with keys of the form
    `rrweb/recordings/sessionId=<recordingId>`.
 4. Retrieving the rrweb events from S3 for a specific recording, retrieved via
    a Lambda function that concatenates the contents of the S3 blobs together as
    json-lines.

## Things left to do

 1. Authentication via Cognito. We should be able to authenticate using API
    Gateway allowing us to partition recordings by userId thereby allowing users
    to securely store recordings.
 2. Storing of screenshot data in S3. At the moment they are stored in DynamoDB
    which isn't ideal. Rather it would be better to push the contents to S3 and
    reference this instead. Options include creating another endpoint for
    pushing/retrieving the screenshot to/from S3, replacing the existing PUT
    /recordings/ integration with a Lambda function that would push to S3, or
    allowing pushing to S3 directly using a Cognito identity pool.
 3. The storage of large website assets to S3 directly. Kinesis has a max
    message size of 1MB which, for sites with large assets will result in large
    snapshot rrweb events. We could instead handling persistence of these assets
    to S3 directly and referencing these from the rrweb events. Something to
    consider here is that there will be a lot of duplication between recordings
    in terms of assets. An optimization here could be to reduce the number of
    API calls that would be necessary (and thereby optimizing costs) by only
    pushing assets that have not already been stored. What the implementation of
    that would look like is still to be hashed out.
 4. At the moment we are only using one release stage, which makes deployment a
    dangerous process. Rather, we should provide either per PR deployments
    and/or some method of promotion of known working configurations to
    production.
 5. Proper testing. There is a script at ./infra/test.sh that I've been using to
    play with, but it's not ideal.

A live example of the site can be found at
https://hazzadous.github.io/rrweb-s3-storage/ and may or may not be working.