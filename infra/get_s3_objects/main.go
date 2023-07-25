package main

import (
	"context"
	"io/ioutil"
	"os"
	"strings"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

// A response in the format expected by API Gateway.
type Response struct {
	StatusCode      int               `json:"statusCode"`
	IsBase64Encoded bool              `json:"isBase64Encoded"`
	Headers         map[string]string `json:"headers"`
	Body            string            `json:"body"`
}

func HandleRequest(ctx context.Context, request events.APIGatewayProxyRequest) (Response, error) {
	// Get the bucket name from the environment variable
	bucketName := aws.String(os.Getenv("BUCKET_NAME"))

	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		panic("configuration error, " + err.Error())
	}

	client := s3.NewFromConfig(cfg)

	// Build the prefix
	prefix := "rrweb/recordings/sessionId=" + request.PathParameters["sessionId"] + "/"

	// Get the list of objects
	listInput := &s3.ListObjectsV2Input{
		Bucket: bucketName,
		Prefix: aws.String(prefix),
	}

	listOutput, err := client.ListObjectsV2(ctx, listInput)
	if err != nil {
		// If we get an error, make sure to include the bucket name
		// and prefix in the error message. bucketName is a pointer
		// to a string and must be dereferenced before use.
		panic("unable to list items in bucket " + *bucketName + "/" + prefix + ", " + err.Error())
	}

	var content []string
	for _, item := range listOutput.Contents {
		getObjectInput := &s3.GetObjectInput{
			Bucket: bucketName,
			Key:    item.Key,
		}

		resp, err := client.GetObject(ctx, getObjectInput)
		if err != nil {
			panic("unable to get object, " + err.Error())
		}

		body, err := ioutil.ReadAll(resp.Body)
		if err != nil {
			panic("unable to read object, " + err.Error())
		}

		content = append(content, string(body))
	}

	return Response{
		StatusCode:      200,
		IsBase64Encoded: false,
		Headers: map[string]string{
			"Content-Type":                "application/jsonl+json",
			"Access-Control-Allow-Origin": "*",
		},
		Body: strings.Join(content, "\n"),
	}, nil
}

func main() {
	lambda.Start(HandleRequest)
}
