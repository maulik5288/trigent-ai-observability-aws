variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Name prefix for resources"
  type        = string
  default     = "ai-observability-test"
}

variable "instance_type" {
  description = "EC2 instance type. t3.large (8 GB RAM) is the practical minimum for ClickHouse + Langfuse + Grafana."
  type        = string
  default     = "t3.large"
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 60
}

variable "key_name" {
  description = "Name of an existing EC2 key pair for SSH (needed to read generated credentials). Set to null to disable SSH."
  type        = string
  default     = null
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to reach SSH/Langfuse/Grafana. Set this to <your-public-ip>/32 — do NOT leave open to the world."
  type        = list(string)
}
