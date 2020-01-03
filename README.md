# terraform_project
VPC solution with EC2 for production AWS with terraform

## High Level Architecture
![Architecture](architecture/aws_tf.png)

## Getting started
- cd `../infrastructure` dir
- Initialise backend config
```terraform init backend-config="infrastructure-prod.config"```
- Run `terraform plan -var-file="production.tfvars" ` to see
any changes that are required for your infrastructure.
- Apply the infrastructure changes `terraform apply -var-file="production.tfvars"`

*Follow same instructions for the `intances` dir:
- cd `../instances` dir
- Initialise backend config
```terraform init backend-config="backend-prod.config"```
- Run `terraform plan -var-file="production.tfvars" ` to see
any changes that are required for your infrastructure.
- Apply the infrastructure changes `terraform apply -var-file="production.tfvars"`


## Destroy infrastructure
- cd `../infrastructure` dir
- Infrastructure managed by Terraform will be destroyed when you run `terraform destroy -var-file="production.tfvars" `

## Prerequisites
These steps should be familiar if you're familiar with AWS & terraform.

- Create an AWS account
- Setup IAM user
- Create keypair
- Setup S3 bucket for the TF scripts

- Install aws-cli
- Install terraform 

## Source
[VPC-with-EC2](https://www.udemy.com/vpc-solutions-with-ec2-for-production-aws-with-terraform/)

[aws-architecture](https://github.com/neocorp/aws_vpc_ec2)
