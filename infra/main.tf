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

// To provide some partitioning of data permissions, we use AWS Cognito to authenticate 
// both the API Gateway and the S3 bucket. We create a Cognito Identity Pool that allows
// unauthenticated users to access the API Gateway, as well as the S3 bucket. We then
// create an IAM role that can be assumed by the Cognito Identity Pool. We can then use 
// the sub of the generated Web Identity Token to:
//
//  1. prefix the recordings for that user with rrweb/recordings/userId=<userId>
//  2. restrict the IAM policy to only allow access to the S3 bucket with prefix
//     rrweb/recordings/userId=<userId>/

locals {
  region = "us-east-1"
}

// Provider for AWS.
provider "aws" {
  region = local.region
}

// Create a CloudWatch log group for the API Gateway.
resource "aws_cloudwatch_log_group" "rrweb" {
  name = "/aws/api-gateway/rrweb"
}

// For API Gateway execution logs, AWS requires the log group name to 
// match the following pattern.
resource "aws_cloudwatch_log_group" "example" {
  name              = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.rrweb.id}/${aws_api_gateway_stage.rrweb.stage_name}"
  retention_in_days = 1
}

// Create a log group for Kinesis Firehose.
resource "aws_cloudwatch_log_group" "rrweb_firehose" {
  name = "/aws/kinesisfirehose/rrweb"
}

resource "aws_api_gateway_rest_api" "rrweb" {
  name = "rrweb"
}

resource "aws_api_gateway_authorizer" "rrweb" {
  name                   = "rrweb"
  rest_api_id            = aws_api_gateway_rest_api.rrweb.id
  type                   = "COGNITO_USER_POOLS"
  provider_arns          = [aws_cognito_user_pool.rrweb.arn]
}

resource "aws_api_gateway_resource" "events" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  parent_id   = aws_api_gateway_resource.recording.id
  path_part   = "events"
}

// Create the aws_api_gateway_method that accepts POST requests. We do not
// include any authentication for this API Gateway.
resource "aws_api_gateway_method" "events_post" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  resource_id = aws_api_gateway_resource.events.id
  http_method = "POST"

  authorization = "NONE"

  // Make sure CORS is enabled.
  request_parameters = {
    "method.request.header.Access-Control-Allow-Origin" = true
  }
}

// Create the aws_api_gateway_method_response that returns a 200 status code.
resource "aws_api_gateway_method_response" "events_post" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  resource_id = aws_api_gateway_resource.events.id
  http_method = aws_api_gateway_method.events_post.http_method
  status_code = "200"

  // Make sure CORS is enabled.
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

// As this is going to be accessed across origin, we need to include an OPTIONS 
// method that ensures CORS is enabled. We iterate over all the resources to ensure that 
// all are covered.
resource "aws_api_gateway_method" "events_options" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  resource_id = aws_api_gateway_resource.events.id
  http_method = "OPTIONS"

  authorization = "NONE"

  // Make sure CORS is enabled.
  request_parameters = {
    "method.request.header.Access-Control-Allow-Headers" = true,
    "method.request.header.Access-Control-Allow-Methods" = true,
    "method.request.header.Access-Control-Allow-Origin" = true
  }
}

// Define the OPTIONS method response
resource "aws_api_gateway_method_response" "events_options" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  resource_id = aws_api_gateway_resource.events.id
  http_method = aws_api_gateway_method.events_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

// Define an integration for OPTIONS that just returns status code 200.
resource "aws_api_gateway_integration" "events_options" {
  rest_api_id             = aws_api_gateway_rest_api.rrweb.id
  resource_id             = aws_api_gateway_resource.events.id
  http_method             = aws_api_gateway_method.events_options.http_method
  type                    = "MOCK"

  request_templates = {
    "application/json" = <<EOF
{
  "statusCode" : 200
}
EOF
  }
}

// Define the integration response for OPTIONS.
resource "aws_api_gateway_integration_response" "events_options" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  resource_id = aws_api_gateway_resource.events.id
  http_method = aws_api_gateway_method.events_options.http_method
  status_code = aws_api_gateway_method_response.events_options.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS,PUT,GET'",
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
}


