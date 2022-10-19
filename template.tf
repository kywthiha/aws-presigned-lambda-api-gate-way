#
# VARIABLES
#
variable "aws_region" {
  description = "AWS region to launch sample"
  default     = "us-east-1"
}
#
# PROVIDER
#
provider "aws" {
  region = var.aws_region
}
#
# DATA
#
# retrieves the default vpc for this region
data "aws_vpc" "default" {
  default = true
}

# retrieves the subnet ids in the default vpc
data "aws_subnets" "all" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}


data "archive_file" "lambda_presignedUrlDownload_file" {
  type = "zip"

  source_dir  = "${path.module}/lambda/presignedUrlDownload"
  output_path = "${path.module}/lambda/presignedUrlDownload.zip"
}

data "archive_file" "lambda_presignedUrlUpload_file" {
  type = "zip"

  source_dir  = "${path.module}/lambda/presignedUrlUpload"
  output_path = "${path.module}/lambda/presignedUrlUpload.zip"
}

resource "random_pet" "lambda_bucket_name" {
  prefix = "learn-terraform-functions"
  length = 4
}

resource "aws_s3_bucket" "lambda_bucket" {
  bucket        = random_pet.lambda_bucket_name.id
  force_destroy = true
}

resource "aws_s3_bucket_acl" "lambda_bucket" {
  bucket = aws_s3_bucket.lambda_bucket.id
  acl    = "private"
}

resource "aws_s3_object" "lambda_presignedUrlDownload_s3" {
  bucket = aws_s3_bucket.lambda_bucket.id

  key    = "lambda_presignedUrlDownload.zip"
  source = data.archive_file.lambda_presignedUrlDownload_file.output_path

  etag = filemd5(data.archive_file.lambda_presignedUrlDownload_file.output_path)
}

resource "aws_s3_object" "lambda_presignedUrlUpload_s3" {
  bucket = aws_s3_bucket.lambda_bucket.id

  key    = "lambda_presignedUrlUpload.zip"
  source = data.archive_file.lambda_presignedUrlUpload_file.output_path

  etag = filemd5(data.archive_file.lambda_presignedUrlUpload_file.output_path)
}

resource "aws_iam_role" "lambda_exec" {
  name = "serverless_lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}


resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role" "lambda_s3_full_access_role" {
  name = "lambda_s3_full_access_role"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "${aws_iam_role.lambda_exec.arn}"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
}


resource "aws_iam_role_policy_attachment" "lambda_s3_full_access_policy" {
  role       = aws_iam_role.lambda_s3_full_access_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_lambda_function" "lambda_presignedUrlDownload_function" {
  function_name = "lambda_presignedUrlDownload_function"

  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = aws_s3_object.lambda_presignedUrlDownload_s3.key

  runtime = "ruby2.7"
  handler = "lambda_function.lambda_handler"
  environment {
    variables = {
      ROLE_ARN          = "${aws_iam_role.lambda_s3_full_access_role.arn}",
      ROLE_SESSION_NAME = "lambda_s3_full_access_role"
    }
  }

  source_code_hash = data.archive_file.lambda_presignedUrlDownload_file.output_base64sha256

  role = aws_iam_role.lambda_exec.arn
}

resource "aws_cloudwatch_log_group" "lambda_presignedUrlDownload_cloudwatch_log_group" {
  name = "/aws/lambda/${aws_lambda_function.lambda_presignedUrlDownload_function.function_name}"

  retention_in_days = 30
}

resource "aws_lambda_function" "lambda_presignedUrlUpload_function" {
  function_name = "lambda_presignedUrlUpload_function"

  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = aws_s3_object.lambda_presignedUrlUpload_s3.key

  runtime = "ruby2.7"
  handler = "lambda_function.lambda_handler"
  environment {
    variables = {
      ROLE_ARN          = "${aws_iam_role.lambda_s3_full_access_role.arn}",
      ROLE_SESSION_NAME = "lambda_s3_full_access_role"
    }
  }

  source_code_hash = data.archive_file.lambda_presignedUrlUpload_file.output_base64sha256

  role = aws_iam_role.lambda_exec.arn
}

resource "aws_cloudwatch_log_group" "lambda_presignedUrlUpload_cloudwatch_log_group" {
  name = "/aws/lambda/${aws_lambda_function.lambda_presignedUrlUpload_function.function_name}"

  retention_in_days = 30
}

resource "aws_api_gateway_rest_api" "image_process" {
  name        = "image-process"
  description = "Terraform Serverless Application Example"
}

resource "aws_api_gateway_resource" "presigned_url_download_resource" {
  rest_api_id = aws_api_gateway_rest_api.image_process.id
  parent_id   = aws_api_gateway_rest_api.image_process.root_resource_id
  path_part   = "presigned-url-download"
}

resource "aws_api_gateway_method" "options_method" {
  rest_api_id   = aws_api_gateway_rest_api.image_process.id
  resource_id   = aws_api_gateway_resource.presigned_url_download_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_method_response" "options_200" {
  rest_api_id = aws_api_gateway_rest_api.image_process.id
  resource_id = aws_api_gateway_resource.presigned_url_download_resource.id
  http_method = aws_api_gateway_method.options_method.http_method
  status_code = "200"
  response_models = {
    "application/json" = "Empty"
  }
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
  depends_on = [aws_api_gateway_method.options_method]
}

resource "aws_api_gateway_integration" "options_integration" {
  rest_api_id = aws_api_gateway_rest_api.image_process.id
  resource_id = aws_api_gateway_resource.presigned_url_download_resource.id
  http_method = aws_api_gateway_method.options_method.http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = <<EOF
{
  "statusCode": 200
}
EOF
  }
  depends_on = [aws_api_gateway_method.options_method]
}

