
# Terraform AWS VPC Setup

## Table of Contents

- [Getting Started](#getting-started)
- [Prerequisites](#prerequisites)
- [Commands to Run](#commands-to-run)

## Getting Started

To get started with this Terraform configuration, you need to have Terraform installed on your machine. Follow the steps below to set up and deploy the infrastructure.

## Prerequisites

1. **Terraform**: Ensure you have Terraform installed. You can download it from the [official Terraform website](https://www.terraform.io/downloads.html).
2. **AWS CLI**: Install the AWS CLI and configure it with your credentials. You can follow the [AWS CLI installation guide](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html).
3. **AWS Account**: You need an AWS account with the necessary permissions to create VPCs, subnets, route tables, and other related resources.

## Commands to Run

1. **Initialize Terraform**: Initializes the working directory and downloads the necessary provider plugins.

   ```bash
   terraform init
   ```

2. **Plan the Infrastructure**: Shows an execution plan of what Terraform will do when you apply the configuration.

   ```bash
   terraform plan
   ```

3. **Apply the Configuration**: Applies the changes required to reach the desired state of the configuration. You will be prompted to confirm the action by typing `yes`.

   ```bash
   terraform apply
   ```

4. **Destroy the Infrastructure**: Destroys the infrastructure created by Terraform. You will be prompted to confirm the action by typing `yes`.

   ```bash
   terraform destroy
   ```




