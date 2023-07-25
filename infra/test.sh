#!/usr/bin/env bash

# This script tests the terraformed AWS infrastructure for ingesting data rrweb
# sessions data into S3 by running a simple test script to:
# 1. POST an rrweb event to the API Gateway endpoint
# 2. Wait for the event to be ingested into S3

# The script takes the following arguments:
# 1. The API Gateway endpoint URL

# The script returns 0 if the test passes, 1 if it fails

# For checking S3 we use the awslocal CLI, which is a local version of the AWS
# CLI that can be used to interact with localstack services. This way we don't
# need to set e.g. AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment
# variables to access the localstack S3 service. We assume awslocal is
# installed and don't check this.

# The script assumes that the localstack S3 and API Gateway service is running
# on port 4566 and we don't do any checks to verify that this is the case, to
# keep this script simple.

set -o pipefail -x

# Check that the API Gateway endpoint URL has been provided
if [ -z "$1" ]
then
  echo "Please provide the API Gateway endpoint URL as the first argument"
  exit 1
fi

# Randomly generate a session ID.
USER_ID=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
SESSION_ID=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
BUCKET=hazzadous-rrweb

set -e


# POST a new rrweb recording to /recordings, including SESSION_ID, USER_ID, and
# a snapshot, base64 encoded.
echo "Posting rrweb recording to API Gateway endpoint"
curl -X OPTIONS \
  -H "Content-Type: application/json" \
  -d '{"screenshot": "asdf"}' \
  "$1/recordings/$SESSION_ID"
curl -X PUT \
  -H "Content-Type: application/json" \
  -d '{"screenshot": "asdf"}' \
  "$1/recordings/$SESSION_ID"

# Get the recording from the /recordings/{sessionId} endpoint
echo "Getting rrweb recording from API Gateway endpoint"
curl -X OPTIONS \
  -H "Content-Type: application/json" \
  "$1/recordings/$SESSION_ID"

curl -X GET \
  -H "Content-Type: application/json" \
  "$1/recordings/$SESSION_ID"

# Get all recordings from the /recordings endpoint
echo "Getting all rrweb recordings from API Gateway endpoint"
curl -X OPTIONS \
  -H "Content-Type: application/json" \
  "$1/recordings"
curl -X GET \
  -H "Content-Type: application/json" \
  "$1/recordings"

# POST an rrweb event to the API Gateway endpoint. We push up a few events to 
# test the batching of events by firehose.
echo "Posting rrweb event to API Gateway endpoint"
for i in {1..3}; do
  curl -X OPTIONS \
    -H "Content-Type: application/json" \
    -d '{"sessionId": "'"$SESSION_ID"'", "events": [{"type": "load", "timestamp": 1620000000000, "data": {"url": "https://www.example.com"}}]}' \
    "$1/recordings/$SESSION_ID/events"
  curl -X POST \
    -H "Content-Type: application/json" \
    -d '{"sessionId": "'"$SESSION_ID"'", "events": [{"type": "load", "timestamp": 1620000000000, "data": {"url": "https://www.example.com"}}]}' \
    "$1/recordings/$SESSION_ID/events"
done

# Wait for the event to be ingested into S3. It should be no more than 60
# seconds. We fetch these events from /recordings/{sessionId}/events
SECONDS=0
echo "Waiting for rrweb event to be ingested into S3"
while true; do
  # Get the events from the /recordings/{sessionId}/events endpoint
  curl -X OPTIONS \
    -H "Content-Type: application/json" \
    "$1/recordings/$SESSION_ID/events"
  EVENTS=$(curl -X GET \
    -H "Content-Type: application/json" \
    "$1/recordings/$SESSION_ID/events")

  # Check if the event has been ingested into S3
  if [[ $EVENTS == *"https://www.example.com"* ]]; then
    echo "Event ingested into S3"
    break
  fi

  # Check if we've waited more than 60 seconds
  if [ $SECONDS -gt 120 ]; then
    echo "Event not ingested into S3 after 60 seconds"
    exit 1
  fi

  # Wait 1 second before checking again
  sleep 1
done