resource "aws_api_gateway_method" "recording_options" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  resource_id = aws_api_gateway_resource.recording.id
  http_method = "OPTIONS"

  authorization = "NONE"

  // Make sure CORS is enabled.
  request_parameters = {
    "method.request.header.Access-Control-Allow-Headers" = true,
    "method.request.header.Access-Control-Allow-Methods" = true,
    "method.request.header.Access-Control-Allow-Origin" = true
  }
}

// Define the OPTIONS method response
resource "aws_api_gateway_method_response" "recording_options" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  resource_id = aws_api_gateway_resource.recording.id
  http_method = aws_api_gateway_method.recording_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

// Define an integration for OPTIONS that just returns status code 200.
resource "aws_api_gateway_integration" "recording_options" {
  rest_api_id             = aws_api_gateway_rest_api.rrweb.id
  resource_id             = aws_api_gateway_resource.recording.id
  http_method             = aws_api_gateway_method.recording_options.http_method
  type                    = "MOCK"

  request_templates = {
    "application/json" = <<EOF
{
  "statusCode" : 200
}
EOF
  }
}

// Define the integration response for OPTIONS.
resource "aws_api_gateway_integration_response" "recording_options" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  resource_id = aws_api_gateway_resource.recording.id
  http_method = aws_api_gateway_method.recording_options.http_method
  status_code = aws_api_gateway_method_response.recording_options.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS,PUT,GET'",
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
}


resource "aws_api_gateway_method" "recordings_options" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  resource_id = aws_api_gateway_resource.recordings.id
  http_method = "OPTIONS"

  authorization = "NONE"

  // Make sure CORS is enabled.
  request_parameters = {
    "method.request.header.Access-Control-Allow-Headers" = true,
    "method.request.header.Access-Control-Allow-Methods" = true,
    "method.request.header.Access-Control-Allow-Origin" = true
  }
}

// Define the OPTIONS method response
resource "aws_api_gateway_method_response" "recordings_options" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  resource_id = aws_api_gateway_resource.recordings.id
  http_method = aws_api_gateway_method.recordings_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

// Define an integration for OPTIONS that just returns status code 200.
resource "aws_api_gateway_integration" "recordings_options" {
  rest_api_id             = aws_api_gateway_rest_api.rrweb.id
  resource_id             = aws_api_gateway_resource.recordings.id
  http_method             = aws_api_gateway_method.recordings_options.http_method
  type                    = "MOCK"

  request_templates = {
    "application/json" = <<EOF
{
  "statusCode" : 200
}
EOF
  }
}

// Define the integration response for OPTIONS.
resource "aws_api_gateway_integration_response" "recordings_options" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  resource_id = aws_api_gateway_resource.recordings.id
  http_method = aws_api_gateway_method.recordings_options.http_method
  status_code = aws_api_gateway_method_response.recordings_options.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS,PUT,GET'",
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
}

// Create the API Gateway deployment.
resource "aws_api_gateway_deployment" "rrweb" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id

  triggers = {
    // To ensure that the API Gateway is redeployed when any methods, resources, 
    // or integrations change we use a hash of the JSON representation of the
    // resources that we want to trigger a redeployment.
    redeployment = sha1(jsonencode([
      aws_api_gateway_method.events_post,
      aws_api_gateway_method_response.events_post,
      aws_api_gateway_method.events_options,
      aws_api_gateway_method_response.events_options,
      aws_api_gateway_integration.events,
      aws_api_gateway_integration_response.events,
      aws_api_gateway_integration.events_options,
      aws_api_gateway_integration_response.events_options,
      aws_api_gateway_resource.events,
      aws_api_gateway_method.recording_put,
      aws_api_gateway_method_response.recording_put,
      aws_api_gateway_integration.recording_put,
      aws_api_gateway_integration_response.recording_put,
      aws_api_gateway_resource.recording,
      aws_api_gateway_method.recording_get,
      aws_api_gateway_method_response.recording_get,
      aws_api_gateway_integration.recording_get,
      aws_api_gateway_integration_response.recording_get,
      aws_api_gateway_resource.recordings,
      aws_api_gateway_method.recordings_get,
      aws_api_gateway_method_response.recordings_get,
      aws_api_gateway_integration.recordings_get,
      aws_api_gateway_integration_response.recordings_get,
      aws_api_gateway_method.events_get,
      aws_api_gateway_integration.events_get,
      aws_api_gateway_integration_response.events_get,
      aws_api_gateway_method_response.events_get,
    ]))
  }

  // Make sure we create a new deployment when the API Gateway is created.
  lifecycle {
    create_before_destroy = true
  }
}

