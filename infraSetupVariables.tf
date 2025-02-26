variable "region" {
  description = "AWS Region"
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
}

variable "public_subnets" {
  description = "List of public subnet CIDR blocks and availability zones"
  type = list(object({
    cidr_block = string
    az         = string
  }))
}

variable "private_subnets" {
  description = "List of private subnet CIDR blocks and availability zones"
  type = list(object({
    cidr_block = string
    az         = string
  }))
}

variable "custom_ami" {
  type        = string
  description = "The custom AMI ID to use for the EC2 instance"
}

variable "application_port" {
  type        = number
  description = "The TCP port on which the application listens"
}

variable "key_pair" {
  description = "The name of the key pair to use for SSH access"
  type        = string
}

variable "aws_instance_type" {
  description = "AWS instance type"
  type        = string
}
