variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI named profile"
  type        = string
  default     = "Fatin"
}

variable "project_name" {
  description = "Prefix applied to all resource names"
  type        = string
  default     = "nt"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "allowed_ssh_cidr" {
  description = "Your machine IP in CIDR form"
  type        = string
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "key_name" {
  description = "Name of existing EC2 key pair"
  type        = string
  default     = "instance_prac_pem"
}

variable "root_volume_size" {
  type    = number
  default = 40
}

# ─────────────────────────────────────────────────────────────
# Database Variables
# ─────────────────────────────────────────────────────────────

variable "db_name" {
  type    = string
  default = "teamdb"
}

variable "db_username" {
  type      = string
  default   = "nt_admin"
  sensitive = true
}

variable "db_password" {
  description = "Password for the DB"
  type        = string
  sensitive   = true
}

variable "db_port" {
  type    = number
  default = 3306
}