// Create the API Gateway Integration that sends the request body to the AWS
// Kinesis Stream.
resource "aws_api_gateway_integration" "events" {
  rest_api_id             = aws_api_gateway_rest_api.rrweb.id
  resource_id             = aws_api_gateway_resource.events.id
  http_method             = "POST"
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${local.region}:kinesis:action/PutRecord"
  passthrough_behavior    = "NEVER"
  credentials                = aws_iam_role.rrweb.arn

  // Put the request body into the Data field, using the session id from the
  // body as the PartitionKey. We also add in the userId from the `sub` value 
  // of the Cognito ID Token into the Data JSON. This ID is available in the 
  // $context.identity.cognitoIdentityId variable. We use Velocity Template 
  // Language (VTL) to do this, such that the old JSON body before base64 
  // encoding is:
  //
  // {
  //   "sessionId": "123",
  //   "userId": "$context.identity.cognitoIdentityId",
  //   ...
  // }
  //
  request_templates = {
    "application/json" = <<EOF
## Parse the input JSON string into a map
#set($inputRoot = $util.parseJson($input.body))

## Add the new key into the resulting record
#set($result = $inputRoot.put("sessionId", "$context.params('sessionId')"))

{
  "StreamName": "rrweb",
  "Data": "$util.base64Encode($input.body)",
  "PartitionKey": "$input.path('$.sessionId')"
}
EOF
  }
}

// Create an API Gateway Integration Response that returns a 200 status code.
resource "aws_api_gateway_integration_response" "events" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  resource_id = aws_api_gateway_resource.events.id
  http_method = aws_api_gateway_method.events_post.http_method
  status_code = aws_api_gateway_method_response.events_post.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }

  depends_on = [
    aws_api_gateway_integration.events
  ]
}

resource "aws_api_gateway_account" "rrweb" {
  cloudwatch_role_arn = aws_iam_role.rrweb.arn

  depends_on = [
    aws_iam_role_policy_attachment.rrweb_cloudwatch
  ]
}

resource "aws_api_gateway_stage" "rrweb" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  stage_name  = "prod"

  deployment_id = aws_api_gateway_deployment.rrweb.id

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.rrweb.arn
    format          = "{\"requestId\":\"$context.requestId\",\"ip\":\"$context.identity.sourceIp\",\"requestTime\":\"$context.requestTime\",\"httpMethod\":\"$context.httpMethod\",\"routeKey\":\"$context.routeKey\",\"status\":\"$context.status\",\"protocol\":\"$context.protocol\",\"responseLength\":\"$context.responseLength\"}"
  }

  xray_tracing_enabled = true

  depends_on = [
    aws_api_gateway_account.rrweb,
    aws_cloudwatch_log_group.rrweb,
  ]
}

resource "aws_api_gateway_method_settings" "rrweb" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  stage_name  = aws_api_gateway_stage.rrweb.stage_name
  method_path = "*/*"

  settings {
    logging_level = "INFO"
    data_trace_enabled = true
    metrics_enabled = true
  }
}

// Compile the go lambda function.
resource "null_resource" "file_hash" {
  triggers = {
    always_run = "${timestamp()}"
  }

  provisioner "local-exec" {
    command = "shasum ${path.module}/main.go | awk '{print $1}' > ${path.module}/hash"
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/get_s3_objects/main"
  output_path = "${path.module}/get_s3_objects/function.zip"
}

resource "aws_lambda_function" "get_s3_objects" {
  // A go lambda function that returns the contents of objects given a 
  // bucket name and sessionId, concatenated together.
  function_name = "get_s3_objects"
  handler = "main"
  runtime = "go1.x"

  role          = aws_iam_role.rrweb.arn

  filename      = data.archive_file.lambda_zip.output_path
  source_code_hash = filebase64sha256(data.archive_file.lambda_zip.output_path)

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.rrweb.id
    }
  }
}

resource "aws_api_gateway_method" "events_get" {
  rest_api_id   = aws_api_gateway_rest_api.rrweb.id
  resource_id   = aws_api_gateway_resource.events.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "events_get" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  resource_id = aws_api_gateway_resource.events.id
  http_method = aws_api_gateway_method.events_get.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_s3_objects.invoke_arn
}

