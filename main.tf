provider "aws" {
  region  = var.region
  profile = var.profile
}

resource "random_id" "vpc_suffix" {
  byte_length = 4
}
resource "random_id" "igw_suffix" {
  byte_length = 4
}

resource "random_id" "public_subnet_suffix" {
  count       = length(var.public_subnets)
  byte_length = 4
}

resource "random_id" "private_subnet_suffix" {
  count       = length(var.private_subnets)
  byte_length = 4
}

resource "random_id" "public_route_table_suffix" {
  byte_length = 4
}

resource "random_id" "private_route_table_suffix" {
  byte_length = 4
}

resource "aws_vpc" "main_vpc" {
  cidr_block = var.vpc_cidr

  tags = {
    Name = "MainVPC-${random_id.vpc_suffix.hex}"
  }
}

resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "InternetGateway-${random_id.igw_suffix.hex}"
  }
}

resource "aws_subnet" "public_subnets" {
  count                   = length(var.public_subnets)
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = var.public_subnets[count.index].cidr_block
  availability_zone       = var.public_subnets[count.index].az
  map_public_ip_on_launch = true

  tags = {
    Name = "PublicSubnet-${random_id.public_subnet_suffix[count.index].hex}"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = var.private_subnets[count.index].cidr_block
  availability_zone = var.private_subnets[count.index].az

  tags = {
    Name = "PrivateSubnet-${random_id.private_subnet_suffix[count.index].hex}"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "PublicRouteTable-${random_id.public_route_table_suffix.hex}"
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main_igw.id
}

resource "aws_route_table_association" "public_assoc" {
  count          = length(var.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "PrivateRouteTable-${random_id.private_route_table_suffix.hex}"
  }
}

resource "aws_route_table_association" "private_assoc" {
  count          = length(var.private_subnets)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_rt.id
}

# EC2 Setup

resource "aws_security_group" "app_sg" {
  name        = "app-sg"
  description = "Security group for web application instances"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = var.application_port
    to_port     = var.application_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "App-SG"
  }
}

resource "aws_instance" "app_instance" {
  ami                         = var.custom_ami
  instance_type               = var.aws_instance_type
  subnet_id                   = aws_subnet.public_subnets[0].id
  associate_public_ip_address = true
  disable_api_termination     = false
  key_name                    = var.key_pair

  vpc_security_group_ids = [
    aws_security_group.app_sg.id
  ]

  root_block_device {
    volume_size           = 25
    volume_type           = "gp2"
    delete_on_termination = true
  }

  tags = {
    Name = "Webapp-Instance"
  }
}

