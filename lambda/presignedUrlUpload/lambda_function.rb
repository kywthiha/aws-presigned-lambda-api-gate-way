require 'json'
require "aws-sdk-s3"

# Creates a presigned URL that can be used to upload content to an object.
#
# @param bucket [Aws::S3::Bucket] An existing Amazon S3 bucket.
# @param object_key [String] The key to give the uploaded object.
# @return [URI, nil] The parsed URI if successful; otherwise nil.
def get_presigned_url(bucket, object_key)
  url = bucket.object(object_key).presigned_url(:put)
  puts "Created presigned URL: #{url}."
  URI(url)
rescue Aws::Errors::ServiceError => e
  puts "Couldn't create presigned URL for #{bucket.name}:#{object_key}. Here's why: #{e.message}"
end

# Sets CORS rules on a bucket.
#
# @param allowed_methods [Array<String>] The types of HTTP requests to allow.
# @param allowed_origins [Array<String>] The origins to allow.
# @returns [Boolean] True if the CORS rules were set; otherwise, false.
def set_cors(bucket_cors)
  bucket_cors.put(
    cors_configuration: {
      cors_rules: [
        {
          allowed_methods: %w[GET PUT],
          allowed_origins: %w[*],
          allowed_headers: %w[*],
          max_age_seconds: 3600
        }
      ]
    }
    )
rescue Aws::Errors::ServiceError => e
  puts "Couldn't set CORS rules for #{bucket_cors.bucket.name}. Here's why: #{e.message}"
  raise e
end

def lambda_handler(event:, context:)
  bucket_name = event["bucket_name"]
  object_key = event["file_name"]
  sts_client = Aws::STS::Client.new()
  credentials = Aws::AssumeRoleCredentials.new(
      client: sts_client,
      role_arn: ENV["ROLE_ARN"],
      role_session_name: ENV["ROLE_SESSION_NAME"]
    )
  s3 = Aws::S3::Client.new(credentials: credentials)
  bucket = Aws::S3::Bucket.new(bucket_name,credentials: credentials)
  if bucket.exists?
    bucket_cors = Aws::S3::BucketCors.new(bucket_name,credentials: credentials)
  else
    bucket.create({})
    bucket_cors = bucket.cors
    puts "create"
  end
  set_cors(bucket_cors)
  s3.put_bucket_notification_configuration({bucket: bucket_name, notification_configuration: {event_bridge_configuration: {}}})
  {upload_url: get_presigned_url(bucket, object_key)}
end
