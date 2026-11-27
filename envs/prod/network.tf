# VPC du registre public : deux zones, sous-réseaux publics, SANS NAT Gateway.
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "novasphere-${var.environment}"
  cidr = var.vpc_cidr
  azs  = local.azs

  public_subnets          = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, i)]
  map_public_ip_on_launch = true
  enable_nat_gateway      = false
}
