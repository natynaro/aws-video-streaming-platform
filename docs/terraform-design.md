Esta sección describe la carpeta `terraform/`, siguiendo un formato claro con arquitectura, implementación, mejoras y trabajo futuro.

# Terraform Infrastructure Implementation

## Purpose of the Terraform folder

The `terraform/` folder contains the infrastructure-as-code definition for the AWS Video Streaming App Automation project. Its purpose is to provision the cloud resources required by the architecture diagram: a secure two-tier deployment with a public Web Frontend, a private Video Streamer, Route53 DNS integration, IAM permissions for certificate automation, and networking components such as VPC, subnets, routing tables, Internet Gateway and NAT Gateway.

Terraform is responsible only for creating the AWS infrastructure. Once the infrastructure is created, Ansible uses the generated inventory to configure the Web Frontend and Video Streamer instances.

The current Terraform folder is organized as follows:

```text
terraform/
├── .terraform.lock.hcl
├── data.tf
├── iam.tf
├── init-backend.sh
├── main.tf
├── outputs.tf
├── providers.tf
└── variables.tf
```

Each file has a specific role. `main.tf` contains the main AWS resources such as the VPC, subnets, EC2 instances, route tables, security groups, Route53 record and generated Ansible inventory. `iam.tf` contains the IAM role and permissions required for Let’s Encrypt DNS-01 validation through Route53. `variables.tf` defines configurable values such as SSH keys, domain name, Route53 hosted zone and certificate mode. `outputs.tf` exposes important values after deployment, such as instance IPs, security group IDs and certificate-related resources. `data.tf` selects the Ubuntu AMI used by the EC2 instances. `providers.tf` defines the AWS and local providers and the remote backend configuration. `init-backend.sh` helps initialize GitLab-managed OpenTofu/Terraform remote state.

***

## What was required by the project diagram

According to the architecture diagram, the Terraform implementation had to create the infrastructure required for the video streaming system. The expected infrastructure included:

* One AWS VPC.
* A public subnet for the Web Frontend.
* A private subnet for the Video Streamer.
* An Internet Gateway for public access to the frontend.
* Route tables and routes for public/private traffic.
* Two EC2 instances:
  * Web Frontend in the public subnet.
  * Video Streamer in the private subnet.
* Security groups restricting traffic:
  * public access only to the Web Frontend.
  * RTMP traffic only between Video Streamer and Web Frontend.
  * no direct internet access to the Video Streamer.
* Route53 DNS record for the public streaming domain.
* IAM permissions allowing the Web Frontend to update Route53 records for Let’s Encrypt DNS-01 validation.
* Outputs needed by Ansible for configuration.

The intended traffic model was:

```text
User
  ↓
Internet Gateway
  ↓
Web Frontend EC2
  ↓ RTMP / internal communication
Video Streamer EC2
```

The certificate automation model required by the diagram was:

```text
Web Frontend
  ↓
IAM Role / Instance Profile
  ↓
Route53 TXT record update
  ↓
Let’s Encrypt DNS-01 validation
  ↓
Valid HTTPS certificate
```

***

## What is currently implemented

The Terraform implementation correctly provisions the core AWS infrastructure required by the project.

### VPC and subnet architecture

The VPC is defined with the CIDR block:

```hcl
cidr_block = "172.16.0.0/16"
```

DNS support and DNS hostnames are enabled:

```hcl
enable_dns_support   = true
enable_dns_hostnames = true
```

This is important because the project uses DNS, Route53 records and EC2 networking.

The subnet design follows the two-tier architecture:

```text
172.16.1.0/24 → public subnet
172.16.2.0/24 → private subnet
```

The Web Frontend is placed in the public subnet and receives a public IP:

```hcl
subnet_id                   = aws_subnet.x_projectBKN_public_subnet.id
associate_public_ip_address = true
```

The Video Streamer is placed in the private subnet and does not receive a public IP:

```hcl
subnet_id                   = aws_subnet.x_projectBKN_private_subnet.id
associate_public_ip_address = false
```

This matches the diagram because only the Web Frontend should be reachable from the outside, while the Video Streamer remains private.

***

### Internet access and routing

The public subnet is connected to the internet through an Internet Gateway:

