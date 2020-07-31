# Create Key
aws ec2 create-key-pair \
  --region sa-east-1 \
  --key-name spo-jaf-project-key \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/spo-jaf-project-key

chmod 600 ~/.ssh/spo-jaf-project-key

# Create Bucket
aws s3api create-bucket \
--bucket spo-jaf-cf-templates \
--region sa-east-1 \
--create-bucket-configuration LocationConstraint=sa-east-1

# S3 commands
aws s3 ls s3://spo-jaf-cf-templates/
aws s3 rm --recursive s3://spo-jaf-cf-templates/jaf-cf
aws s3 cp --recursive jaf-cf s3://spo-jaf-cf-templates/

# CodeDeploy
## List applications
aws deploy list-applications \
--profile default

## Deploy 
deployId=$(aws deploy create-deployment \
--application-name sgo-prd-jaf-app1 \
--deployment-config-name CodeDeployDefault.OneAtATime \
--deployment-group-name sgo-prd-jaf-app1-group \
--s3-location bucket=spo-mcp-deploy,bundleType=tgz,key=app1/app1-4.0.7.tgz \
--query "deploymentId" \
--output text \
--profile default)

## Wait deploy
aws deploy wait deployment-successful \
--deployment-id $deployId \
--profile default 

# Opsworks
## List Stacks
stackId=$(aws opsworks describe-stacks \
--region us-east-1 \
--query "Stacks[*].{StackId:StackId,Name:Name} " \
--output text \
--profile default)

stackId='<ID>'

## Update cookbooks
deployId=$(aws opsworks create-deployment \
--region us-east-1 \
--output text \
--stack-id $stackId \
--command "{\"Name\":\"update_custom_cookbooks\"}" \
--profile default)

## Wait update finished
aws opsworks wait deployment-successful \
--region us-east-1 \
--deployment-id $deployId \
--profile default

## Update applications configuration
deployId=$(aws opsworks create-deployment \
--region us-east-1 \
--output text \
--stack-id $stackId \
--command "{\"Name\":\"configure\"}" \
--profile default)

## Wait update applications configuration
aws opsworks wait deployment-successful \
--region us-east-1 \
--deployment-id $deployId \
--profile default

## List layers
aws opsworks describe-layers \
--region us-east-1 \
--stack-id $stackId \
--query "Layers[*].{LayerId:LayerId,Name:Shortname}" \
--profile default

# SSM
## List instances
aws ssm describe-instance-information \
--output text \
--query "InstanceInformationList[*]" \
--profile default

## Send command to IntanceID
aws ssm send-command \
--instance-ids "instance ID" \
--document-name "AWS-RunShellScript" \
--comment "IP config" \
--parameters commands=ifconfig \
--output text

## Restart applications
commandId=$(aws ssm send-command \
--profile default \
--document-name "AWS-RunShellScript" \
--targets "Key=tag:opsworks:layer:app1,Values=sgo-prd-jaf-app1-layer" \
--comment "Reload App1" \
--parameters commands='/usr/local/bin/app1 reload' \
--query 'Command.CommandId' \
--output text \
--max-concurrency 1 \
--max-errors 1)

## Check command status
aws ssm list-command-invocations \
--profile default \
--command-id $commandId  \
--output table \
--query 'CommandInvocations[*].{InstanceId:InstanceId, Status:Status}'

# Cloudformation
## Create stack
aws cloudformation create-stack \
--region sa-east-1 \
--stack-name hlg-jaf \
--template-body file://cf-jaf.yml \
--parameters file://parameters.json \
--capabilities CAPABILITY_NAMED_IAM 

## Update stack
aws cloudformation update-stack \
--region sa-east-1 \
--stack-name hlg-jaf \
--template-body file://cf-jaf.yml \
--parameters file://parameters.json \
--capabilities CAPABILITY_NAMED_IAM

# EC2
## List instances based on tag and state
aws ec2 describe-instances \
--filters "Name=tag-value,Values=*jaf*" "Name=instance-state-name,Values=running" \
--query "Reservations[*].Instances[*].{Instance:InstanceId,Name:Tags[?Key=='Name']|[0].Value}" \
--profile default \
--output text



