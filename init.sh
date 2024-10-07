#!/bin/bash

# This script triggers the Datascientest Sandbox creation with the initial CloudFormation templates.
# If the S3 Bucket has not been created, this Script will create the S3 bucket and tag the bucket with the appropriate name.

# Check if access key is set up in your system
if ! grep -q aws_access_key_id ~/.aws/config && ! grep -q aws_access_key_id ~/.aws/credentials; then
   echo "AWS config not found or you don't have AWS CLI installed"
   exit 1
fi

# Prompt to enter the name of the account you wish to create
read -r -p  "* Choose the account you want to deploy (format: student[1-90]):" student

# Check if the chosen profile exists
if ! grep -q "\[$student\]" ~/.aws/credentials; then
  echo "Profile $student not found in AWS credentials"
  exit 1
fi

# Display the chosen profile
cat "${HOME}/.aws/credentials" | grep -A1 "$student" | head -2

# Choosing the account
export AWS_PROFILE=$student

# Fetch the current cost
cost=$(aws ce get-cost-and-usage --time-period Start=$(date +%Y-%m-01),End=$(date -d "`date +%Y%m01` +1 month -1 day" +%Y-%m-%d) --granularity MONTHLY --metrics UnblendedCost)
actual_cost=$(echo $cost | jq -r '.ResultsByTime[0].Total.UnblendedCost.Amount')

echo "Actual cost: $actual_cost"

# Check if there is any IAM user
if [[ $(aws iam list-users --query 'Users' --output text | wc -l) -gt 0 ]]; then
  echo "An IAM user already exists on this account. The account is in use."
  exit 1
fi

# Prompt for various inputs with default values
read -r -p  "[*] Enter the name of the sandbox user (Default value: $student): " username
username="${username:=$student}"

read -r -p  "[*] Enter the billing warning level (This will stop running resources, default value: 100): " warning_level
warning_level="${warning_level:=100}"

read -r -p  "[*] Enter the billing critical level (This triggers the aws nuke pipeline, default value: 150): " critical_level
critical_level="${critical_level:=150}"

read -r -p  "[*] Enter the email of the sandbox user to notify (Student email, default value: dst-student@datascientest.com): " email_student
email_student="${email_student:=dst-student@datascientest.com}"

read -r -p  "[*] Enter the datascientest admin email to notify (Default value: dst-student@datascientest.com): " email_datascientest
email_datascientest="${email_datascientest:=dst-student@datascientest.com}"

read -r -p  "[*] Enter a valid Github token (Default account already provided): " GITHUBToken
GITHUBToken="${GITHUBToken:=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}"

read -r -p  "[*] Enter a valid password for the admin app token (Default token already provided): " gmail_password
gmail_password="${gmail_password:=ennkkbgsgvypdqba}"

userpass=$(pwgen -1 14)

function initsandbox() {
  aws cloudformation create-stack \
    --capabilities "CAPABILITY_IAM" "CAPABILITY_NAMED_IAM" \
    --stack-name sandbox-init-stack --template-body file://aws-user-service.yaml \
    --parameters ParameterKey=UserName,ParameterValue=$username ParameterKey=Password,ParameterValue=$userpass ParameterKey=SESToEmail,ParameterValue=$email_student ParameterKey=SESPassword,ParameterValue=$gmail_password --region us-east-1

  # Wait for the stack to be created
  echo "Waiting for sandbox-init-stack to be created..."
  sleep 80  
}

function invokeUserLambda() {
  touch response.json

  aws lambda invoke \
    --function-name caller \
    --region us-east-1 response.json
}

function invokeConfigLambda() {
  aws lambda invoke \
    --function-name sandboxTrigger \
    --region us-east-1 response2.json

}

function setupAlerts() {
  # Fetch the S3 bucket name, it has been created randomly by the first stack:
  S3BucketName=$(aws s3api list-buckets --query 'Buckets[*].[Name]' --output text | grep "cfn-datascientest-sandbox-templates-repo" | head -n 1)

  aws cloudformation create-stack \
    --capabilities "CAPABILITY_IAM" "CAPABILITY_NAMED_IAM" "CAPABILITY_AUTO_EXPAND" \
    --stack-name sandbox-setup-billing-alerts --template-body file://aws-alerting-service.yaml \
    --parameters ParameterKey=CriticalLevel,ParameterValue=$critical_level ParameterKey=WarningLevel,ParameterValue=$warning_level \
    ParameterKey=Email,ParameterValue=$email_datascientest ParameterKey=EmailStudent,ParameterValue=$email_student \
    ParameterKey=S3BucketName,ParameterValue=$S3BucketName ParameterKey=GITHUBToken,ParameterValue=$GITHUBToken --region us-east-1

  # Wait for the stack to be created
  echo "Waiting for sandbox-setup-billing-alerts to be created..."
  sleep 10  # 10 sec
}

echo "** Creating the AWS Sandbox user and preparing the sandbox config !! "
echo ""
initsandbox    # Calling the createbucket function
invokeUserLambda
invokeConfigLambda
setupAlerts

echo "** The sandbox-init-stack AWS CloudFormation stack has been created successfully!"