```hcl
resource "aws_internet_gateway" "x_projectBKN_igw" {
  vpc_id = aws_vpc.x_projectBKN_vpc.id
}
```

The public route table sends internet-bound traffic through the Internet Gateway:

```hcl
route {
  cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.x_projectBKN_igw.id
}
```

For the private subnet, a NAT Gateway is implemented:

```hcl
resource "aws_nat_gateway" "x_projectBKN_nat" {
  allocation_id = aws_eip.x_projectBKN_nat.id
  subnet_id     = aws_subnet.x_projectBKN_public_subnet.id
}
```

This is not strictly required by the base diagram, but it is a good improvement. It allows the private Video Streamer to download packages and the sample video without exposing it to inbound internet traffic.

The private route table routes outbound internet traffic through the NAT Gateway:

```hcl
route {
  cidr_block     = "0.0.0.0/0"
  nat_gateway_id = aws_nat_gateway.x_projectBKN_nat.id
}
```

This keeps the Video Streamer private while still allowing necessary outbound provisioning access.

***

### Security groups

The Web Frontend security group exposes the required public services:

```hcl
from_port = 443
to_port   = 443
protocol  = "tcp"
```

Port `443` is necessary because users must access the Web Frontend through HTTPS.

Port `80` is also open:

```hcl
from_port = 80
to_port   = 80
protocol  = "tcp"
```

In the current implementation, this is documented as HTTP-to-HTTPS redirection. Since DNS-01 validation does not require HTTP access, port `80` is not mandatory for certificates anymore. However, keeping it only for redirection is acceptable.

SSH access to the Web Frontend is restricted using `admin_ssh_cidr_blocks`:

```hcl
cidr_blocks = var.admin_ssh_cidr_blocks
```

This is better than allowing SSH from everywhere.

The Video Streamer security group is more restrictive. SSH access to the private instance is allowed only from the Web Frontend security group:

```hcl
source_security_group_id = aws_security_group.x_projectBKN_web_sg.id
```

This correctly implements the bastion/jump-host model, where the Web Frontend is used to reach the private instance.

RTMP traffic is also restricted. The Web Frontend accepts RTMP only from the Video Streamer security group:

```hcl
security_group_id        = aws_security_group.x_projectBKN_web_sg.id
source_security_group_id = aws_security_group.x_projectBKN_streamer_sg.id
from_port                = 1935
to_port                  = 1935
protocol                 = "tcp"
```

The Video Streamer can push RTMP traffic to the Web Frontend:

```hcl
security_group_id        = aws_security_group.x_projectBKN_streamer_sg.id
source_security_group_id = aws_security_group.x_projectBKN_web_sg.id
from_port                = 1935
to_port                  = 1935
protocol                 = "tcp"
```

This matches the required streaming flow:

```text
Video Streamer → RTMP port 1935 → Web Frontend
```

***

### EC2 instances

The Web Frontend EC2 instance is correctly deployed in the public subnet:

```hcl
resource "aws_instance" "x_projectBKN_web" {
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.x_projectBKN_public_subnet.id
  associate_public_ip_address = true
}
```

It is also assigned an Elastic IP:

```hcl
resource "aws_eip" "x_projectBKN_web_eip" {
  instance = aws_instance.x_projectBKN_web.id
}
```

This is a useful improvement because it provides a stable public endpoint for Route53.

The Video Streamer EC2 instance is correctly deployed in the private subnet:

```hcl
resource "aws_instance" "x_projectBKN_streamer" {
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.x_projectBKN_private_subnet.id
  associate_public_ip_address = false
}
```

Both instances receive SSH authorized keys through cloud-init:

```hcl
ssh_authorized_keys:
${local.ssh_authorized_yaml}
```

This supports team access without manually configuring keys after deployment.

***

### Route53 DNS record

The public streaming domain is mapped to the Web Frontend Elastic IP:

```hcl
resource "aws_route53_record" "x_projectBKN_web" {
  zone_id = var.route53_zone_id
  name    = var.stream_domain
  type    = "A"
  ttl     = 300
  records = [aws_eip.x_projectBKN_web_eip.public_ip]
}
```

This implements the expected DNS path:

```text
stream_domain → Web Frontend Elastic IP
```

This is required so users can access the streaming service using a domain instead of an IP address.

***

