# Central place for all network address ranges and zones.
# Keeping CIDRs here means there is a single source of truth and less chance
# of typos when referencing them across subnets/routes.
locals {
  vpc_cidr = "10.10.0.0/16"

  availability_zone_a = "eu-central-1a"
  availability_zone_b = "eu-central-1b"

  public_subnet_cidrs = {
    a = "10.10.1.0/24"
    b = "10.10.2.0/24"
  }

  private_subnet_cidrs = {
    a = "10.10.11.0/24"
    b = "10.10.12.0/24"
  }
}
