# AMI Amazon Linux 2023 standard (la variante "minimal" n'a pas l'agent SSM).
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

locals {
  # Un secret par environnement : /novasphere/dev/... ou /novasphere/prod/...
  # Le secret est stocké dans Parameter Store par secrets.tf.
  secret_path = "/novasphere/${var.environment}/db_password"
}

module "web" {
  source = "../../modules/ec2-server"

  environment           = var.environment
  vpc_id                = module.vpc.vpc_id
  subnet_ids            = module.vpc.public_subnets
  ami_id                = data.aws_ami.al2023.id
  root_device_name      = data.aws_ami.al2023.root_device_name
  aws_region            = var.aws_region
  instance_type         = var.instance_type
  instance_profile_name = var.instance_profile_name
  secret_parameter_path = local.secret_path
  secret_version        = var.db_password_version

  depends_on = [aws_ssm_parameter.db_password]
}