### IAM for DNS-01 certificate automation

The current implementation includes an `iam.tf` file dedicated to Let’s Encrypt DNS-01 automation through Route53.

The EC2 assume-role policy allows the Web Frontend instance to assume an IAM role:

```hcl
actions = ["sts:AssumeRole"]

principals {
  type        = "Service"
  identifiers = ["ec2.amazonaws.com"]
}
```

The Route53 policy allows listing hosted zones and changing DNS records:

```hcl
actions = [
  "route53:GetChange",
  "route53:ListHostedZones",
  "route53:ListHostedZonesByName",
]
```

and:

```hcl
actions = [
  "route53:ChangeResourceRecordSets",
]
```

The `ChangeResourceRecordSets` permission is restricted to the configured hosted zone:

```hcl
"arn:aws:route53:::hostedzone/${var.route53_zone_id}"
```

This is a good security decision because it avoids granting unnecessary permissions to all Route53 zones.

The IAM instance profile is conditionally attached to the Web Frontend:

```hcl
iam_instance_profile = var.enable_dns01_iam ? aws_iam_instance_profile.x_projectBKN_web_certbot[0].name : null
```

This supports two deployment modes:

```text
enable_dns01_iam = true  → DNS-01 via Route53
enable_dns01_iam = false → fallback mode
```

For the architecture required by the diagram, `enable_dns01_iam` should be set to `true`.

***

### Ansible inventory generation

Terraform automatically generates the Ansible inventory:

```hcl
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory.ini"
}
```

The generated inventory includes:

```ini
[web]
<web_public_ip>

[streamer]
<streamer_private_ip>
```

It also passes important variables to Ansible:

```ini
stream_domain=<domain>
certbot_email=<email>
rtmp_publish_allow_cidr=<private_subnet_cidr>
certbot_challenge=<dns-route53-or-webroot>
web_frontend_private_ip=<web_private_ip>
```

This is a strong automation feature because Terraform directly provides Ansible with all required infrastructure values. It avoids manual copy-paste of IP addresses, subnet CIDRs and domain configuration.

The inventory also configures ProxyJump for the private streamer:

```ini
ansible_ssh_common_args=-o ProxyJump=ubuntu@<web_public_ip>
```

This supports the architecture where the Web Frontend acts as the bastion host for Ansible access to the private Video Streamer.

***

## Extra elements beyond the base requirements

Several features go beyond the minimum diagram and are well implemented.

### NAT Gateway

The NAT Gateway was not strictly required in the base statement, but it is very useful. It enables outbound internet access from the private subnet while keeping the Video Streamer unreachable from the internet.

This supports:

```text
Video Streamer → NAT Gateway → Internet
```

for:

* `apt` package installation
* FFmpeg installation
* sample video download

without exposing inbound access to the private instance.

***

### Elastic IP

The Web Frontend uses an Elastic IP instead of relying only on an automatically assigned public IP. This improves stability because the Route53 record always points to a permanent public address.

This is useful for:

```text
Route53 A record → Elastic IP → Web Frontend
```

***

### Automatic Ansible inventory

The generated inventory is a strong DevOps improvement. It connects infrastructure provisioning and configuration management automatically.

Instead of manually writing:

```ini
[web]
x.x.x.x

[streamer]
172.16.x.x
```

Terraform generates these values directly from created resources.

***

### Optional DNS-01 IAM mode

The variable:

```hcl
variable "enable_dns01_iam" {
  type    = bool
  default = false
}
```

makes IAM creation optional. This is useful in lab environments where the user may not have permission to create IAM roles.

When enabled, the project matches the diagram requirement:

```text
DNS-01 + Route53 + IAM
```

When disabled, the project can still be deployed in a more limited environment, although that fallback does not fully represent the DNS-01 architecture.

***

### Remote state with GitLab/OpenTofu

The backend configuration and `init-backend.sh` support a shared team state. This is useful because multiple team members can collaborate without overwriting each other’s local Terraform state.

The lock file also shows that the project is being initialized with OpenTofu-compatible providers.

***

## Current issues and future improvements

The Terraform implementation is functionally aligned with the project diagram when `enable_dns01_iam = true`. However, there are still some points that should be revised or documented.

### 1. DNS-01 is optional, but required by the diagram