resource "aws_api_gateway_integration_response" "events_get" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  resource_id = aws_api_gateway_resource.events.id
  http_method = aws_api_gateway_method.events_get.http_method
  status_code = "200"

  response_templates = {
    "application/json" = "$input.body"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }

  depends_on = [
    aws_api_gateway_integration.events_get
  ]
}

resource "aws_api_gateway_method_response" "events_get" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  resource_id = aws_api_gateway_resource.events.id
  http_method = aws_api_gateway_method.events_get.http_method
  status_code = aws_api_gateway_integration_response.events_get.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }

  depends_on = [
    aws_api_gateway_integration_response.events_get
  ]
}

// Create a DynamoDB table to store the rrweb recordings metadata.
resource "aws_dynamodb_table" "rrweb" {
  name = "rrweb"

  attribute {
    name = "sessionId"
    type = "S"
  }

  billing_mode = "PAY_PER_REQUEST"

  hash_key = "sessionId"
}

// Create an API Gateway Resource, Method, and Integration that creates a new DynamoDB item with the
// sessionId, and createdAt.

// Create an API Gateway Method that accepts PUT requests.
resource "aws_api_gateway_method" "recording_put" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  resource_id = aws_api_gateway_resource.recording.id
  http_method = "PUT"

  authorization = "NONE"

  // Make sure CORS is enabled.
  request_parameters = {
    "method.request.header.Access-Control-Allow-Origin" = true
  }
}

// Create an API Gateway Method Response that returns a 200 status code.
resource "aws_api_gateway_method_response" "recording_put" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  resource_id = aws_api_gateway_resource.recording.id
  http_method = aws_api_gateway_method.recording_put.http_method
  status_code = "200"

  // Make sure CORS is enabled.
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

// Create an API Gateway Integration that creates a new DynamoDB item with the
// sessionId, and createdAt, as well as a screenshot of the page.
resource "aws_api_gateway_integration" "recording_put" {
  rest_api_id             = aws_api_gateway_rest_api.rrweb.id
  resource_id             = aws_api_gateway_resource.recording.id
  http_method             = "PUT"
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${local.region}:dynamodb:action/PutItem"
  passthrough_behavior    = "NEVER"
  credentials             = aws_iam_role.rrweb.arn

  // Put the request body into the Item field.
  request_templates = {
    "application/json" = <<EOF
  {
    "TableName": "rrweb",
    "Item": {
      "sessionId": {
        "S": "$input.params('sessionId')"
      },
      "createdAt": {
        "N": "$context.requestTimeEpoch"
      },
      "screenshot": {
        "S": "$input.path('$.screenshot')"
      }
    }
  }
EOF
  }
}

// Create an API Gateway Integration Response that returns a 200 status code.
resource "aws_api_gateway_integration_response" "recording_put" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  resource_id = aws_api_gateway_resource.recording.id
  http_method = aws_api_gateway_method.recording_put.http_method
  status_code = aws_api_gateway_method_response.recording_put.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }

  depends_on = [
    aws_api_gateway_integration.recording_put
  ]
}

resource "aws_api_gateway_resource" "recordings" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  parent_id   = aws_api_gateway_rest_api.rrweb.root_resource_id
  path_part   = "recordings"
}

// Create an endpoint for retrieving a recording metadata object.
resource "aws_api_gateway_resource" "recording" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  parent_id   = aws_api_gateway_resource.recordings.id
  path_part   = "{sessionId}"
}

// Create an API Gateway Method that accepts GET requests for retrieving a list of 
// all recordings metadata objects in DynamoDB.
resource "aws_api_gateway_method" "recordings_get" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  resource_id = aws_api_gateway_resource.recordings.id
  http_method = "GET"

  authorization = "NONE"

  // Make sure CORS is enabled.
  request_parameters = {
    "method.request.header.Access-Control-Allow-Origin" = true
  }
}

// Create an API Gateway Method Response that returns a 200 status code.
resource "aws_api_gateway_method_response" "recordings_get" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  resource_id = aws_api_gateway_resource.recordings.id
  http_method = aws_api_gateway_method.recordings_get.http_method
  status_code = "200"

  // Make sure CORS is enabled.
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

