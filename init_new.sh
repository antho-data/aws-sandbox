#!/bin/bash

# Check if a student profile was passed as an argument
if [ -n "$1" ]; then
    student=$1
    echo "Using specified profile: $student"
else
    echo "No profile specified, running in automatic mode."
fi

echo "Checking AWS CLI configuration..."
if ! grep -q aws_access_key_id ~/.aws/config && ! grep -q aws_access_key_id ~/.aws/credentials; then
    echo "AWS config not found or AWS CLI not installed."
    exit 1
fi

# Function to check if a profile exists and is valid
function check_profile() {
    student=$1
    if grep -q "\[$student\]" ~/.aws/credentials; then
        echo "Checking profile: $student"
        export AWS_PROFILE=$student

        # Check if there are any IAM users
        num_users=$(aws iam list-users --query 'Users' --output text | wc -l)
        if [[ $num_users -gt 0 ]]; then
            echo "An IAM user already exists on $student. The account is in use."
            return 1
        fi

        # Fetch the current cost
        cost=$(aws ce get-cost-and-usage --time-period Start=$(date +%Y-%m-01),End=$(date -d "$(date +%Y%m01) +1 month -1 day" +%Y-%m-%d) --granularity MONTHLY --metrics UnblendedCost)
        actual_cost=$(echo $cost | jq -r '.ResultsByTime[0].Total.UnblendedCost.Amount')
        echo "Actual cost for $student: $actual_cost"

        if (( $(echo "$actual_cost >= 5" | bc -l) )); then
            echo "Cost exceeds $5 for $student, moving to the next profile."
            return 1
        fi

        return 0
    else
        echo "Profile $student not found, skipping."
        return 1
    fi
}

# If a student profile is specified, use it directly
if [ -n "$student" ]; then
    check_profile $student
    if [[ $? -ne 0 ]]; then
        echo "Specified profile $student is either in use or has a cost issue."
        exit 1
    fi
else
    # Loop through student profiles from 4 to 90 if no profile is specified
    for i in {4..90}; do
        student="student$i"
        check_profile $student
        if [[ $? -eq 0 ]]; then
            # If a valid profile is found, break the loop
            echo "Selected profile: $student"
            break
        fi
    done
fi

if [[ -z $student ]]; then
    echo "No suitable profile found."
    exit 1
fi

# Use the selected profile for further operations
export AWS_PROFILE=$student

# Display the chosen profile
grep -A1 "\[$student\]" ~/.aws/credentials

read -r -p  "[*] Enter the name of the sandbox user (Default value: $student): " username_input
username="${username_input:=$student}"

read -r -p  "[*] Enter the billing warning level (This will stop running resources, default value: 150): " warning_level_input
warning_level="${warning_level_input:=150}"

read -r -p  "[*] Enter the billing critical level (This triggers the aws nuke pipeline, default value: 200): " critical_level_input
critical_level="${critical_level_input:=200}"

read -r -p  "[*] Enter the email of the sandbox user to notify (Student email, default value: dst-student@datascientest.com): " email_student_input
email_student="${email_student_input:=anthony.j@datascientest.com}"

read -r -p  "[*] Enter the datascientest admin email to notify (Default value: dst-student@datascientest.com): " email_datascientest_input
email_datascientest="${email_datascientest_input:=dst-student@datascientest.com}"

read -r -p  "[*] Enter a valid Github token (Default account already provided): " GITHUBToken_input
GITHUBToken="${GITHUBToken_input:=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}"

read -r -p  "[*] Enter a valid password for the admin app token (Default token already provided): " gmail_password_input
gmail_password="${gmail_password_input:=ffxmvdccrhwckbsg}"

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
