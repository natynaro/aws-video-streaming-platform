# AWS Video Streaming Platform

End-to-end Infrastructure as Code project that provisions and configures a secure video streaming platform on AWS using Terraform (OpenTofu) and Ansible.

The platform deploys a two-tier architecture where a private video streaming server continuously publishes an RTMP stream to a public web frontend that serves HLS and DASH content over HTTPS.


## Overview

This project demonstrates:

- Infrastructure as Code with Terraform/OpenTofu
- Configuration management with Ansible
- AWS networking design (VPC, public/private subnets, routing)
- Secure access control through Security Groups
- Route53 DNS integration
- HTTPS automation using Let's Encrypt
- NGINX RTMP streaming
- FFmpeg-based video ingestion
- CI validation pipelines
- Infrastructure documentation and automation



## Architecture

```text
                       Internet
                           │
                           ▼
                  HTTPS (443)
                           │
                    Route53 DNS
                           │
                           ▼
                 Web Frontend EC2
               (Public Subnet)
             ┌───────────────────┐
             │ NGINX + RTMP      │
             │ HLS / DASH        │
             │ Let's Encrypt     │
             └───────────────────┘
                           ▲
                           │ RTMP (1935)
                           │
             ┌───────────────────┐
             │ Video Streamer EC2│
             │ FFmpeg            │
             │ Looping Video     │
             └───────────────────┘
               (Private Subnet)

```

AWS resources include:

- VPC
- Public subnet
- Private subnet
- Internet Gateway
- NAT Gateway
- Route Tables
- Security Groups
- EC2 Instances
- Route53 Records
- IAM Policies (optional DNS-01 challenge)



## Technology Stack

### Infrastructure

- AWS
- Terraform / OpenTofu
- Route53
- EC2
- IAM

### Configuration Management

- Ansible
- Ansible Roles
- Jinja2 Templates

### Streaming

- FFmpeg
- NGINX
- NGINX RTMP Module
- HLS
- MPEG-DASH

### Security

- Let's Encrypt
- Certbot
- Security Groups
- Private Subnets

### CI/CD

- GitHub Actions



## Project Structure

```text
.
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── providers.tf
│   ├── iam.tf
│   ├── data.tf
│   ├── init-backend.sh
│   ├── .terraform.lock.hcl
│   └── terraform.tfvars.example
│
├── ansible/
│   ├── playbooks/
│   ├── roles/
│   │   ├── web/
│   │   └── streamer/
│   ├── ansible.cfg
│   └── inventory.example
│
├── docs/
│   ├── architecture.md
│   ├── architecture.png
│   ├── ansible-design.md
│   ├── terraform-design.md
│   └── report.md
│
├── .github/
│   └── workflows/
│       └── validate.yml
├── .env.example
├── .gitignore
├── README.md
└── LICENSE
```



## Infrastructure Components

### Web Frontend

Located in the public subnet.

Responsibilities:

- Receives RTMP streams
- Generates HLS playlists
- Generates DASH manifests
- Serves video content over HTTPS
- Hosts the demo website

### Video Streamer

Located in the private subnet.

Responsibilities:

- Downloads sample video content
- Runs FFmpeg as a systemd service
- Publishes RTMP streams to the frontend
- Remains inaccessible from the public internet



## Security Design

The platform follows a layered security model.

### Public Access

Allowed:

- HTTPS (443)

Restricted:

- Direct access to the video streamer

### Internal Traffic

Allowed:

- RTMP (1935) from the private streamer subnet to the frontend

All other traffic is denied by default through Security Groups.



## Deployment Workflow

### 1. Configure AWS credentials

```bash
aws configure sso
```

### 2. Initialize Terraform backend

```bash
./terraform/init-backend.sh
```

### 3. Deploy infrastructure

```bash
cd terraform

tofu init
tofu plan
tofu apply
```

### 4. Configure servers

```bash
export ANSIBLE_CONFIG=ansible/ansible.cfg

ansible-playbook \
  -i ansible/inventory.ini \
  ansible/playbooks/deploy-all.yml
```

### 5. Validate deployment

```bash
ansible-playbook \
  -i ansible/inventory.ini \
  ansible/playbooks/validate-streaming.yml
```



## Streaming Endpoints

### HLS

```text
https://your-domain/hls/stream.m3u8
```

### DASH

```text
https://your-domain/dash/stream.mpd
```



## Automation Features

- Fully automated infrastructure provisioning
- Automatic inventory generation for Ansible
- Ansible role-based deployment
- FFmpeg managed through systemd
- Automated SSL certificate deployment
- Infrastructure validation playbooks
- GitHub Actions validation workflow



## Technical Challenges

### Route53 DNS-01 Validation

The project includes support for Let's Encrypt DNS-01 validation using Route53 and IAM.

However, the AWS training environment used during development did not allow IAM role creation (`iam:CreateRole` was denied).

To maintain HTTPS automation, HTTP-01 validation was used as a fallback strategy.

The DNS-01 implementation remains fully available in the codebase and can be enabled in environments with appropriate IAM permissions.

### DASH Compatibility

The NGINX RTMP module provides basic DASH support.

Several improvements were implemented:

- Correct MIME types
- Extended DASH playlist duration
- Automated validation checks

HLS remains the most reliable playback option across platforms.



## Lessons Learned

This project provided practical experience with:

- Infrastructure as Code principles
- AWS networking and security design
- Infrastructure automation
- Configuration management
- Streaming architectures
- SSL certificate automation
- Service orchestration with systemd
- CI validation workflows


## Future Improvements

Potential next steps include:

- Terraform modules refactoring
- CloudWatch monitoring
- AWS Systems Manager integration
- S3-based HLS storage
- CloudFront CDN integration
- Auto Scaling Groups
- Multi-AZ deployment
- Complete CI/CD deployment pipeline


## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).