// Create an API Gateway Integration that retrieves the latest 10 recordings metadata objects from DynamoDB.
resource "aws_api_gateway_integration" "recordings_get" {
  rest_api_id             = aws_api_gateway_rest_api.rrweb.id
  resource_id             = aws_api_gateway_resource.recordings.id
  http_method             = "GET"
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${local.region}:dynamodb:action/Scan"
  passthrough_behavior    = "NEVER"
  credentials             = aws_iam_role.rrweb.arn

  // Query the table for the latest 10 items, ordered by createdAt descending.
  request_templates = {
    "application/json" = <<EOF
  {
    "TableName": "rrweb"
  }
EOF
  }
}

// Create an API Gateway Integration Response that returns a 200 status code and the
// recording metadata objects from dynamodb.
resource "aws_api_gateway_integration_response" "recordings_get" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  resource_id = aws_api_gateway_resource.recordings.id
  http_method = aws_api_gateway_method.recordings_get.http_method
  status_code = aws_api_gateway_method_response.recordings_get.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }

  // Transform the DynamoDB response to a list of sessionId, createdAt, and screenshot objects
  // that can be returned to the client.
#   response_templates = {
#     "application/json" = <<EOF
# #set($inputRoot = $input.path('$'))
# {
#   "recordings" : [
#     #foreach($elem in $inputRoot.Items)
#     {
#       "sessionId" : "$elem.sessionId.S",
#       "createdAt" : "$elem.createdAt.N",
#       "screenshot" : "$elem.screenshot.S"
#     }#if($foreach.hasNext),#end
#     #end
#   ]
# }
# EOF
#   }

  depends_on = [
    aws_api_gateway_integration.recordings_get
  ]
}

// Create an API Gateway Method that accepts GET requests for the recording resource.
resource "aws_api_gateway_method" "recording_get" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  resource_id = aws_api_gateway_resource.recording.id
  http_method = "GET"

  authorization = "NONE"

  // Make sure CORS is enabled.
  request_parameters = {
    "method.request.header.Access-Control-Allow-Origin" = true
  }
}

// Create an API Gateway Method Response that returns a 200 status code.
resource "aws_api_gateway_method_response" "recording_get" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  resource_id = aws_api_gateway_resource.recording.id
  http_method = aws_api_gateway_method.recording_get.http_method
  status_code = "200"

  // Make sure CORS is enabled.
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

// Create an API Gateway Integration that retrieves the recording metadata object from DynamoDB.
resource "aws_api_gateway_integration" "recording_get" {
  rest_api_id             = aws_api_gateway_rest_api.rrweb.id
  resource_id             = aws_api_gateway_resource.recording.id
  http_method             = "GET"
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${local.region}:dynamodb:action/GetItem"
  passthrough_behavior    = "NEVER"
  credentials             = aws_iam_role.rrweb.arn

  // Put the request body into the Item field.
  request_templates = {
    "application/json" = <<EOF
  {
    "TableName": "rrweb",
    "Key": {
      "sessionId": {
        "S": "$input.params('sessionId')"
      }
    }
  }
EOF
  }
}

// Create an API Gateway Integration Response that returns a 200 status code and the
// recording metadata object from dynamodb.
resource "aws_api_gateway_integration_response" "recording_get" {
  rest_api_id = aws_api_gateway_rest_api.rrweb.id
  resource_id = aws_api_gateway_resource.recording.id
  http_method = aws_api_gateway_method.recording_get.http_method
  status_code = aws_api_gateway_method_response.recording_get.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }

  // Transform the DynamoDB response to a list of sessionId, createdAt, and screenshot objects
  // that can be returned to the client.
#   response_templates = {
#     "application/json" = <<EOF
# #set($inputRoot = $input.path('$'))
# {
#   "recordings" : [
#     #foreach($elem in $inputRoot.Items)
#     {
#       "sessionId" : "$elem.sessionId.S",
#       "createdAt" : "$elem.createdAt.N",
#       "screenshot" : "$elem.screenshot.S"
#     }#if($foreach.hasNext),#end
#     #end
#   ]
# }
# EOF
#   }

  depends_on = [
    aws_api_gateway_integration.recording_get
  ]
}

// Create the S3 bucket to which the data will be saved.
resource "aws_s3_bucket" "rrweb" {
  bucket = "hazzadous-rrweb"
}