resource "aws_api_gateway_integration_response" "options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.image_process.id
  resource_id = aws_api_gateway_resource.presigned_url_download_resource.id
  http_method = aws_api_gateway_method.options_method.http_method
  status_code = aws_api_gateway_method_response.options_200.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS,POST,PUT'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_method_response.options_200]
}

resource "aws_api_gateway_method" "presigned_url_download_method" {
  rest_api_id   = aws_api_gateway_rest_api.image_process.id
  resource_id   = aws_api_gateway_resource.presigned_url_download_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "presigned_url_download_integration" {
  rest_api_id = aws_api_gateway_rest_api.image_process.id
  resource_id = aws_api_gateway_resource.presigned_url_download_resource.id
  http_method = aws_api_gateway_method.presigned_url_download_method.http_method

  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = aws_lambda_function.lambda_presignedUrlDownload_function.invoke_arn
}

resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.image_process.id
  resource_id = aws_api_gateway_resource.presigned_url_download_resource.id
  http_method = aws_api_gateway_method.presigned_url_download_method.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
  depends_on = [
    aws_api_gateway_integration.presigned_url_download_integration
  ]
}

resource "aws_api_gateway_integration_response" "MyDemoIntegrationResponse" {
  rest_api_id = aws_api_gateway_rest_api.image_process.id
  resource_id = aws_api_gateway_resource.presigned_url_download_resource.id
  http_method = aws_api_gateway_method.presigned_url_download_method.http_method
  status_code = aws_api_gateway_method_response.response_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
  depends_on = [
    aws_api_gateway_integration.presigned_url_download_integration
  ]
}

resource "aws_lambda_permission" "image_process_lambda_api_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_presignedUrlDownload_function.function_name
  principal     = "apigateway.amazonaws.com"

  # The /*/* portion grants access from any method on any resource
  # within the API Gateway "REST API".
  source_arn = "${aws_api_gateway_rest_api.image_process.execution_arn}/*/*"
}

resource "aws_api_gateway_resource" "presigned_url_upload_resource" {
  rest_api_id = aws_api_gateway_rest_api.image_process.id
  parent_id   = aws_api_gateway_rest_api.image_process.root_resource_id
  path_part   = "presigned-url-upload"
}

resource "aws_api_gateway_method" "presigned_url_upload_resource_options_method" {
  rest_api_id   = aws_api_gateway_rest_api.image_process.id
  resource_id   = aws_api_gateway_resource.presigned_url_upload_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_method_response" "presigned_url_upload_resource_options_200" {
  rest_api_id = aws_api_gateway_rest_api.image_process.id
  resource_id = aws_api_gateway_resource.presigned_url_upload_resource.id
  http_method = aws_api_gateway_method.presigned_url_upload_resource_options_method.http_method
  status_code = "200"
  response_models = {
    "application/json" = "Empty"
  }
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
  depends_on = [aws_api_gateway_method.presigned_url_upload_resource_options_method]
}

resource "aws_api_gateway_integration" "presigned_url_upload_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.image_process.id
  resource_id = aws_api_gateway_resource.presigned_url_upload_resource.id
  http_method = aws_api_gateway_method.presigned_url_upload_resource_options_method.http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = <<EOF
{
  "statusCode": 200
}
EOF
  }
  depends_on = [aws_api_gateway_method.presigned_url_upload_resource_options_method]
}

resource "aws_api_gateway_integration_response" "presigned_url_upload_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.image_process.id
  resource_id = aws_api_gateway_resource.presigned_url_upload_resource.id
  http_method = aws_api_gateway_method.presigned_url_upload_resource_options_method.http_method
  status_code = aws_api_gateway_method_response.presigned_url_upload_resource_options_200.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS,POST,PUT'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_method_response.presigned_url_upload_resource_options_200]
}

resource "aws_api_gateway_method" "presigned_url_upload_method" {
  rest_api_id   = aws_api_gateway_rest_api.image_process.id
  resource_id   = aws_api_gateway_resource.presigned_url_upload_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "presigned_url_upload_integration" {
  rest_api_id = aws_api_gateway_rest_api.image_process.id
  resource_id = aws_api_gateway_resource.presigned_url_upload_resource.id
  http_method = aws_api_gateway_method.presigned_url_upload_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.lambda_presignedUrlUpload_function.invoke_arn
}

resource "aws_api_gateway_method_response" "presigned_url_upload_response_200" {
  rest_api_id = aws_api_gateway_rest_api.image_process.id
  resource_id = aws_api_gateway_resource.presigned_url_upload_resource.id
  http_method = aws_api_gateway_method.presigned_url_upload_method.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
  depends_on = [
    aws_api_gateway_integration.presigned_url_upload_integration
  ]
}

resource "aws_lambda_permission" "image_process_presigned_url_upload_lambda_api_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_presignedUrlUpload_function.function_name
  principal     = "apigateway.amazonaws.com"

  # The /*/* portion grants access from any method on any resource
  # within the API Gateway "REST API".
  source_arn = "${aws_api_gateway_rest_api.image_process.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "presigned_url_download_deployment" {
  depends_on = [
    aws_api_gateway_integration.presigned_url_download_integration,
    aws_api_gateway_integration.options_integration,
    aws_api_gateway_integration_response.MyDemoIntegrationResponse,
    aws_api_gateway_integration_response.options_integration_response,
    aws_api_gateway_integration.presigned_url_upload_integration,
    aws_api_gateway_integration.presigned_url_upload_options_integration,
    aws_api_gateway_integration_response.presigned_url_upload_options_integration_response
  ]

  rest_api_id = aws_api_gateway_rest_api.image_process.id
  stage_name  = "test"
}
