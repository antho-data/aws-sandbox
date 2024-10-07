#!/bin/bash

# Fonction pour v�rifier les cl�s KMS
check_kms_keys() {
  regions=("us-east-1" "eu-west-3")

  for region in "${regions[@]}"; do
    echo "Checking for KMS keys in region $region..."
    keys=$(aws kms list-keys --region "$region" --query 'Keys[*].KeyId' --output text)
    for key in $keys; do
      key_info=$(aws kms describe-key --key-id "$key" --region "$region" --query 'KeyMetadata.KeyManager' --output text)
      if [ "$key_info" = "CUSTOMER" ]; then
        echo "Customer managed KMS key found in region $region for $student."
        return 0
      fi
    done
  done
  return 1
}

# V�rifier la configuration AWS CLI
echo "Checking AWS CLI configuration..."
if ! grep -q aws_access_key_id ~/.aws/config && ! grep -q aws_access_key_id ~/.aws/credentials; then
    echo "AWS config not found or AWS CLI not installed."
    exit 1
fi

# V�rifier si un profil �tudiant a �t� pass� en argument
if [ -n "$1" ]; then
    student=$1
    echo "Using specified profile: $student"
else
    echo "No profile specified, running in automatic mode."
fi

# Fonction pour afficher la derni�re connexion des utilisateurs IAM
check_user_last_login() {
    users=$(aws iam list-users --query 'Users[*].UserName' --output text)
    for user in $users; do
        last_login=$(aws iam get-user --user-name "$user" --query 'User.PasswordLastUsed' --output text 2>/dev/null)
        if [ "$last_login" != "None" ]; then
            echo "User $user last login: $last_login"
        else
            echo "User $user has never logged into the console."
        fi
    done
}

# Fonction pour v�rifier un profil donn�
check_profile() {
    student=$1
    if grep -q "\[$student\]" ~/.aws/credentials; then
        echo
        echo "Checking profile: $student"
        export AWS_PROFILE=$student

        # V�rifier s'il existe des utilisateurs IAM
        num_users=$(aws iam list-users --query 'Users' --output text | wc -l)
        if [[ $num_users -gt 0 ]]; then
            echo "An IAM user exists on $student. The account is in use."

            # R�cup�rer les co�ts actuels
            cost=$(aws ce get-cost-and-usage --time-period Start=$(date +%Y-%m-01),End=$(date -d "$(date +%Y%m01) +1 month -1 day" +%Y-%m-%d) --granularity MONTHLY --metrics UnblendedCost)
            actual_cost=$(echo $cost | jq -r '.ResultsByTime[0].Total.UnblendedCost.Amount')
            echo "Actual cost for $student: $actual_cost"

            # V�rifier les cl�s KMS
            if check_kms_keys; then
                echo "Profile $student has IAM user and CMK found."
            else
                echo "Profile $student has IAM user but no CMK found."
            fi

            # V�rifier la derni�re connexion des utilisateurs IAM
            check_user_last_login
        else
            echo "No IAM users found on $student."
        fi
        return 0
    else
        echo "Profile $student not found, skipping."
        return 1
    fi
}

# Si un profil est sp�cifi�, l'utiliser directement
if [ -n "$student" ]; then
    check_profile $student
    if [[ $? -ne 0 ]]; then
        echo "Specified profile $student not found or has an issue."
        exit 1
    fi
else
    # Boucle sur les profils d'�tudiants de 4 � 90 si aucun profil n'est sp�cifi�
    for i in {4..90}; do
        student="student$i"
        check_profile $student
        if [[ $? -eq 0 ]]; then
            # Si un profil valide est trouv�, continuer
            continue
        fi
    done
fi

echo "Scan completed."
