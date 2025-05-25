# AWS Systems Manager CLI Examples

> **Author:** Jeffrey Stuhr  
> **Blog:** [TechByJeff](https://techbyjeff.ghost.io/ghost/#/editor/post/683141785f4cc30001818513)

This document contains a collection of AWS CLI commands for working with AWS Systems Manager, demonstrating various SSM features including instance management, command execution, and CloudWatch integration.

## Prerequisites
- AWS CLI v2 with configured credentials
- Appropriate IAM permissions for Systems Manager operations

## Usage
Replace placeholder values like `i-YOUR-INSTANCE-ID` with actual values before running commands. Run each command individually or edit as needed.

---

## Instance Management

### List all managed instances
```bash
aws ssm describe-instance-information \
    --query 'InstanceInformationList[*].[InstanceId,PingStatus,PlatformType,AgentVersion]' \
    --output table
```

### Check specific instance
```bash
aws ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=i-YOUR-INSTANCE-ID" \
    --query 'InstanceInformationList[0]'
```

## Manual Activation

### Create an activation (from your local machine)
```bash
aws ssm create-activation \
    --default-instance-name "MyWindowsServer" \
    --description "Manual activation for troubleshooting" \
    --iam-role "EC2-SSM-Role" \
    --registration-limit 1
```

Example output:
```json
{
    "ActivationId": "1234abcd-12ab-34cd-56ef-1234567890ab",
    "ActivationCode": "ABCDEFGHIJKLMNOP"
}
```

### Register the SSM agent on the instance
```bash
amazon-ssm-agent -register -code "ABCDEFGHIJKLMNOP" -id "1234abcd-12ab-34cd-56ef-1234567890ab" -region "us-east-1"
```

## Network Configuration

### Get your security group ID
```bash
INSTANCE_ID="i-YOUR-INSTANCE-ID"
SG_ID=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text)
```

### Add outbound HTTPS rule if missing
```bash
aws ec2 authorize-security-group-egress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0
```

## VPC Endpoints Setup

### Define variables
```bash
VPC_ID="vpc-YOUR-VPC-ID"
SUBNET_ID="subnet-YOUR-PRIVATE-SUBNET"
REGION="us-east-1"
```

### Create endpoints for each service
```bash
for service in ssm ssmmessages ec2messages; do
    aws ec2 create-vpc-endpoint \
        --vpc-id $VPC_ID \
        --service-name com.amazonaws.$REGION.$service \
        --route-table-ids rtb-YOUR-ROUTE-TABLE \
        --subnet-ids $SUBNET_ID \
        --security-group-ids $SG_ID
done
```

### Don't forget S3 endpoint (gateway type)
```bash
aws ec2 create-vpc-endpoint \
    --vpc-id $VPC_ID \
    --service-name com.amazonaws.$REGION.s3 \
    --route-table-ids rtb-YOUR-ROUTE-TABLE
```

## Command Execution

### Send a simple command
```bash
INSTANCE_ID="i-YOUR-INSTANCE-ID"

COMMAND_ID=$(aws ssm send-command \
    --document-name "AWS-RunPowerShellScript" \
    --targets "Key=instanceids,Values=$INSTANCE_ID" \
    --parameters 'commands=["Write-Host \"Hello from Systems Manager!\"","Get-Date"]' \
    --query 'Command.CommandId' \
    --output text)

echo "Command ID: $COMMAND_ID"
```

### Check command result
```bash
# Wait a few seconds, then check result
sleep 5

aws ssm get-command-invocation \
    --command-id $COMMAND_ID \
    --instance-id $INSTANCE_ID \
    --query '[Status,StandardOutputContent]' \
    --output text
```

## Advanced Command Examples

### Test S3 access through Systems Manager
```bash
INSTANCE_ID="i-YOUR-INSTANCE-ID"

aws ssm send-command \
    --document-name "AWS-RunPowerShellScript" \
    --targets "Key=instanceids,Values=$INSTANCE_ID" \
    --parameters 'commands=[
        "Get-Module -ListAvailable AWS.Tools.S3",
        "Get-S3Bucket | Select-Object -First 5"
    ]'
```

### Check command status
```bash
aws ssm get-command-invocation \
    --command-id $COMMAND_ID \
    --instance-id $INSTANCE_ID \
    --query '[Status,StandardOutputContent]' \
    --output text
```

## Scheduled Commands

### Create a heartbeat association
```bash
aws ssm create-association \
    --name "AWS-RunPowerShellScript" \
    --targets "Key=instanceids,Values=i-YOUR-INSTANCE-ID" \
    --parameters 'commands=["Write-Host \"Heartbeat: $(Get-Date)\""]' \
    --schedule-expression "rate(30 minutes)" \
    --output-location '{
        "S3Location": {
            "OutputS3BucketName": "your-s3-bucket",
            "OutputS3KeyPrefix": "ssm-heartbeat/"
        }
    }'
```

## CloudWatch Integration

### Install CloudWatch agent via Systems Manager
```bash
aws ssm send-command \
    --document-name "AWS-ConfigureAWSPackage" \
    --targets "Key=instanceids,Values=i-YOUR-INSTANCE-ID" \
    --parameters '{
        "action": ["Install"],
        "name": ["AmazonCloudWatchAgent"],
        "version": ["latest"]
    }' \
    --comment "Install CloudWatch Agent"
```

### Check installation status
```bash
aws ssm list-command-invocations \
    --instance-id "i-YOUR-INSTANCE-ID" \
    --details \
    --query 'CommandInvocations[0].Status'
```

### Example CloudWatch agent configuration for Windows

Save this as `cloudwatch-config.json`:

```json
{
    "agent": {
        "metrics_collection_interval": 60
    },
    "logs": {
        "logs_collected": {
            "windows_events": {
                "collect_list": [
                    {
                        "event_name": "Microsoft-Windows-Desired State Configuration/Operational",
                        "event_levels": ["ERROR", "WARNING", "INFORMATION"],
                        "log_group_name": "/aws/systemsmanager/dsc",
                        "log_stream_name": "{instance_id}"
                    },
                    {
                        "event_name": "System",
                        "event_levels": ["ERROR", "WARNING"],
                        "log_group_name": "/aws/systemsmanager/system",
                        "log_stream_name": "{instance_id}"
                    }
                ]
            },
            "files": {
                "collect_list": [
                    {
                        "file_path": "C:\\ProgramData\\Amazon\\SSM\\Logs\\amazon-ssm-agent.log",
                        "log_group_name": "/aws/systemsmanager/ssm-agent",
                        "log_stream_name": "{instance_id}"
                    },
                    {
                        "file_path": "C:\\ProgramData\\Amazon\\SSM\\Logs\\errors.log",
                        "log_group_name": "/aws/systemsmanager/ssm-errors",
                        "log_stream_name": "{instance_id}"
                    }
                ]
            }
        }
    }
}
```

### Store configuration in Parameter Store
```bash
aws ssm put-parameter \
    --name "AmazonCloudWatch-windows-dsc" \
    --type "String" \
    --value file://cloudwatch-config.json \
    --description "CloudWatch config for DSC monitoring"
```

### Apply configuration to instances
```bash
aws ssm send-command \
    --document-name "AmazonCloudWatch-ManageAgent" \
    --targets "Key=instanceids,Values=i-YOUR-INSTANCE-ID" \
    --parameters '{
        "action": ["configure"],
        "mode": ["ec2"],
        "optionalConfigurationSource": ["ssm"],
        "optionalConfigurationLocation": ["AmazonCloudWatch-windows-dsc"],
        "optionalRestart": ["yes"]
    }'
```

## Monitoring and Verification

### List log groups
```bash
aws logs describe-log-groups --log-group-name-prefix "/aws/systemsmanager"
```

### Check for recent log streams
```bash
aws logs describe-log-streams \
    --log-group-name "/aws/systemsmanager/ssm-agent" \
    --order-by LastEventTime \
    --descending \
    --limit 5
```
