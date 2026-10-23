##########################
##### VPC and subnets
##########################
resource "aws_vpc" "main_vpc" {
  cidr_block           = local.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "main-vpc" }
}

resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = local.public_subnet_cidrs.a
  availability_zone       = local.availability_zone_a
  map_public_ip_on_launch = true
  tags                    = { Name = "public-subnet-a" }
}

resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = local.private_subnet_cidrs.a
  availability_zone = local.availability_zone_a
  tags              = { Name = "private-subnet-a" }
}

##########################
##### Routing
#########################
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main_vpc.id
  # no route blocks, the implicit "local" route exists
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private_subnet_a.id
  route_table_id = aws_route_table.private.id
}


#########################
##### Endpoints
#########################
resource "aws_vpc_endpoint" "ecr" {
  for_each = toset(["ecr.api", "ecr.dkr"])

  vpc_id              = aws_vpc.main_vpc.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.key}"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.ecr_endpoint_sg.id]
  subnet_ids          = [aws_subnet.private_subnet_a.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main_vpc.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
}

# CloudWatch Logs interface endpoint so the EC2 can push container logs
# without any internet egress. Reuses the ECR endpoint SG (443 from app-server).
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.main_vpc.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.logs"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.ecr_endpoint_sg.id]
  subnet_ids          = [aws_subnet.private_subnet_a.id]
  private_dns_enabled = true

  tags = { Name = "logs-endpoint" }
}

# SSM endpoints so the AMI's built-in SSM agent stops reaching for the
# public internet (and so you can shell in via Session Manager, no ingress).
resource "aws_vpc_endpoint" "ssm" {
  for_each = toset(["ssm", "ssmmessages", "ec2messages"])

  vpc_id              = aws_vpc.main_vpc.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.key}"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.ecr_endpoint_sg.id]
  subnet_ids          = [aws_subnet.private_subnet_a.id]
  private_dns_enabled = true

  tags = { Name = "${each.key}-endpoint" }
}

