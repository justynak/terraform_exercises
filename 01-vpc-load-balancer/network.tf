# --- VPC ---------------------------------------------------------------

resource "aws_vpc" "app_vpc" {
  cidr_block           = local.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "app-vpc" # will pop up in AWS console
  }
}

# --- Subnets -----------------------------------------------------------

resource "aws_subnet" "public_a_subnet" {
  vpc_id                  = aws_vpc.app_vpc.id
  cidr_block              = local.public_subnet_cidrs.a
  availability_zone       = local.availability_zone_a
  map_public_ip_on_launch = true

  tags = {
    Name = "public-a-subnet"
  }
}

resource "aws_subnet" "public_b_subnet" {
  vpc_id                  = aws_vpc.app_vpc.id
  cidr_block              = local.public_subnet_cidrs.b
  availability_zone       = local.availability_zone_b
  map_public_ip_on_launch = true

  tags = {
    Name = "public-b-subnet"
  }
}

resource "aws_subnet" "private_a_subnet" {
  vpc_id            = aws_vpc.app_vpc.id
  cidr_block        = local.private_subnet_cidrs.a
  availability_zone = local.availability_zone_a

  tags = {
    Name = "private-a-subnet"
  }
}

resource "aws_subnet" "private_b_subnet" {
  vpc_id            = aws_vpc.app_vpc.id
  cidr_block        = local.private_subnet_cidrs.b
  availability_zone = local.availability_zone_b

  tags = {
    Name = "private-b-subnet"
  }
}

# --- Internet Gateway & public routing ---------------------------------

resource "aws_internet_gateway" "app_igw" {
  vpc_id = aws_vpc.app_vpc.id

  tags = {
    Name = "app-igw"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.app_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.app_igw.id
  }

  tags = { Name = "public_rt" }
}

resource "aws_route_table_association" "public_a_rt_association" {
  subnet_id      = aws_subnet.public_a_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_b_rt_association" {
  subnet_id      = aws_subnet.public_b_subnet.id
  route_table_id = aws_route_table.public_rt.id
}
