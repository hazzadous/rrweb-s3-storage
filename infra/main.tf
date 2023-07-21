// Use terraform to provision the browser rrweb recording events -> AWS API
// Gateway -> AWS Kinesis -> AWS Kinesis Firehose -> S3.

// The terraform script will create the following resources:
// 1. AWS API Gateway
// 2. AWS Kinesis Stream
// 3. AWS Kinesis Firehose
// 4. AWS S3 Bucket
// 5. AWS IAM Role
// 6. AWS IAM Policy
// 7. AWS IAM Policy Attachment

// No lambda function is needed for this setup. The AWS Kinesis Firehose will
// automatically save the data to S3.

// The API Gateway will be created with a single endpoint: /record/<session-id>.
// The endpoint will be configured to accept POST requests. The request body
// will be JSONL formatted. The API Gateway will be configured to send the
// request body to the AWS Kinesis Stream.

// The AWS Kinesis Stream will be configured with a single shard. The AWS
// Kinesis Stream will be configured to send the data to the AWS Kinesis
// Firehose.

// The AWS Kinesis Firehose will be configured to send the data to the AWS S3
// Bucket partitioned by <session-id>, with a maximum file size of 1MB, and a
// maximum file age of 60 seconds.

// The AWS S3 Bucket will be configured to save the data in the
// <bucket-name>/<session-id>/<timestamp>.jsonl format.

// The AWS IAM Role will be configured with the following permissions:
// 1. AWS Kinesis Stream: PutRecord
// 2. AWS Kinesis Firehose: PutRecord
// 3. AWS S3 Bucket: PutObject

// The AWS IAM Policy will be configured with the following permissions:
// 1. AWS Kinesis Stream: PutRecord
// 2. AWS Kinesis Firehose: PutRecord
// 3. AWS S3 Bucket: PutObject

// The AWS IAM Policy Attachment will be configured to attach the AWS IAM
// Policy to the AWS IAM Role.


// Create the API Gateway with a single endpoint: /record/ that
// accepts POST requests and pushes the request body to the AWS Kinesis Stream.

locals {
  region = "us-east-1"
}

resource "aws_api_gateway_rest_api" "rrweb" {
  name = "rrweb"
}

resource "aws_api_gateway_resource" "record" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  parent_id   = aws_api_gateway_rest_api.rrweb.root_resource_id
  path_part   = "record"
}

// Create the aws_api_gateway_method that accepts POST requests. We do not
// include any authentication for this API Gateway.
resource "aws_api_gateway_method" "events" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  resource_id = aws_api_gateway_resource.record.id
  http_method = "POST"

  authorization = "NONE"
}

// Create the aws_api_gateway_method_response that returns a 200 status code.
resource "aws_api_gateway_method_response" "events" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  resource_id = aws_api_gateway_resource.record.id
  http_method = aws_api_gateway_method.events.http_method
  status_code = "200"
}

// Create the API Gateway deployment.
resource "aws_api_gateway_deployment" "rrweb" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  stage_name  = "prod"

  depends_on = [
    aws_api_gateway_method_response.events,
  ]
}

// Create the API Gateway Integration that sends the request body to the AWS
// Kinesis Stream.
resource "aws_api_gateway_integration" "rrweb" {
  rest_api_id             = aws_api_gateway_rest_api.rrweb.id
  resource_id             = aws_api_gateway_resource.record.id
  http_method             = "POST"
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${local.region}:kinesis:action/PutRecord"
  passthrough_behavior    = "WHEN_NO_MATCH"

  // Put the request body into the Data field, using the session id from the
  // body as the PartitionKey.
  request_templates = {
    "application/json" = <<EOF
{
  "StreamName": "rrweb",
  "Data": "$util.base64Encode($input.body)",
  "PartitionKey": "$input.path('$.sessionId')"
  }
EOF
  }

  depends_on = [
    aws_api_gateway_method_response.events,
  ]
}

// Create the S3 bucket to which the data will be saved.
resource "aws_s3_bucket" "rrweb" {
  bucket = "rrweb"
}

// Create the S3 bucket policy that allows the AWS Kinesis Firehose to save data
// to the S3 bucket.
resource "aws_s3_bucket_acl" "rrweb" {
  bucket = aws_s3_bucket.rrweb.id

  acl = "private"
}

// Create a Kinisis Stream with a single shard.
resource "aws_kinesis_stream" "rrweb" {
  name             = "rrweb"
  shard_count      = 1
  retention_period = 24
}

// Create a Kinesis Firehose send data from the Kinesis Stream to the S3 bucket.
// We use the sessionId key from the record JSON body as the partition key.
resource "aws_kinesis_firehose_delivery_stream" "rrweb" {
  name        = "rrweb"
  destination = "extended_s3"

  extended_s3_configuration {
    bucket_arn = aws_s3_bucket.rrweb.arn
    role_arn   = aws_iam_role.rrweb.arn

    buffering_size     = 1
    buffering_interval = 60
    compression_format = "GZIP"

    # https://docs.aws.amazon.com/firehose/latest/dev/dynamic-partitioning.html
    dynamic_partitioning_configuration {
      enabled = "true"
    }

    prefix              = "rrweb/sessions/!{partitionKeyFromQuery:sessionId}/"
    error_output_prefix = "rrweb/errors/"
  }

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.rrweb.arn
    role_arn           = aws_iam_role.rrweb.arn
  }

  depends_on = [
    aws_kinesis_stream.rrweb,
  ]
}

// Create an IAM role with the following permissions:
// 1. AWS Kinesis Stream: PutRecord
// 2. AWS Kinesis Firehose: PutRecord
// 3. AWS S3 Bucket: PutObject
resource "aws_iam_role" "rrweb" {
  name = "rrweb"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "firehose.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

// Create an IAM policy with the following permissions:
// 1. AWS Kinesis Stream: PutRecord
// 2. AWS Kinesis Firehose: PutRecord
// 3. AWS S3 Bucket: PutObject
resource "aws_iam_policy" "rrweb" {
  name = "rrweb"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "kinesis:PutRecord"
      ],
      "Effect": "Allow",
      "Resource": [
        "${aws_kinesis_stream.rrweb.arn}"
      ]
    },
    {
      "Action": [
        "firehose:PutRecord"
      ],
      "Effect": "Allow",
      "Resource": [
        "${aws_kinesis_firehose_delivery_stream.rrweb.arn}"
      ]
    },
    {
      "Action": [
        "s3:PutObject"
      ],
      "Effect": "Allow",
      "Resource": [
        "${aws_s3_bucket.rrweb.arn}/*"
      ]
    }
  ]
}
EOF
}

// Attach the IAM policy to the IAM role.
resource "aws_iam_role_policy_attachment" "rrweb" {
  role       = aws_iam_role.rrweb.name
  policy_arn = aws_iam_policy.rrweb.arn
}



// Output the API Gateway endpoint.
output "endpoint" {
  value = aws_api_gateway_deployment.rrweb.invoke_url
}
