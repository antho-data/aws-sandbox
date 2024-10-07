#!/bin/bash

# Fonction pour vérifier les clés KMS
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

# Vérifier la configuration AWS CLI
echo "Checking AWS CLI configuration..."
if ! grep -q aws_access_key_id ~/.aws/config && ! grep -q aws_access_key_id ~/.aws/credentials; then
    echo "AWS config not found or AWS CLI not installed."
    exit 1
fi

# Vérifier si un profil étudiant a été passé en argument
if [ -n "$1" ]; then
    student=$1
    echo "Using specified profile: $student"
else
    echo "No profile specified, running in automatic mode."
fi

# Fonction pour afficher la dernière connexion des utilisateurs IAM
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

# Fonction pour vérifier un profil donné
check_profile() {
    student=$1
    if grep -q "\[$student\]" ~/.aws/credentials; then
        echo
        echo "Checking profile: $student"
        export AWS_PROFILE=$student

        # Vérifier s'il existe des utilisateurs IAM
        num_users=$(aws iam list-users --query 'Users' --output text | wc -l)
        if [[ $num_users -gt 0 ]]; then
            echo "An IAM user exists on $student. The account is in use."

            # Récupérer les coûts actuels
            cost=$(aws ce get-cost-and-usage --time-period Start=$(date +%Y-%m-01),End=$(date -d "$(date +%Y%m01) +1 month -1 day" +%Y-%m-%d) --granularity MONTHLY --metrics UnblendedCost)
            actual_cost=$(echo $cost | jq -r '.ResultsByTime[0].Total.UnblendedCost.Amount')
            echo "Actual cost for $student: $actual_cost"

            # Vérifier les clés KMS
            if check_kms_keys; then
                echo "Profile $student has IAM user and CMK found."
            else
                echo "Profile $student has IAM user but no CMK found."
            fi

            # Vérifier la dernière connexion des utilisateurs IAM
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

# Si un profil est spécifié, l'utiliser directement
if [ -n "$student" ]; then
    check_profile $student
    if [[ $? -ne 0 ]]; then
        echo "Specified profile $student not found or has an issue."
        exit 1
    fi
else
    # Boucle sur les profils d'étudiants de 4 à 90 si aucun profil n'est spécifié
    for i in {4..90}; do
        student="student$i"
        check_profile $student
        if [[ $? -eq 0 ]]; then
            # Si un profil valide est trouvé, continuer
            continue
        fi
    done
fi

echo "Scan completed."