The variable:

```hcl
enable_dns01_iam = false
```

is currently set to `false` by default.

This is understandable for lab environments where IAM creation may be restricted, but according to the diagram, DNS-01 Route53 automation is required.

For full compliance with the architecture, the deployment should use:

```hcl
enable_dns01_iam = true
```

If it remains `false`, the IAM role and instance profile are not created, and the Web Frontend will not have the AWS permissions required for Route53 DNS-01 automation.

So the implementation supports the required design, but the default does not activate it.

***

### 2. Possible HTML markup in Terraform files

Some pasted file contents show HTML-formatted links, for example inside `providers.tf` and the generated inventory content.

The real Terraform files must contain plain strings, not HTML anchor tags.

For example, the backend address must be a plain string:

```hcl
address = "..."
```

not an HTML link.

The same applies to:

```hcl
sample_video_url=...
```

If HTML markup remains in the real `.tf` files, Terraform/OpenTofu will fail to parse or will generate invalid Ansible inventory.

This is the most important thing to verify before deployment.

***

### 3. Port 80 remains open

Port `80` is still publicly open on the Web Frontend:

```hcl
from_port = 80
to_port   = 80
```

This is acceptable if it is only used for HTTP-to-HTTPS redirection. Since the project now supports DNS-01 validation, port `80` is no longer needed for certificate generation.

Future improvement:

```text
Keep port 80 only for redirect, or remove it entirely for stricter security.
```

***

### 4. Streamer outbound access is broad

The Video Streamer has outbound access to the internet:

```hcl
cidr_blocks = ["0.0.0.0/0"]
```

This is useful for provisioning, package installation and video download. However, from a stricter security point of view, it could be narrowed after setup.

Future improvement:

```text
Allow broad outbound during provisioning, then restrict to only required destinations or protocols.
```

***

### 5. Provider versions are not pinned in providers.tf

The lock file contains selected provider versions, but `providers.tf` does not explicitly pin versions:

```hcl
aws = {
  source = "hashicorp/aws"
}
```

Future improvement:

```hcl
aws = {
  source  = "hashicorp/aws"
  version = "~> 6.50"
}
```

and:

```hcl
local = {
  source  = "hashicorp/local"
  version = "~> 2.9"
}
```

This would make the infrastructure more reproducible.

***

### 6. Terraform and OpenTofu terminology should be clarified

The folder is named:

```text
terraform/
```

The scripts and lock file use OpenTofu-compatible tooling:

```text
tofu init
tofu apply
```

This does not break the implementation, but the documentation should clarify that the project uses OpenTofu as a Terraform-compatible tool, or standardize the wording.

***

### 7. Minor formatting/details

There are a few small formatting issues that do not affect the architecture but should be cleaned:

```hcl
description = "RTMP ingest from Video Streameronly"
```

should be:

```hcl
description = "RTMP ingest from Video Streamer only"
```

and:

```hcl
resource "aws_security_group_rule" "streamer_egress_internet"{
```

could be formatted as:

```hcl
resource "aws_security_group_rule" "streamer_egress_internet" {
```

These are cosmetic, but cleaning them improves readability.

***

## Final Terraform evaluation

The Terraform folder correctly implements the required AWS infrastructure for the video streaming architecture. It provisions the VPC, public and private subnets, routing, Internet Gateway, NAT Gateway, EC2 instances, Elastic IP, security groups, Route53 DNS record, IAM permissions for Route53 DNS-01 validation, and an automatically generated Ansible inventory.

The required two-tier architecture is respected:

```text
Public Web Frontend
Private Video Streamer
Restricted internal RTMP communication
HTTPS domain access through Route53
```

The implementation also includes several valuable improvements beyond the base requirements, such as NAT-based private outbound access, Elastic IP, remote state, team SSH key support, optional IAM creation, and Terraform-to-Ansible integration.

The main point to document is that DNS-01 compliance depends on enabling:

```hcl
enable_dns01_iam = true
```

If this variable remains `false`, the infrastructure can still be deployed, but it does not fully activate the DNS-01 Route53 path required by the diagram.

Overall, the Terraform implementation is strong, modular and close to production-style infrastructure automation. The remaining issues are mostly configuration hygiene and optional hardening rather than missing core architecture components.