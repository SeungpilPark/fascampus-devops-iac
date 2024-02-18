provider "aws" {
  region = var.region
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "ubuntu" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  tags = {
    Name = var.instance_name
  }
}

#module "vpc" {
#  source  = "terraform-aws-modules/vpc/aws"
#  version = "5.5.1"
#}

#import {
#  # ID of the cloud resource
#  # Check provider documentation for importable resources and format
#  id = "vpc-0b1f19c4f16ef55a5"
#  # Resource address
#  to = aws_vpc.this
#}