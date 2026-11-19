########################################
# VPC
########################################

resource "aws_vpc" "x_projectBKN_vpc" {
  cidr_block           = "172.16.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "x-projectBKN-vpc"
  }
}

########################################
# Subnets
########################################

resource "aws_subnet" "x_projectBKN_public_subnet" {
  vpc_id                  = aws_vpc.x_projectBKN_vpc.id
  cidr_block              = "172.16.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "x-projectBKN-public-subnet"
  }
}

resource "aws_subnet" "x_projectBKN_private_subnet" {
  vpc_id     = aws_vpc.x_projectBKN_vpc.id
  cidr_block = "172.16.2.0/24"

  tags = {
    Name = "x-projectBKN-private-subnet"
  }
}

########################################
# Internet Gateway
########################################

resource "aws_internet_gateway" "x_projectBKN_igw" {
  vpc_id = aws_vpc.x_projectBKN_vpc.id

  tags = {
    Name = "x-projectBKN-igw"
  }
}

########################################
# NAT Gateway (private subnet outbound for Streamer apt)
########################################

resource "aws_eip" "x_projectBKN_nat" {
  domain = "vpc"

  tags = {
    Name = "x-projectBKN-nat-eip"
  }
}

resource "aws_nat_gateway" "x_projectBKN_nat" {
  allocation_id = aws_eip.x_projectBKN_nat.id
  subnet_id     = aws_subnet.x_projectBKN_public_subnet.id

  tags = {
    Name = "x-projectBKN-nat"
  }

  depends_on = [aws_internet_gateway.x_projectBKN_igw]
}

########################################
# Route Tables
########################################

resource "aws_route_table" "x_projectBKN_public_rt" {
  vpc_id = aws_vpc.x_projectBKN_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.x_projectBKN_igw.id
  }

  tags = {
    Name = "x-projectBKN-public-rt"
  }
}

resource "aws_route_table" "x_projectBKN_private_rt" {
  vpc_id = aws_vpc.x_projectBKN_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.x_projectBKN_nat.id
  }

  tags = {
    Name = "x-projectBKN-private-rt"
  }
}

########################################
# Route Table Associations
########################################

resource "aws_route_table_association" "x_projectBKN_public_assoc" {
  subnet_id      = aws_subnet.x_projectBKN_public_subnet.id
  route_table_id = aws_route_table.x_projectBKN_public_rt.id
}

resource "aws_route_table_association" "x_projectBKN_private_assoc" {
  subnet_id      = aws_subnet.x_projectBKN_private_subnet.id
  route_table_id = aws_route_table.x_projectBKN_private_rt.id
}

########################################
# Security Groups
########################################

resource "aws_security_group" "x_projectBKN_web_sg" {
  vpc_id = aws_vpc.x_projectBKN_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP redirect to HTTPS (certificates use DNS-01 via Route53)"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.admin_ssh_cidr_blocks
    description = "SSH bastion access for team Ansible runs"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "x-projectBKN-web-sg"
  }
}

resource "aws_security_group" "x_projectBKN_streamer_sg" {
  vpc_id = aws_vpc.x_projectBKN_vpc.id

  tags = {
    Name = "x-projectBKN-streamer-sg"
  }
}

resource "aws_security_group_rule" "streamer_ssh_from_web" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  security_group_id        = aws_security_group.x_projectBKN_streamer_sg.id
  source_security_group_id = aws_security_group.x_projectBKN_web_sg.id
  description              = "SSH allowed only from Web Frontend bastion"
}

# Cross-SG RTMP rules (separate resources — re-apply if lost after web_sg inline changes).
resource "aws_security_group_rule" "web_rtmp_from_streamer" {
  type                     = "ingress"
  from_port                = 1935
  to_port                  = 1935
  protocol                 = "tcp"
  security_group_id        = aws_security_group.x_projectBKN_web_sg.id
  source_security_group_id = aws_security_group.x_projectBKN_streamer_sg.id
  description              = "RTMP ingest from Video Streamer only"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "streamer_rtmp_to_web" {
  type                     = "egress"
  from_port                = 1935
  to_port                  = 1935
  protocol                 = "tcp"
  security_group_id        = aws_security_group.x_projectBKN_streamer_sg.id
  source_security_group_id = aws_security_group.x_projectBKN_web_sg.id
  description              = "RTMP push to Web Frontend"
}

resource "aws_security_group_rule" "streamer_egress_internet" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.x_projectBKN_streamer_sg.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Outbound for apt and sample video download"
}

