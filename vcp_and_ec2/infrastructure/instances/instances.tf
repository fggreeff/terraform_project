provider "aws" {
  region = "${var.region}"
}

terraform {
  backend "s3" {}
}

# read outputs from prev layer of infrastructure
# read the remote state config, we make use of subnet ids, vpc cidr blocks
data "terraform_remote_state" "network_configuration" {
  backend = "s3"

  config {
    bucket = "${var.remote_state_bucket}"
    key    = "${var.remote_state_key}"
    region = "${var.region}"
  }
}

resource "aws_security_group" "ec2_public_security_group" {
  name        = "EC2-Public-SG"
  description = "Internet reaching access for EC2 Instances"
  vpc_id      = "${data.terraform_remote_state.network_configuration.vpc_id}"


  ingress {
    from_port   = 80
    protocol    = "TCP"
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }
  # ssh access
  ingress {
    from_port   = 22
    protocol    = "TCP"
    to_port     = 22
    cidr_blocks = ["82.13.115.86/32"] #whatismyip
  }
  # allow to output traffic from EC2
  egress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"] # allow output traffic to everywhere
  }
}

resource "aws_security_group" "ec2_private_security_group" {
  name        = "EC2-Private-SG"
  description = "Only allow public SG resources to access these instances"
  vpc_id      = "${data.terraform_remote_state.network_configuration.vpc_id}"

  # allow ingress traffic from pub security group
  ingress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["${aws_security_group.ec2_public_security_group.id}"]
  }

  ingress {
    from_port   = 80
    protocol    = "TCP"
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow health checking for instances using this SG"
  }

  egress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"] # allow output traffic to everywhere
  }
}

resource "aws_security_group" "elb_security_group" {
  name        = "ELB-SG"
  description = "ELB Security Group"
  vpc_id      = "${data.terraform_remote_state.network_configuration.vpc_id}"

  # internet facing loadbalancer
  ingress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    description = "Allow wen traffic to load balancer"
  }
  egress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "ec2_iam_role" {
  name               = "EC2-IAM-Role"
  assume_role_policy = <<EOF
{
    "Version" : "2019-11-10",
    "Statement": 
    [
        {
            "Effect" : "Allow",
            "Principal" : {
                "Service" : ["ec2.amazonaws.com", "application-autoscaling.amazonaws.com"]
            },
            "Action" : "sts:AssumeRole"
        }
    ]
}
  EOF
}
