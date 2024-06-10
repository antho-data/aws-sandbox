#!/bin/bash

# Script used to nuke a chosen student account

# Check if AWS_PROFILE is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <AWS_PROFILE>"
  exit 1
fi

# Export the AWS_PROFILE
export AWS_PROFILE=$1

# Check for KMS keys (CMK) in specified regions
check_kms_keys() {
  regions=("us-east-1" "eu-west-3")

  for region in "${regions[@]}"; do
    echo "Checking for KMS keys in region $region..."
    keys=$(aws kms list-keys --region "$region" --query 'Keys[*].KeyId' --output text)
    for key in $keys; do
      key_info=$(aws kms describe-key --key-id "$key" --region "$region" --query 'KeyMetadata.KeyManager' --output text)
      if [ "$key_info" = "CUSTOMER" ]; then
        echo "Customer managed KMS key found in region $region. Aborting script."
        exit 1
      fi
    done
  done
}

# Destroy IAM entities and S3 buckets
destroy_resources() {
  echo "Burning all IAM entities and buckets except AWS managed, this may generate errors"
  sleep 10

  aws s3 ls | cut -d" " -f 3 | xargs -I{} aws s3 rb s3://{} --force

  for user in $(aws iam list-users --query 'Users[*].UserName' --output text); do
    user_policies=$(aws iam list-user-policies --user-name "$user" --query 'PolicyNames[*]' --output text)
    for policy in $user_policies; do
      aws iam delete-user-policy --user-name "$user" --policy-name "$policy"
    done

    user_attached_policies=$(aws iam list-attached-user-policies --user-name "$user" --query 'AttachedPolicies[*].PolicyArn' --output text)
    for policy_arn in $user_attached_policies; do
      aws iam detach-user-policy --user-name "$user" --policy-arn "$policy_arn"
    done

    user_groups=$(aws iam list-groups-for-user --user-name "$user" --query 'Groups[*].GroupName' --output text)
    for group in $user_groups; do
      aws iam remove-user-from-group --user-name "$user" --group-name "$group"
    done

    user_access_keys=$(aws iam list-access-keys --user-name "$user" --query 'AccessKeyMetadata[*].AccessKeyId' --output text)
    for key in $user_access_keys; do
      aws iam delete-access-key --user-name "$user" --access-key-id "$key"
    done

    aws iam delete-login-profile --user-name "$user"
    aws iam delete-user --user-name "$user"
  done

  for group in $(aws iam list-groups --query 'Groups[*].GroupName' --output text); do
    group_policies=$(aws iam list-group-policies --group-name "$group" --query 'PolicyNames[*]' --output text)
    for policy in $group_policies; do
      aws iam delete-group-policy --group-name "$group" --policy-name "$policy"
    done

    group_attached_policies=$(aws iam list-attached-group-policies --group-name "$group" --query 'AttachedPolicies[*].PolicyArn' --output text)
    for policy_arn in $group_attached_policies; do
      aws iam detach-group-policy --group-name "$group" --policy-arn "$policy_arn"
    done

    aws iam delete-group --group-name "$group"
  done

  for policy_arn_local in $(aws iam list-policies --scope 'Local' --query 'Policies[*].Arn' --output text); do
    aws iam delete-policy --policy-arn "$policy_arn_local"
  done

  for role in $(aws iam list-roles --query 'Roles[*].RoleName' --output text); do
    role_policies=$(aws iam list-role-policies --role-name "$role" --query 'PolicyNames[*]' --output text)
    for policy in $role_policies; do
      aws iam delete-role-policy --role-name "$role" --policy-name "$policy"
    done

    role_attached_policies=$(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[*].PolicyArn' --output text)
    for policy_arn in $role_attached_policies; do
      aws iam detach-role-policy --role-name "$role" --policy-arn "$policy_arn"
    done

    aws iam delete-role --role-name "$role"
  done
}

# Recreate default VPCs
recreate_default_vpc() {
  regions=("us-east-1" "eu-west-3")
  for region in "${regions[@]}"; do
    aws ec2 create-default-vpc --region "$region"
  done
}

# Main function
main() {
  # Confirm account to destroy
  cat "$HOME/.aws/credentials" | grep -A1 "$1" | head -2
  echo
  read -s -n 30 -p "Do you want to proceed?"

  # Check for KMS keys
  check_kms_keys

  # Destroy resources
  destroy_resources

  # Perform AWS Nuke
  ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
  ACCOUNT_ALIAS="datascientest-$ACCOUNT_ID"
  aws iam create-account-alias --account-alias "$ACCOUNT_ALIAS"
  aws-nuke --profile "$AWS_PROFILE" --config "./config.yaml" --force --no-dry-run
  aws cloudformation delete-stack --stack-name "cfn-nuke-stack" --region "us-east-1"
  aws cloudformation delete-stack --stack-name "cfn-freeze-stack" --region "us-east-1"
  aws cloudformation delete-stack --stack-name "sandbox-setup-billing-alerts" --region "us-east-1"
  aws cloudformation delete-stack --stack-name "sandbox-init-stack" --region "us-east-1"
  aws iam delete-account-alias --account-alias "$ACCOUNT_ALIAS"

  # Recreate default VPCs
  recreate_default_vpc

  echo "** Destroying all the AWS Sandbox !!"
  echo ""
  echo "** Sandbox destroyed, you should check the account"
}

main "$1"
