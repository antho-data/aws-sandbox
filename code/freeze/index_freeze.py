import boto3
import os

def handler(event, context):
    group_name = 'datascientest-readonlyusers'
    policy_arn = 'arn:aws:iam::aws:policy/ReadOnlyAccess'
    github_token = os.environ['GITHUBToken']
    
    iam = boto3.client('iam')
    sns = boto3.client('sns')
    cloudformation = boto3.client('cloudformation')
    
    # Verification if groupname exist
    try:
        iam.get_group(GroupName=group_name)
    except iam.exceptions.NoSuchEntityException:
        iam.create_group(GroupName=group_name)
        iam.attach_group_policy(GroupName=group_name, PolicyArn=policy_arn)

    # Publish an SNS message to the right topic
    topics = sns.list_topics()
    for topic in topics['Topics']:
        if 'BillingEmailAlertTopic' in topic['TopicArn']:
            sns.publish(TopicArn=topic['TopicArn'], Message='You reached the warning level of your AWS sandbox budget. We’ll stop your resources to reduce unwanted billing.')

    # Make all users Read Only by adding them to the right group
    users = iam.list_users()
    for user in users['Users']:
        username = user['UserName']
        policies = iam.list_attached_user_policies(UserName=username)
        for policy in policies['AttachedPolicies']:
            iam.detach_user_policy(UserName=username, PolicyArn=policy['PolicyArn'])
        
        groups = iam.list_groups_for_user(UserName=username)
        for group in groups['Groups']:
            iam.remove_user_from_group(UserName=username, GroupName=group['GroupName'])

        iam.add_user_to_group(UserName=username, GroupName=group_name)

    # Create the codepipeline freeze process to start freezing resources 
    cloudformation.create_stack(
        StackName='cfn-freeze-stack',
        Capabilities=['CAPABILITY_IAM', 'CAPABILITY_NAMED_IAM'],
        TemplateURL='https://cf-template-datascientest-sandboxes.s3.amazonaws.com/aws-freeze-service.yaml',
        Parameters=[
            {'ParameterKey': 'GitToken', 'ParameterValue': github_token},
            {'ParameterKey': 'NotificationEmailAddress', 'ParameterValue': 'dst-student@datascientest.com'},
            {'ParameterKey': 'WhenToExecute', 'ParameterValue': 'cron(0 0 * * ? *)'},
            {'ParameterKey': 'RetentionInDays', 'ParameterValue': '14'},
            {'ParameterKey': 'AWSFreezeProfileName', 'ParameterValue': 'freeze'}
        ]
    )
