# ─────────────────────────────────────────────────────────────
# Locals
# ─────────────────────────────────────────────────────────────

locals {
  name_prefix = var.project_name
  common_tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}

# ─────────────────────────────────────────────────────────────
# Data Sources
# ─────────────────────────────────────────────────────────────

# Ubuntu 24.04 LTS
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ─────────────────────────────────────────────────────────────
# Network Infrastructure
# ─────────────────────────────────────────────────────────────

resource "aws_vpc" "nt-vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-vpc" }
}

resource "aws_internet_gateway" "nt-igw" {
  vpc_id = aws_vpc.nt-vpc.id
  tags   = { Name = "${var.project_name}-igw" }
}

resource "aws_subnet" "nt-public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.nt-vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${count.index + 1}"
    Tier = "public"
  }
}

# Needed to get AZs dynamically
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_route_table" "nt-public-rt" {
  vpc_id = aws_vpc.nt-vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.nt-igw.id
  }
  tags = { Name = "${var.project_name}-rt-public" }
}

resource "aws_route_table_association" "nt-public-rt-assoc" {
  count          = length(aws_subnet.nt-public)
  subnet_id      = aws_subnet.nt-public[count.index].id
  route_table_id = aws_route_table.nt-public-rt.id
}

# ─────────────────────────────────────────────────────────────
# Security Group
# ─────────────────────────────────────────────────────────────

resource "aws_security_group" "nt-public-sg" {
  name        = "${var.project_name}-public-sg"
  description = "Allow Web, SSH, and Monitoring"
  vpc_id      = aws_vpc.nt-vpc.id 

  ingress {
    description = "HTTP (Nginx)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Grafana"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  ingress {
    description = "Prometheus"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr, "0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-sg" }
}

# ─────────────────────────────────────────────────────────────
# EC2 Instance
# ─────────────────────────────────────────────────────────────

resource "aws_instance" "nt-Server" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.medium" # Heavy stack requires more RAM
  key_name                    = var.key_name
  subnet_id                   = aws_subnet.nt-public[0].id 
  vpc_security_group_ids      = [aws_security_group.nt-public-sg.id]
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/scripts/server_userdata.sh", {
    project_name       = var.project_name
    db_endpoint        = "127.0.0.1"
    db_port            = var.db_port
    db_name            = var.db_name
    db_username        = var.db_username
    db_password        = var.db_password
  })

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 50 # Larger disk for logs/metrics
    delete_on_termination = true
    encrypted             = true
  }
  
  lifecycle { create_before_destroy = true }
  tags = { Name = "${var.project_name}-server", Role = "fullstack-native" }
}