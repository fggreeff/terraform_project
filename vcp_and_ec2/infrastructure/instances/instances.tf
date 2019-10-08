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
