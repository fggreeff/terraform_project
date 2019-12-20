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
    "Version" : "2019-12-24",
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

resource "aws_iam_role_policy" "ec2_iam_role_policy" {
  name = "EC2-IAM-Policy"
  role = "${aws_iam_role.ec2_iam_role.id}"
  policy = <<EOF
{
    "Version" : "2019-12-24",
        "Statement": 
    [
         {
            "Effect" : "Allow",
            "Action" : [
                "ec2:*", 
                "elasticloadbalancing:*",
                "cloudwatch:*",
                "logs:*"
             ],
             "Resource":"*" 
         }
    ]
}
EOF
}

# Instances that are launched with this instance profile, will have the above role & role policy
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "EC2-IAM-Instance-Profile"
  role = "${aws_iam_role.ec2_iam_role.name}"
}

# Read latest ami from aws
data "aws_ami" "launch_configuration_ami" {
    most_recent = true
    filter {
        name   = "owner-alias"
        values = ["amazon"]
    }
}

resource "aws_launch_configuration" "ec2_private_launch_configuration" {
    image_id                    = "${data.aws_ami.launch_configuration_ami.id}"
    instance_type               = "${var.ec2_instance_type}"
    key_name                    = "${var.key_pair_name}"
    associate_public_ip_address = false
    iam_instance_profile        = "${aws_iam_instance_profile.ec2_instance_profile.name}"
    security_groups             = ["${aws_security_group.ec2_private_security_group.id}"]
  
  user_data = <<EOF
    #!/bin/bash
    yum update -y 
    yum install httpd24 -y
    service httpd start
    chkconfig httpd on
    export INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/instance-id)
    echo "<html><body><h1>Hello from Prod backend at intance <b>"$INSTANCE_ID"</b></h1></body></html>" > /var/www/html/index.html
  EOF
}

resource "aws_launch_configuration" "ec2_public_launch_configuration" {
    image_id = "${data.aws_ami.launch_configuration_ami.id}"
    instance_type = "${var.ec2_instance_type}"
    key_name = "${var.key_pair_name}"
    associate_public_ip_address = true
    iam_instance_profile = "${aws_iam_instance_profile.ec2_instance_profile.name}"
    security_groups = ["${aws_security_group.ec2_public_security_group.id}"]

  user_data = <<EOF
    #!/bin/bash
    yum update -y 
    yum install httpd24 -y
    service httpd start
    chkconfig httpd on
    export INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/instance-id)
    echo "<html><body><h1>Hello from Production Web App at intance <b>"$INSTANCE_ID"</b></h1></body></html>" > /var/www/html/index.html
  EOF
}

# Public Load balancer in front of ASG
resource "aws_elb" "webapp_load_balancer" {
  name        = "Production-WebApp-LoadBalancer"
  internal    = false
  security_groups = ["${aws_security_group.elb_security_group.id}"]
  subnets = [
    "${data.terraform_remote_state.network_configuration.public_subnet_1_cidr}",
    "${data.terraform_remote_state.network_configuration.public_subnet_2_cidr}",
    "${data.terraform_remote_state.network_configuration.public_subnet_3_cidr}"]

  "listener" {
    instance_port = 80
    instance_protocol = "HTTP"
    lb_port = 80
    lb_protocol = "HTTP"
  }
  health_check {
    healthy_threshold = 5
    internal = 30
    target = "HTTP:80/index.html"
    timeout = 10
    unhealthy_threshold = 5
  }
}

# Backend / private load balancer
resource "aws_elb" "backend_load_balancer" {
  name        = "Production-Backend-LoadBalancer"
  internal    = true
  security_groups = ["${aws_security_group.elb_security_group.id}"]
  subnets = [
    "${data.terraform_remote_state.network_configuration.private_subnet_1_cidr}",
    "${data.terraform_remote_state.network_configuration.private_subnet_2_cidr}",
    "${data.terraform_remote_state.network_configuration.private_subnet_3_cidr}"]


  "listener" {
    instance_port = 80
    instance_protocol = "HTTP"
    lb_port = 80
    lb_protocol = "HTTP"
  }

    health_check {
    healthy_threshold = 5
    internal = 30
    target = "HTTP:80/index.html"
    timeout = 10
    unhealthy_threshold = 5
  }
}

# private EC2 ASG
resource "aws_autoscaling_group" "ec2_private_autoscaling_group" {
  name = "Production-Backend-AutoScalingGroup"
  vpc_zone_identifier = [
    "${data.terraform_remote_state.network_configuration.private_subnet_1_cidr}",
    "${data.terraform_remote_state.network_configuration.private_subnet_2_cidr}",
    "${data.terraform_remote_state.network_configuration.private_subnet_3_cidr}"
  ]
  max_size = "${var.max_instance_size}"
  min_size = "${var.min_instance_size}"
  launch_configuration = "${aws_launch_configuration.ec2_private_launch_configuration.name}"
  health_check_type = "ELB"
  load_balancers = ["${aws_elb.backend_load_balancer.name}"]

  tag {
    key = "Name"
    propagate_at_launch = false
    value = "Backend-EC2-Instance"
  }
  tag {
    key = "Type"
    propagate_at_launch = false
    value = "Backend"
  }
}

# public EC2 ASG
resource "aws_autoscaling_group" "ec2_public_autoscaling_group" {
  name = "Production-WebApp-AutoScalingGroup"
  vpc_zone_identifier = [
    "${data.terraform_remote_state.network_configuration.public_subnet_1_cidr}",
    "${data.terraform_remote_state.network_configuration.public_subnet_2_cidr}",
    "${data.terraform_remote_state.network_configuration.public_subnet_3_cidr}"
  ]
  max_size = "${var.max_instance_size}"
  min_size = "${var.min_instance_size}"
  launch_configuration = "${aws_launch_configuration.ec2_public_launch_configuration.name}"
  health_check_type = "ELB"
  load_balancers = ["${aws_elb.webapp_load_balancer.name}"]

  tag {
    key = "Name"
    propagate_at_launch = false
    value = "WebApp-EC2-Instance"
  }
  tag {
    key = "Type"
    propagate_at_launch = false
    value = "WebApp"
  }
}

resource "aws_autoscaling_policy" "webapp_production_scaling_policy" {
  autoscaling_group_name="${aws_autoscaling_group.ec2_public_autoscaling_group.name}"
  name="Production-Webapp-Autoscaling-Policy"
  policy_type="TargetTrackingPolicy"
  min_adjustment_magnitude=1
  
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type="ASGAverageCPUUtilizarion"
    }
target_value=80.0 # if it hits 80 cpu usage, it will scale up
  }
}

resource "aws_autoscaling_policy" "backend_production_scaling_policy" {
  autoscaling_group_name="${aws_autoscaling_group.ec2_private_autoscaling_group.name}"
  name="Production-Backend-Autoscaling-Policy"
  policy_type="TargetTrackingPolicy"
  min_adjustment_magnitude=1
  
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type="ASGAverageCPUUtilizarion"
    }
target_value=80.0 # if it hits 80 cpu usage, it will scale up
  }
}

# keep track of autoscaling/traffic and be notified
resource "aws_sns_topic" "webapp_production_autoscaling_alert_topic" {
  display_name="Webapp_Autoscaling_Topic"
  name="Webapp_Autoscaling_Topic"
}

# subscribe to topic to get notified (sms subscription)
resource "aws_sns_topic_subscription" "webapp_production_autoscaling_sns_subscription" {
  endpoint="+447450000000"
  protocol="sms"
  topic_arn="${aws_sns_topic.webapp_production_autoscaling_alert_topic.arn}"
}