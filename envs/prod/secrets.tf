resource "aws_ssm_parameter" "db_password" {
  name        = local.secret_path
  description = "Mot de passe applicatif NovaSphere pour ${var.environment}."
  type        = "SecureString"
  key_id      = "alias/aws/ssm"

  value_wo         = var.db_password
  value_wo_version = var.db_password_version

  tags = {
    Name        = "novasphere-${var.environment}-db-password"
    Environment = var.environment
  }
}
