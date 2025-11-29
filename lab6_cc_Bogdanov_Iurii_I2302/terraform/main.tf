terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  required_version = ">= 1.5.0"
}

provider "aws" {
  region = var.aws_region
}

# Доступные зоны (чтобы разбросать подсети по разным AZ)
data "aws_availability_zones" "available" {
  state = "available"
}

# Ищем последнюю Amazon Linux 2 AMI (x86_64, gp2)
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ========== VPC ==========
resource "aws_vpc" "lab6_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "lab6-vpc"
    Lab  = "cloud-computing-6"
  }
}

# ========== Internet Gateway ==========
resource "aws_internet_gateway" "lab6_igw" {
  vpc_id = aws_vpc.lab6_vpc.id

  tags = {
    Name = "lab6-igw"
  }
}

# ========== Публичные подсети ==========
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.lab6_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "lab6-public-1"
    Type = "public"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.lab6_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "lab6-public-2"
    Type = "public"
  }
}

# ========== Приватные подсети (для Auto Scaling позже) ==========
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.lab6_vpc.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "lab6-private-1"
    Type = "private"
  }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.lab6_vpc.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "lab6-private-2"
    Type = "private"
  }
}

# ========== Route table для публичных подсетей ==========
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab6_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab6_igw.id
  }

  tags = {
    Name = "lab6-public-rt"
  }
}

resource "aws_route_table_association" "public_1_assoc" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2_assoc" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# ========== Security Group для веб-сервера ==========
resource "aws_security_group" "web_sg" {
  name        = "lab6-web-sg"
  description = "Allow HTTP and SSH"
  vpc_id      = aws_vpc.lab6_vpc.id

  # SSH — по-хорошему тут должен быть твой IP, но для удобства сейчас 0.0.0.0/0
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP для всех
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "lab6-web-sg"
  }
}

# ========== EC2: Amazon Linux 2 + init.sh ==========
resource "aws_instance" "web_server" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  associate_public_ip_address = true
  monitoring                  = true # Detailed CloudWatch monitoring (Enable)

  key_name = "lab6-key"

  # UserData — скрипт init.sh, который тебе дал препод
  user_data = file("${path.module}/init.sh")
  user_data_replace_on_change = true
  tags = {
    Name = "lab6-web-ec2"
    Role = "web"
  }
}
