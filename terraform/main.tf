terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# ─── VPC ───────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "devops-intern-vpc" }
}

# ─── SUBNETS ───────────────────────────────────────────
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true
  tags = { Name = "devops-intern-public" }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.region}a"
  tags = { Name = "devops-intern-private" }
}

# ─── INTERNET GATEWAY ──────────────────────────────────
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "devops-intern-igw" }
}

# ─── NAT GATEWAY (lets private VMs reach internet) ─────
resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  tags          = { Name = "devops-intern-nat" }
}

# ─── ROUTE TABLES ──────────────────────────────────────
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "public-rt" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "private-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# ─── SECURITY GROUP: API Gateway (public) ──────────────
resource "aws_security_group" "api_gateway" {
  name        = "api-gateway-sg"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP API"
    from_port   = 3111
    to_port     = 3111
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "api-gateway-sg" }
}

# ─── SECURITY GROUP: Workers (private) ─────────────────
resource "aws_security_group" "workers" {
  name   = "workers-sg"
  vpc_id = aws_vpc.main.id

  # iii engine WebSocket from gateway only
  ingress {
    from_port       = 49134
    to_port         = 49134
    protocol        = "tcp"
    security_groups = [aws_security_group.api_gateway.id]
  }

  # SSH from gateway only (bastion pattern)
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.api_gateway.id]
  }

  # Inter-worker communication
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "workers-sg" }
}

# ─── EC2: API Gateway VM (public) ──────────────────────
resource "aws_instance" "api_gateway" {
  ami                    = var.ami_id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.api_gateway.id]
  key_name               = var.key_name

  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y nodejs npm git
    curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
    echo 'export PATH="/home/ubuntu/.local/bin:$PATH"' >> /home/ubuntu/.bashrc
  EOF
  )

  tags = { Name = "api-gateway", Role = "gateway" }
}

# ─── EC2: Inference Worker (private) ───────────────────
resource "aws_instance" "inference_worker" {
  ami                    = var.ami_id
  instance_type          = var.worker_instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.workers.id]
  key_name               = var.key_name

  root_block_device {
    volume_size = 20
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y python3 python3-pip python3-venv git
    curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
    echo 'export PATH="/home/ubuntu/.local/bin:$PATH"' >> /home/ubuntu/.bashrc
  EOF
  )

  tags = { Name = "inference-worker", Role = "worker" }
}

# ─── EC2: Caller Worker (private) ──────────────────────
resource "aws_instance" "caller_worker" {
  ami                    = var.ami_id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.workers.id]
  key_name               = var.key_name

  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y nodejs npm git
    curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
    echo 'export PATH="/home/ubuntu/.local/bin:$PATH"' >> /home/ubuntu/.bashrc
  EOF
  )

  tags = { Name = "caller-worker", Role = "worker" }
}
