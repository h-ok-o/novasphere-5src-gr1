variable "aws_region" {
  description = "Region AWS de deploiement"
  type        = string
  default     = "us-east-1"
}

variable "owner" {
  description = "Trigramme de l'etudiant, utilise pour nommer et tagger les ressources"
  type        = string

  validation {
    condition     = can(regex("^[a-z]{3}$", var.owner))
    error_message = "Le trigramme doit etre compose de 3 lettres minuscules."
  }
}

variable "instance_type" {
  description = "Type d'instance EC2"
  type        = string
  default     = "t3.micro"
}

variable "environment" {
  description = "dev ou prod"
  type        = string

  validation {
    condition     = var.environment == "prod"
    error_message = "Dans envs/prod, environment doit valoir prod."
  }
}


variable "generate_inventory" {
  description = "Genere l'inventaire Ansible local (false en CI)"
  type        = bool
  default     = true
}

variable "instance_profile_name" {
  description = "Profil d'instance des serveurs web. Learner Lab : LabInstanceProfile, precree (creation de roles IAM refusee)."
  type        = string
  default     = "LabInstanceProfile"
}

variable "vpc_cidr" {
  description = "CIDR du VPC de l'environnement"
  type        = string
  default     = "10.1.0.0/16"
}

variable "db_password" {
  description = "Mot de passe applicatif reçu uniquement à l'apply via TF_VAR_db_password."
  type        = string
  sensitive   = true
  ephemeral   = true

  validation {
    condition     = length(var.db_password) >= 16
    error_message = "Le mot de passe applicatif doit contenir au moins 16 caractères."
  }
}

variable "db_password_version" {
  description = "Compteur à incrémenter à chaque rotation du secret (DB_PASSWORD_VERSION)."
  type        = number
  default     = 1

  validation {
    condition     = var.db_password_version >= 1 && floor(var.db_password_version) == var.db_password_version
    error_message = "db_password_version doit être un entier positif."
  }
}
