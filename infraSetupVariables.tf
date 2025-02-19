variable "region" {
  description = "AWS Region"
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  description = "List of public subnet CIDR blocks and availability zones"
  type        = list(object({
    cidr_block = string
    az         = string
  }))
  default = [
    { cidr_block = "10.0.1.0/24", az = "us-east-1a" },
    { cidr_block = "10.0.2.0/24", az = "us-east-1b" },
    { cidr_block = "10.0.3.0/24", az = "us-east-1c" }
  ]
}

variable "private_subnets" {
  description = "List of private subnet CIDR blocks and availability zones"
  type        = list(object({
    cidr_block = string
    az         = string
  }))
  default = [
    { cidr_block = "10.0.4.0/24", az = "us-east-1a" },
    { cidr_block = "10.0.5.0/24", az = "us-east-1b" },
    { cidr_block = "10.0.6.0/24", az = "us-east-1c" }
  ]
}
