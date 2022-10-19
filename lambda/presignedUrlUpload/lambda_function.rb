require 'json'
require "aws-sdk-s3"


class LambdaS3Wrapper
  attr_reader :credentials, :s3_client, :s3_bucket, :bucket_name, :region, :log_prefix

  def initialize(bucket_name,log_prefix = nil,region = nil)
    @bucket_name = bucket_name
    @log_prefix = log_prefix
    @region = region
    @credentials = self.assume_role
    @s3_client = Aws::S3::Client.new(credentials: @credentials)
    @s3_bucket = Aws::S3::Bucket.new(@bucket_name,credentials: @credentials)
  end
  
  def log(message)
    if @log_prefix.nil?
      puts message
    else
      puts "#{@log_prefix} ====>> #{message}"
    end
  end

  def bucket_create
    log "Creating bucket #{@bucket_name}."
    if !@s3_bucket.exists?
      if @region.nil?
        @s3_bucket.create()
      else
        @s3_bucket.create(create_bucket_configuration: { location_constraint: @region })
      end
      log "Created bucket #{@bucket_name}."
    else
      log "Exiting bucket #{@bucket_name}."
    end
  rescue Aws::Errors::ServiceError => e
    log "Couldn't create bucket. Here's why: #{e.message}"
    raise e
  end
  
  
  def bucket_event_bridge_enable
    @s3_client.put_bucket_notification_configuration({bucket: @bucket_name, notification_configuration: {event_bridge_configuration: {}}})
    log "Enable event_bridge_configuration in bucket #{@bucket_name}"
  rescue Aws::Errors::ServiceError => e
    log "Couldn't enable event_bridge_configuration. Here's why: #{e.message}"
    raise e
  end

  # Gets temporary credentials that can be used to assume a role.
  #
  # @param role_arn [String] The ARN of the role that is assumed when these credentials
  #                          are used.
  # @param sts_client [AWS::STS::Client] An AWS STS client.
  # @return [Aws::AssumeRoleCredentials] The credentials that can be used to assume the role.
  def assume_role
    sts_client = Aws::STS::Client.new()
    credentials = Aws::AssumeRoleCredentials.new(
      client: sts_client,
      role_arn: ENV["ROLE_ARN"],
      role_session_name: ENV["ROLE_SESSION_NAME"]
    )
    log("Assumed role '#{ENV["ROLE_ARN"]}', got temporary credentials.")
    credentials
  rescue Aws::Errors::ServiceError => e
    log "Couldn't set temporary credentials for #{ENV["ROLE_ARN"]}. Here's why: #{e.message}"
    raise e
  end
  
  
  # Sets CORS rules on a bucket.
  #
  # @param allowed_methods [Array<String>] The types of HTTP requests to allow.
  # @param allowed_origins [Array<String>] The origins to allow.
  # @returns [Boolean] True if the CORS rules were set; otherwise, false.
  def set_cors
    @s3_bucket.cors.put(
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
    log "Set CORS rules for #{@s3_bucket.name}"
  rescue Aws::Errors::ServiceError => e
    log "Couldn't set CORS rules for #{@s3_bucket.name}. Here's why: #{e.message}"
    raise e
  end
  
  # Creates a presigned URL that can be used to upload content to an object.
  #
  # @param bucket [Aws::S3::Bucket] An existing Amazon S3 bucket.
  # @param object_key [String] The key to give the uploaded object.
  # @return [URI, nil] The parsed URI if successful; otherwise nil.
  def get_presigned_url(object_key,metadata)
    # maximun 7 days (7*24*60*60)
    # min 1s (1)
    url = @s3_bucket.object(object_key).presigned_url(:put,expires_in: 60, metadata: metadata)
    log "Created presigned URL: #{url}."
    URI(url)
  rescue Aws::Errors::ServiceError => e
    log "Couldn't create presigned URL for #{@s3_bucket.name}:#{object_key}. Here's why: #{e.message}"
    raise e
  end

end

def generate_s3_bucket(username,service_name)
  "#{username}-#{service_name}"
end

def generate_s3_key(file_name)
  folder = "#{File.basename(file_name,'.*')}_#{Time.now.strftime('%Y%m%d%H%M')}"
  "#{folder}/#{file_name}"
end

def lambda_handler(event:, context:)
    body = JSON.parse(event["body"])
    service_name = body["service_name"]
    file_names = body["file_names"]
    file_name = body["file_name"]
    puts body
    puts event
    auth = event["requestContext"]["authorizer"]["claims"]
    log_prefix = "sub: #{auth['sub']}, email: #{auth['email']}, name: #{auth['cognito:username']}"
    metadata = {username: auth['cognito:username'], email: auth['email'] , sub: auth['sub']}
    lambdaS3Wrapper = LambdaS3Wrapper.new(generate_s3_bucket(auth['cognito:username'],service_name),log_prefix)
    lambdaS3Wrapper.bucket_create()
    lambdaS3Wrapper.set_cors()
    lambdaS3Wrapper.bucket_event_bridge_enable()
    
    responseBody = nil
    if !file_name.nil?
      responseBody = {
         upload_url:  lambdaS3Wrapper.get_presigned_url(generate_s3_key(file_name),metadata)
      }
    elsif file_names && file_names.size > 0
      output_files = []
      file_names.each_with_index do |file_name|
        output_files << {
          file_name: file_name,
          upload_url:  lambdaS3Wrapper.get_presigned_url(generate_s3_key(file_name),metadata)
        }
      end

      responseBody = output_files
    end
    
    {
      "isBase64Encoded": false,
      "statusCode": 200,
      "headers": {
        "Access-Control-Allow-Origin": "*"
      },
      "body":JSON.generate(responseBody) 
    }
rescue Exception => e
    puts e
    {
     "isBase64Encoded": false,
     "statusCode": 403,
     "headers": {
       "Access-Control-Allow-Origin": "*"
     },
     "body":JSON.generate(e),
    }
end