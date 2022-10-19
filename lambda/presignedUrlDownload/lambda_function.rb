require 'json'
require "aws-sdk-s3"


class LambdaS3Wrapper
  attr_reader :credentials, :s3_bucket, :region, :log_prefix, :object_key
  
  STATUS = {
    :pending => 0,
    :success => 1,
    :fail => -1,
  }


  def initialize(bucket_name,object_key,log_prefix = nil,region = nil)
    @bucket_name = bucket_name
    @object_key = object_key
    @log_prefix = log_prefix
    @region = region
    @credentials = self.assume_role
    @s3_bucket = Aws::S3::Bucket.new(@bucket_name,credentials: @credentials)
  end
  
  def get_download_url
    output_file_name = "output_#{File.basename(@object_key, '.*') }.csv"
    if @s3_bucket.object(output_file_name).exists?
      return {
        :statusCode => STATUS[:success],
        :downloadUrl => self::get_presigned_url(output_file_name),
        :message => "Success"
      }
    end
    step_state_file_name = "step-state-#{@object_key}"
    if @s3_bucket.object(step_state_file_name).exists?
        step_result_str = @s3_bucket.object(step_state_file_name).get.body.read
        step_result = JSON.parse(step_result_str)
        if step_result["status"] == "fail"
          return {
            :statusCode => STATUS[:fail],
            :message => "Step Function Execution Fail"
          }
        end
        return {
          :statusCode => STATUS[:pending],
          :message => "Step Function Status => #{step_result['status']}"
        }
    end
    if @s3_bucket.object(@object_key).exists?
      puts "existing"
      head_object = @s3_bucket.object(@object_key).head
      puts head_object
      if head_object && head_object[:last_modified]
        last_modified = Time.parse(head_object[:last_modified].to_s)
        if Time.now <= last_modified + (1 * 60)
          return {
            :statusCode => STATUS[:pending],
            :message => "Wait Step Function Execute"
          }
        end
      end
    end
      {
        :statusCode => STATUS[:fail],
        :message => "Please retry fail"
      }
  end
  
  def log(message)
    if @log_prefix.nil?
      puts message
    else
      puts "#{@log_prefix} ====>> #{message}"
    end
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
  
  # Creates a presigned URL that can be used to upload content to an object.
  #
  # @param bucket [Aws::S3::Bucket] An existing Amazon S3 bucket.
  # @param object_key [String] The key to give the uploaded object.
  # @return [URI, nil] The parsed URI if successful; otherwise nil.
  def get_presigned_url(object_key)
    # maximun 7 days (7*24*60*60)
    # min 1s (1)
    url = @s3_bucket.object(object_key).presigned_url(:get,expires_in: 60)
    log "Created presigned URL: #{url}."
    URI(url)
  rescue Aws::Errors::ServiceError => e
    log "Couldn't create presigned URL for #{@s3_bucket.name}:#{object_key}. Here's why: #{e.message}"
    raise e
  end

end

def lambda_handler(event:, context:)
  body = JSON.parse(event["body"])
  bucket_name = body["bucket_name"]
  object_key = body["file_name"]
  lambdaS3Wrapper = LambdaS3Wrapper.new(bucket_name,object_key)
  {
    "isBase64Encoded": false,
    "statusCode": 200,
    "headers": {
      "Access-Control-Allow-Origin": "*"
    },
    "body":JSON.generate(lambdaS3Wrapper.get_download_url) 
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
