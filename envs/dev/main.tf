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
  # Le secret lui-même est écrit par secrets.tf (partie de Soratha).
  secret_path = "/novasphere/${var.environment}/calendar-api-key"
}

module "web" {
  # TODO(Julien): remplacer par le repo/tag du module web
  source = "../module"

  environment           = var.environment
  vpc_id                = module.vpc.vpc_id
  subnet_ids            = module.vpc.public_subnets
  ami_id                = data.aws_ami.al2023.id
  instance_type         = var.instance_type
  instance_profile_name = var.instance_profile_name
  secret_parameter_path = local.secret_path

  # A activer quand secrets.tf existe : le secret doit exister avant
  # que les instances démarrent.
  # depends_on = [aws_ssm_parameter.app_secret]
}