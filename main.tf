provider "aws" {
  region  = var.region
  profile = "demo-login"
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
  cidr_block              =    var.public_subnets[count.index].cidr_block
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