resource "aws_s3_bucket_ownership_controls" "rrweb" {
  bucket = aws_s3_bucket.rrweb.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

// Create the S3 bucket policy that allows the AWS Kinesis Firehose to save data
// to the S3 bucket via the rrweb role.
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
// Original thinking: We use the sessionId key from the record JSON body as the partition key.
//
// Revised after realising LocalStack doesn't support dynamic partition key, we'll use S3 
// Select instead for now, although this will have implications for costs and performance. It
// should however make it possible to move forward with other parts of the project.
//
// Revised after deciding to ditch LocalStack to avoid wrestling differences between it and AWS:
// Use AWS directly. Testing won't be as easy, but should be less confusing.
resource "aws_kinesis_firehose_delivery_stream" "rrweb" {
  name        = "rrweb"
  destination = "extended_s3"

  extended_s3_configuration {
    bucket_arn = aws_s3_bucket.rrweb.arn
    role_arn   = aws_iam_role.rrweb.arn

    buffering_size     = 64
    buffering_interval = 60

    compression_format = "UNCOMPRESSED"

    dynamic_partitioning_configuration {
      enabled = true
    }

    processing_configuration {
      enabled = true

      # Multi-record deaggregation processor example
      processors {
        type = "RecordDeAggregation"

        parameters {
          parameter_name  = "SubRecordType"
          parameter_value = "JSON"
        }
      }

      // Extract the sessionId from the JSON using JQ as metadata
      processors {
        type = "MetadataExtraction"

        parameters {
          parameter_name  = "MetadataExtractionQuery"
          parameter_value = "{sessionId: .sessionId}"
        }

        // Specify that we should use the jQ engine to extract the metadata
        // from the record.
        parameters {
          parameter_name  = "JsonParsingEngine"
          parameter_value = "JQ-1.6"
        }
      }

      processors {
        // Add new line delimiter to the end of each record, otherwise the
        // records will be concatenated together.
        type = "AppendDelimiterToRecord"
      }
    }

    // Configure CloudWatch logging for the Kinesis Firehose.
    cloudwatch_logging_options {
      enabled = true
      log_group_name = aws_cloudwatch_log_group.rrweb_firehose.name
      log_stream_name = "rrweb"
    }

    prefix              = "rrweb/recordings/sessionId=!{partitionKeyFromQuery:sessionId}/"
    error_output_prefix = "rrweb/errors/"
  }

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.rrweb.arn
    role_arn           = aws_iam_role.rrweb.arn
  }
}

// Create a role that can be assumed by the API Gateway deployment, Kinesis, and Kinesis Firehose.
resource "aws_iam_role" "rrweb" {
  name = "rrweb"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "sts:AssumeRole"
      ],
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "apigateway.amazonaws.com",
          "kinesis.amazonaws.com",
          "firehose.amazonaws.com",
          "lambda.amazonaws.com"
        ]
      }
    }
  ]
}
EOF
}

// Create an IAM policy with the following permissions:
// 1. AWS Kinesis Stream: PutRecord, DescribeStream
// 2. AWS S3 Bucket: PutObject
resource "aws_iam_policy" "rrweb" {
  name = "rrweb"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "kinesis:PutRecord",
        "kinesis:DescribeStream",
        "kinesis:GetShardIterator",
        "kinesis:GetRecords",
        "kinesis:ListShards"
      ],
      "Effect": "Allow",
      "Resource": [
        "${aws_kinesis_stream.rrweb.arn}"
      ]
    },
    {
      "Action": [
        "s3:AbortMultipartUpload",
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads",
        "s3:PutObject",
        "s3:ListObjectsV2"
      ],
      "Effect": "Allow",
      "Resource": [
        "${aws_s3_bucket.rrweb.arn}/*",
        "${aws_s3_bucket.rrweb.arn}"
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

// Separately, we creat a policy for rrweb role to be able to PutRecord to the 
// firehose delivery stream. We do this separately because otherwise we have a 
// dependency cycle; we need the rrweb role to have DescribeStream permissions
// to allow the delivery stream to be created, but we will be depending on specifying 
// the delivery stream ARN in the policy.
resource "aws_iam_policy" "rrweb_firehose" {
  name = "rrweb_firehose"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "firehose:PutRecord"
      ],
      "Effect": "Allow",
      "Resource": [
        "${aws_kinesis_firehose_delivery_stream.rrweb.arn}"
      ]
    }
  ]
}
EOF
}

// Attach the IAM policy to the IAM role.
resource "aws_iam_role_policy_attachment" "rrweb_firehose" {
  role       = aws_iam_role.rrweb.name
  policy_arn = aws_iam_policy.rrweb_firehose.arn
}

