# Generate an SSH key pair
resource "tls_private_key" "main_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Store the private key locally
resource "local_file" "private_key_pem" {
  content         = tls_private_key.main_key.private_key_pem
  filename        = "${path.module}/startup_key.pem"
  file_permission = "0400"
}

# Register the public key in AWS
resource "aws_key_pair" "deployer_key" {
  key_name   = "startup-key"
  public_key = tls_private_key.main_key.public_key_openssh
}

# Create Custom VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "StartupVPC" }
}

# Internet Gateway for public access
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "Main-IGW" }
}

# Public Subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "eu-central-1a"
  tags                    = { Name = "PublicSubnet" }
}

# Private Subnet
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-central-1a"
  tags              = { Name = "PrivateSubnet" }
}

# Public Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

# Associate Public Route Table
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

# Public Security Group (SSH & HTTP)
resource "aws_security_group" "public_sg" {
  name   = "public_sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Open SSH for access
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Private Security Group (SSH only from Public SG)
resource "aws_security_group" "private_sg" {
  name   = "private_sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.public_sg.id] # Tightly controlled
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Use an Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Public Instance
resource "aws_instance" "public_ec2" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public.id
  key_name               = aws_key_pair.deployer_key.key_name
  vpc_security_group_ids = [aws_security_group.public_sg.id]
  tags                   = { Name = "Public-EC2" }
}

# Bastion Host (Assignment lists these as separate, so we make a 2nd public one)
resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public.id
  key_name               = aws_key_pair.deployer_key.key_name
  vpc_security_group_ids = [aws_security_group.public_sg.id]
  tags                   = { Name = "Bastion-Host" }
}

# Private Instance
resource "aws_instance" "private_ec2" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private.id
  key_name               = aws_key_pair.deployer_key.key_name
  vpc_security_group_ids = [aws_security_group.private_sg.id]
  tags                   = { Name = "Private-EC2" }
}

# OUTPUTS
output "public_ip" { value = aws_instance.public_ec2.public_ip }
output "bastion_ip" { value = aws_instance.bastion.public_ip }
output "private_internal_ip" { value = aws_instance.private_ec2.private_ip }
output "key_path" { value = local_file.private_key_pem.filename }