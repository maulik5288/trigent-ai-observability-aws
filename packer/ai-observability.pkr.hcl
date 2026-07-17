packer {
  required_plugins {
    amazon = {
      version = ">= 1.3.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "region" {
  type        = string
  default     = "us-east-1" # AWS Marketplace requires the product AMI here
}

variable "instance_type" {
  type    = string
  default = "t3.large"
}

variable "ami_name_prefix" {
  type    = string
  default = "trigent-ai-observability-stack"
}

variable "product_version" {
  type    = string
  default = "1.0.0"
}

source "amazon-ebs" "ubuntu" {
  region        = var.region
  instance_type = var.instance_type
  ssh_username  = "ubuntu"

  # Marketplace naming convention: [Seller] [Product] [Version]
  ami_name        = "${var.ami_name_prefix}-${var.product_version}-{{timestamp}}"
  ami_description = "Trigent AI Observability Stack ${var.product_version}: Langfuse v3 tracing + LLM cost dashboards (Grafana/ClickHouse) + automated eval hooks. Secrets generated at first boot."

  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
      virtualization-type = "hvm"
      root-device-type    = "ebs"
    }
    owners      = ["099720109477"] # Canonical
    most_recent = true
  }

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 60
    volume_type           = "gp3"
    delete_on_termination = true
    # NOTE: no 'encrypted = true' - AWS Marketplace requires the product AMI
    # snapshot to be unencrypted; buyers encrypt at launch (our CFN/TF do).
  }

  # Remove Packer's temporary key from authorized_keys after provisioning
  # (Marketplace: AMIs must not contain authorized public keys).
  ssh_clear_authorized_keys = true

  # IMDSv2 on the build instance
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tags = {
    Name           = "${var.ami_name_prefix}-${var.product_version}"
    Project        = "ai-observability-marketplace"
    ProductVersion = var.product_version
    BaseAMI        = "{{ .SourceAMI }}"
  }
}

build {
  name    = "ai-observability-ami"
  sources = ["source.amazon-ebs.ubuntu"]

  provisioner "file" {
    source      = "scripts/firstboot.sh"
    destination = "/tmp/firstboot.sh"
  }

  provisioner "shell" {
    execute_command = "sudo -E bash '{{ .Path }}'"
    script          = "scripts/install-stack.sh"
  }

  post-processor "manifest" {
    output     = "build-manifest.json"
    strip_path = true
  }
}