// Add permissions to write to the CloudWatch log group.
resource "aws_iam_policy" "rrweb_cloudwatch" {
  name = "rrweb_cloudwatch"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents",
          "logs:GetLogEvents",
          "logs:FilterLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

// Attach the IAM policy to the IAM role.
resource "aws_iam_role_policy_attachment" "rrweb_cloudwatch" {
  role       = aws_iam_role.rrweb.name
  policy_arn = aws_iam_policy.rrweb_cloudwatch.arn
}


// Create a Cognito Identity Pool that allows unauthenticated users to access
// the API Gateway, as well as the S3 bucket.

resource "aws_cognito_user_pool" "rrweb" {
  name = "rrweb"
}

resource "aws_cognito_user_pool_client" "rrweb" {
  name = "rrweb"
  user_pool_id = aws_cognito_user_pool.rrweb.id
  generate_secret = false
  allowed_oauth_flows = ["implicit"]
  callback_urls = ["http://localhost:3000"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["openid"]
  supported_identity_providers = ["COGNITO"]
}

// Create a Cognito Identity Pool.
resource "aws_cognito_identity_pool" "rrweb" {
  allow_unauthenticated_identities = true
  identity_pool_name               = "rrweb"
}

// Create a role that can be assumed by the Cognito Identity Pool.
resource "aws_iam_role" "rrweb_cognito" {
  name = "rrweb_cognito"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "sts:AssumeRole"
      ],
      "Effect": "Allow",
      "Principal": {
        "Federated": "cognito-identity.amazonaws.com"
      }
    }
  ]
}
EOF
}

// Create an IAM policy with the following permissions:
//
//   AWS S3 Bucket: GetObject and ListObjects, but specifically only for the rrweb bucket with objects of prefix rrweb/recordings/userId=<userId>/
//
resource "aws_iam_policy" "rrweb_cognito" {
  name = "rrweb_cognito"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:GetObject",
        "s3:ListObjects"
      ],
      "Effect": "Allow",
      "Resource": [
        "${aws_s3_bucket.rrweb.arn}/rrweb/recordings/*"
      ],
      "Condition": {
        "StringLike": {
          "s3:prefix": [
            "rrweb/recordings/userId=$${cognito-identity.amazonaws.com:sub}/*"
          ]
        }
      }
    }
  ]
}
EOF
}

// Attach the IAM policy to the IAM role.
resource "aws_iam_role_policy_attachment" "rrweb_cognito" {
  role       = aws_iam_role.rrweb_cognito.name
  policy_arn = aws_iam_policy.rrweb_cognito.arn
}

// Create a policy for rrweb to PutItem to the DynamoDB table.
resource "aws_iam_policy" "rrweb_dynamodb" {
  name = "rrweb_dynamodb"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:Scan"
      ],
      "Effect": "Allow",
      "Resource": [
        "${aws_dynamodb_table.rrweb.arn}"
      ]
    }
  ]
}
EOF
}

// Attach the IAM policy to the IAM role.
resource "aws_iam_role_policy_attachment" "rrweb_dynamodb" {
  role       = aws_iam_role.rrweb.name
  policy_arn = aws_iam_policy.rrweb_dynamodb.arn
}

// Add a policy to rrweb to allow it to execute the get_s3_objects lambda function.
resource "aws_iam_policy" "rrweb_lambda" {
  name = "rrweb_lambda"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "lambda:InvokeFunction"
      ],
      "Effect": "Allow",
      "Resource": [
        "${aws_lambda_function.get_s3_objects.arn}"
      ]
    }
  ]
}
EOF
}

// Attach the IAM policy to the IAM role.
resource "aws_iam_role_policy_attachment" "rrweb_lambda" {
  role       = aws_iam_role.rrweb.name
  policy_arn = aws_iam_policy.rrweb_lambda.arn
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_s3_objects.function_name
  principal     = "apigateway.amazonaws.com"

  # The /*/* portion grants access from any method on any resource
  # within the specified API Gateway.
  source_arn = "${aws_api_gateway_rest_api.rrweb.execution_arn}/*/*"
}

// Output the API Gateway endpoint.
output "endpoint" {
  value = aws_api_gateway_deployment.rrweb.invoke_url
}

// Output the Cognito Client Id.
output "cognito_client_id" {
  value = aws_cognito_user_pool_client.rrweb.id
}