import boto3
import os

def handler(event, context):
    github_token = os.environ['GITHUBToken']
    
    sns = boto3.client('sns')
    cloudformation = boto3.client('cloudformation')
    
    # Publish an SNS message to the right topic
    topics = sns.list_topics()
    for topic in topics['Topics']:
        if 'BillingEmailAlertTopic' in topic['TopicArn']:
            sns.publish(TopicArn=topic['TopicArn'], Message='You have reached the limit of your AWS sandbox budget. We’ll proceed with the reset of this environment and destroy all the resources.')

    # Create the stack to nuke resources
    cloudformation.create_stack(
        StackName='cfn-nuke-stack',
        Capabilities=['CAPABILITY_IAM', 'CAPABILITY_NAMED_IAM'],
        TemplateURL='https://cf-template-datascientest-sandboxes.s3.amazonaws.com/aws-wipe-service.yaml',
        Parameters=[
            {'ParameterKey': 'GitUser', 'ParameterValue': 'antho-data'},
            {'ParameterKey': 'GitRepo', 'ParameterValue': 'sandbox-automation'},
            {'ParameterKey': 'GitBranch', 'ParameterValue': 'main'},
            {'ParameterKey': 'GitToken', 'ParameterValue': github_token},
            {'ParameterKey': 'AWSNukeVersionNumber', 'ParameterValue': '2.21.0'},
            {'ParameterKey': 'AWSNukeConfigFile', 'ParameterValue': 'aws-nuke-config/config.yaml'},
            {'ParameterKey': 'AWSNukeProfileName', 'ParameterValue': 'nuke'}
        ]
    )
