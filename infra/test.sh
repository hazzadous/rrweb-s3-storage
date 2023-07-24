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
SESSION_ID=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
BUCKET=hazzadous-rrweb

set -e

# POST an rrweb event to the API Gateway endpoint. We push up a few events to 
# test the batching of events by firehose.
echo "Posting rrweb event to API Gateway endpoint"
for i in {1..3}; do
  curl -X POST \
    -H "Content-Type: application/json" \
    -d '{"sessionId": "'"$SESSION_ID"'", "events": [{"type": "load", "timestamp": 1620000000000, "data": {"url": "https://www.example.com"}}]}' \
    "$1"
done

# Wait for the event to be ingested into S3. It should be no more than 60
# seconds.
SECONDS=0
echo "Waiting for event to be ingested into S3"
while [ $SECONDS -lt 60 ]; do
  if aws s3api list-objects-v2 --bucket $BUCKET --prefix rrweb/recordings/sessionId=$SESSION_ID | jq -r '.Contents | length' | grep -q 3; then
    echo "Event ingested into S3"
    # Output the latest S3 object contents to help with debugging
    aws s3api list-objects-v2 --bucket $BUCKET --prefix rrweb/recordings/sessionId=$SESSION_ID | jq -r '.Contents | sort_by(.LastModified) | last | .Key' | xargs aws s3api get-object --bucket $BUCKET --key | jq
    exit 0
  fi
  echo "Waiting for event to be ingested into S3"
  sleep 1
done

echo "Event not ingested into S3"
exit 1
