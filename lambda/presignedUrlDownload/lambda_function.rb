require 'json'
require "aws-sdk-s3"

def lambda_handler(event:, context:)
  bucket_name = event["bucket_name"]
  object_key = event["file_name"]
  sts_client = Aws::STS::Client.new()
  credentials = Aws::AssumeRoleCredentials.new(
      client: sts_client,
      role_arn: ENV["ROLE_ARN"],
      role_session_name: ENV["ROLE_SESSION_NAME"]
    )
   object = Aws::S3::Object.new(bucket_name, object_key,credentials: credentials)
   if object.exists?
     {download_url: object.presigned_url(:get)}
   else
     {message: "File Not Found"}
   end
end