########################################
# Key Pair
########################################

locals {
  ssh_public_key      = file(pathexpand(var.ssh_public_key_path))
  ssh_authorized_keys = concat([local.ssh_public_key], var.team_ssh_public_keys)
  ssh_authorized_yaml = join("\n", [for k in local.ssh_authorized_keys : "  - ${trimspace(k)}"])
}

resource "aws_key_pair" "x_projectBKN_key" {
  key_name   = "x-projectBKN-key"
  public_key = local.ssh_public_key
}

########################################
# Web Frontend EC2 (Public Subnet)
########################################

resource "aws_instance" "x_projectBKN_web" {
  ami                         = data.aws_ami.ubuntu_jammy.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.x_projectBKN_public_subnet.id
  vpc_security_group_ids      = [aws_security_group.x_projectBKN_web_sg.id]
  iam_instance_profile        = var.enable_dns01_iam ? aws_iam_instance_profile.x_projectBKN_web_certbot[0].name : null
  key_name                    = aws_key_pair.x_projectBKN_key.key_name
  associate_public_ip_address = true

  user_data = <<EOF
#cloud-config
ssh_authorized_keys:
${local.ssh_authorized_yaml}
EOF

  tags = {
    Name = "x-projectBKN-web-frontend"
    Role = "bastion"
  }
}

########################################
# Elastic IP (Permanent Public IP)
########################################

resource "aws_eip" "x_projectBKN_web_eip" {
  instance = aws_instance.x_projectBKN_web.id

  tags = {
    Name = "x-projectBKN-web-eip"
  }
}

########################################
# Video Streamer EC2 (Private Subnet, no public IP)
########################################

resource "aws_instance" "x_projectBKN_streamer" {
  ami                         = data.aws_ami.ubuntu_jammy.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.x_projectBKN_private_subnet.id
  vpc_security_group_ids      = [aws_security_group.x_projectBKN_streamer_sg.id]
  key_name                    = aws_key_pair.x_projectBKN_key.key_name
  associate_public_ip_address = false

  user_data = <<EOF
#cloud-config
ssh_authorized_keys:
${local.ssh_authorized_yaml}
EOF

  tags = {
    Name = "x-projectBKN-video-streamer"
    Role = "backend"
  }
}

########################################
# Route53 — team subdomain (Natalia: teambkn.devops.intuitivelabs.net)
########################################

resource "aws_route53_record" "x_projectBKN_web" {
  zone_id = var.route53_zone_id
  name    = var.stream_domain
  type    = "A"
  ttl     = 300
  records = [aws_eip.x_projectBKN_web_eip.public_ip]
}

########################################
# Ansible Inventory (auto-generated)
########################################

locals {
  web_public_ip     = aws_eip.x_projectBKN_web_eip.public_ip
  certbot_challenge = var.enable_dns01_iam ? "dns-route53" : "webroot"
}

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory.ini"

  content = <<-EOT
[web]
${local.web_public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=${var.ansible_ssh_private_key_file}

[web:vars]
stream_domain=${var.stream_domain}
certbot_email=${var.certbot_email}
web_enable_https=true
rtmp_publish_allow_cidr=${aws_subnet.x_projectBKN_private_subnet.cidr_block}
certbot_challenge=${local.certbot_challenge}

[streamer]
${aws_instance.x_projectBKN_streamer.private_ip} ansible_user=ubuntu ansible_ssh_private_key_file=${var.ansible_ssh_private_key_file}

[streamer:vars]
ansible_ssh_common_args=-o ProxyJump=ubuntu@${local.web_public_ip}
web_frontend_private_ip=${aws_instance.x_projectBKN_web.private_ip}
sample_video_url=https://download.blender.org/peach/bigbuckbunny_movies/BigBuckBunny_320x180.mp4
rtmp_application=live
rtmp_stream_name=stream
EOT
}