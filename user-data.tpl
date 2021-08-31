#!/bin/bash
echo ECS_CLUSTER=${cluster_name} >> /etc/ecs/ecs.config
echo ECS_ENABLE_CONTAINER_METADATA=true >> /etc/ecs/ecs.config

# Get the current region from the instance metadata
#region=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)

# Install the SSM agent RPM
#yum install -y https://amazon-ssm-$region.s3.amazonaws.com/latest/linux_amd64/amazon-ssm-agent.rpm
