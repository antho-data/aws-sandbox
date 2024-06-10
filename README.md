# AWS Sandbox Generator

This project is a CloudFormation template to provision an AWS sandbox environment for users. It creates an IAM user with the specified parameters and sends notification emails via SES once the sandbox environment is ready.

## Table of Contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Parameters](#parameters)
- [Mappings](#mappings)
- [Conditions](#conditions)
- [Resources](#resources)
- [Lambda Functions](#lambda-functions)
- [Outputs](#outputs)
- [Usage](#usage)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## Architecture

The CloudFormation stack provisions the following resources:
- An IAM User with specified permissions.
- An IAM Access Key for programmatic access.
- An S3 bucket for storing the sandbox templates.
- Lambda functions to initialize the sandbox and notify the user.
- An SES configuration set for sending emails.

## Prerequisites

Before deploying this stack, ensure the following:
- You have an AWS Organization set up.
- AWS Nuke is configured to clean up resources according to defined thresholds.

## Parameters

| Parameter | Type | Description | Default | Allowed Values |
|-----------|------|-------------|---------|----------------|
| `Group` | String | IAM Group to add the user to. | "None" | Comma separated list of IAM Group names |
| `ManagedPolicy` | String | Predefined Managed Policy to associate with the user. | "Administrator" | Administrator, Billing, DatabaseAdministrator, DataScientist, DeveloperPowerUser, NetworkAdministrator, SecurityAuditor, SupportUser, SystemAdministrator, View-Only, None |
| `Password` | String | Password for the IAM user. | N/A | 8-32 characters, can include special characters !@#$%& |
| `PasswordResetRequired` | String | Require password reset on first login. | "false" | "true", "false" |
| `Path` | String | IAM Path for the user. | "/" | Valid IAM Path |
| `UserName` | String | UserName for the IAM User. | "None" | Valid UserName |
| `SESFromEmail` | String | SES email address for sending notifications. | "dst-student@datascientest.com" | Valid email address |
| `SESToEmail` | String | SES email address to receive notifications. | "dst-student@gmail.com" | Valid email address |
| `SESPassword` | String | SES password for authentication. | N/A | 8-32 characters, can include special characters !@#$%& |

## Mappings

Predefined Managed Policies:

| ManagedPolicy | ARN | GroupRole |
|---------------|-----|-----------|
| Administrator | arn:aws:iam::aws:policy/AdministratorAccess | AdministratorAccess |
| Billing | arn:aws:iam::aws:policy/job-function/Billing | Billing |
| DatabaseAdministrator | arn:aws:iam::aws:policy/job-function/DatabaseAdministrator | DatabaseAdministrator |
| DataScientist | arn:aws:iam::aws:policy/job-function/DataScientist | DataScientist |
| DeveloperPowerUser | arn:aws:iam::aws:policy/PowerUserAccess | PowerUserAccess |
| NetworkAdministrator | arn:aws:iam::aws:policy/job-function/NetworkAdministrator | NetworkAdministrator |
| SecurityAuditor | arn:aws:iam::aws:policy/SecurityAudit | SecurityAudit |
| SupportUser | arn:aws:iam::aws:policy/job-function/SupportUser | SupportUser |
| SystemAdministrator | arn:aws:iam::aws:policy/job-function/SystemAdministrator | SystemAdministrator |
| View-Only | arn:aws:iam::aws:policy/job-function/ViewOnlyAccess | ViewOnlyAccess |
| None | arn:aws:iam::aws:policy/NoAccess | NoAccess |

## Conditions

Conditions used in the template:

- `hasManagedPolicy`: Checks if a Managed Policy is specified.
- `hasUserName`: Checks if a UserName is specified.
- `hasGroup`: Checks if a Group is specified.

## Resources

The CloudFormation stack provisions the following resources:

- **IAM User**: Creates an IAM user with the specified properties.
- **IAM Access Key**: Generates an access key for the IAM user.
- **S3 Bucket**: Stores the sandbox templates.
- **SES Configuration Set**: Configures SES for sending emails.
- **Lambda Functions**: Handles sandbox initialization and user notifications.

## Lambda Functions

### User Notification Lambda

Sends an email notification once the IAM user is created.

#### Environment Variables

- `SES_FROM_EMAIL`
- `SES_TO_EMAIL`
- `SES_PASS`
- `SES_CONFIG_SET_NAME`
- `SES_User_NAME`
- `SES_User_Password`
- `SES_User_AccessKey`
- `SES_User_SecretKey`

#### Code Snippet

```python
import os
import boto3
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

from_email = os.environ["SES_FROM_EMAIL"]
to_email = os.environ["SES_TO_EMAIL"]
pass_email = os.environ["SES_PASS"]
config_set_name = os.environ["SES_CONFIG_SET_NAME"]
user_name = os.environ["SES_User_NAME"]
user_pass = os.environ["SES_User_Password"]
user_access_key = os.environ["SES_User_AccessKey"]
user_secret_key = os.environ["SES_User_SecretKey"]

def lambda_handler(event, context):
    user_aws_account_id = boto3.client("sts").get_caller_identity()["Account"]

    body_html = f"""
    <html>
        <head></head>
        <body>
            <h2>Your Datascientest AWS Sandbox is live!</h2>
            <br/>
            <p>You have been granted access to an aws sandbox environment.
            You could login to <a href="https://aws.amazon.com/" target="_blank">Amazon Web Services</a> using the following AWS account id: <b>{user_aws_account_id}</b></p>
            <p> For console (web browser) access, use the following credentials:</p>
                - <b>username</b>: {user_name}
                - <b>password</b>: {user_pass}
            <p>For programmatic access, please read the <a href="https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html" target="_blank">documentation</a> and use the following access key and secret key within your aws cli:</p>
                - <b>AccessKey</b>: {user_access_key}
                - <b>SecretKey</b>: {user_secret_key}
            </body>
    </html>
    """

    msg = MIMEMultipart('alternative')
    msg['Subject'] = 'Your Datascientest AWS Sandbox is ready'
    msg['From'] = from_email
    msg['To'] = to_email

    part1 = MIMEText(body_html, 'html')
    msg.attach(part1)

    try:
        server = smtplib.SMTP_SSL('smtp.gmail.com', 465)
        server.ehlo()
        server.login(from_email, pass_email)
        server.sendmail(from_email, to_email, msg.as_string())
        server.close()
        print('Email sent!')
    except:
        print('Something went wrong...')
