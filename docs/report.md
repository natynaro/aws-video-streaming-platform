# GIN207 — AWS Video Streaming Application Automation

**Team:** BKN\
**GitLab Repository:** `gin852423/GIN207`\
**Demonstration URL (not longer working):** [Webroot Classification: green

https://teambkn.devops.intuitivelabs.net/hls/stream.m3u8](<https://teambkn.devops.intuitivelabs.net/hls/stream.m3u8>)


## Introduction

This report describes the implementation of the GIN207 AWS Video Streaming Application Automation project. It presents the architecture requirements defined by the course, the infrastructure and application components implemented in the code, the additional improvements introduced by the team, and the limitations encountered during deployment.

The report distinguishes between the original project requirements, the features successfully implemented and deployed, additional improvements, and deviations or limitations that could not be resolved within the available AWS laboratory environment.

The repository architecture diagram is available at `docs/architecture.png`. Further technical details are documented in `docs/architecture.md`.


## 1\. Target Architecture and Course Requirements

The project requires a fully automated **two-tier architecture** deployed on AWS, with infrastructure provisioning and configuration managed from the laboratory workstation using Terraform and Ansible.

The target architecture consists of the following components:

text

```text
Laboratory Workstation (Terraform + Ansible)
                    |
                    v
                 AWS VPC
                    |
        +--+--+
        |                       |
  Private Subnet           Public Subnet
        |                       |
  Video Streamer           Web Frontend
     (EC2)                    (EC2)
        |                       |
        +--+--+
                    |
              Route 53 (DNS)
                    |
              IAM Permissions
                    |
             Let's Encrypt
          (HTTPS / DNS-01)
```

### 1.1 Expected Application Workflow

The expected application workflow is based on RTMP ingestion and HLS/DASH streaming:

text

```text
User
 |
 | HTTPS :443
 v
Web Frontend
 |
 | RTMP ingestion :1935
 v
NGINX RTMP Server
 |
 +> HLS / DASH segments
 |
 v
HTTPS Video Playback
```

The Video Streamer continuously sends video data to the Web Frontend through the RTMP protocol. The Web Frontend, running NGINX with the RTMP module, receives the stream and generates HLS and DASH segments that can subsequently be accessed by users over HTTPS.

### 1.2 Security Requirements

The original specifications define the following security constraints:

- End users must access only the Web Frontend through HTTPS on port **443**.
- The Video Streamer must not be directly accessible from the public internet.
- Communication between virtual machines must be restricted to the required ports, particularly RTMP on port **1935**.
- A valid SSL/TLS certificate must be obtained automatically using Let's Encrypt, DNS-01 validation, Route 53, and IAM permissions, as illustrated in the reference architecture.



## 2\. Implementation Details

This section describes the infrastructure and application components actually implemented in the project repository.

### 2.1 Infrastructure Provisioning — OpenTofu (`terraform/`)

Although the course refers to Terraform, the project uses **OpenTofu**, an open-source infrastructure-as-code tool compatible with the Terraform configuration language.

Infrastructure provisioning is performed using `tofu apply`, with a remote state stored in GitLab.

The following table summarizes the infrastructure requirements and their implementation.

| Course Requirement | Implementation Status | File / Resource |
|  |  |  |
| VPC `172.16.0.0/16` | Implemented | `aws_vpc.x_projectBKN_vpc` — `main.tf` |
| Public subnet (Web) | Implemented | `172.16.1.0/24` — `aws_subnet.x_projectBKN_public_subnet` |
| Private subnet (Streamer) | Implemented | `172.16.2.0/24` — `aws_subnet.x_projectBKN_private_subnet` |
| Internet Gateway | Implemented | `aws_internet_gateway.x_projectBKN_igw` |
| Route tables | Implemented | Public subnet → IGW; Private subnet → NAT — `aws_route_table_*` |
| Two EC2 instances (public Web, private Streamer) | Implemented | `aws_instance.x_projectBKN_web` / `_streamer` |
| Elastic IP for the Web instance | Implemented | `aws_eip.x_projectBKN_web_eip` |
| HTTPS security group on port 443 | Implemented | `aws_security_group.x_projectBKN_web_sg` |
| RTMP port 1935 (Streamer → Web only) | Implemented | `aws_security_group_rule.web_rtmp_from_streamer` |
| Route 53 DNS record (A → EIP) | Implemented | `aws_route53_record.x_projectBKN_web` |
| IAM role and instance profile for DNS-01 | Code implemented / Deployment unsuccessful | `iam.tf` — see Section 4.1 |
| Automatic Ansible inventory generation | Implemented (additional feature) | `local_file.ansible_inventory` — `main.tf` |

The first automation stage defined by the course, corresponding to AWS infrastructure provisioning, is covered by the following commands:

bash

```bash
./terraform/init-backend.sh
cd terraform
tofu init
tofu apply
```

The initialization script configures the GitLab remote backend before infrastructure provisioning.

### 2.2 Server Configuration and Application Deployment — Ansible (`ansible/`)

Ansible is used to configure both EC2 instances and deploy the video streaming infrastructure.

The Web Frontend and Video Streamer are configured independently through dedicated Ansible roles.

#### Web Frontend Configuration

| Requirement | Implementation Status | File / Role |
|  |  |  |
| Install NGINX, `libnginx-mod-rtmp`, and `ffmpeg` | Implemented | `roles/web/tasks/main.yml` |
| Create `/var/www/html/stream/{hls,dash}` directories | Implemented | `roles/web/tasks/main.yml` |
| Configure NGINX for RTMP, HLS, and DASH | Implemented | `roles/web/templates/nginx.conf.j2` |
| Configure `/hls` and `/dash` virtual paths | Implemented | `roles/web/templates/streamer.conf.j2` |
| Obtain Let's Encrypt certificate and enable HTTPS | Implemented | `roles/web/tasks/certificate.yml` — HTTP-01 in production |
| Configure DNS-01 validation through Route 53 | Code implemented only | `certbot --dns-route53` when `enable_dns01_iam = true` |

The NGINX configuration follows the technical guidelines provided by the course, including the RTMP module, the `application live` configuration, HLS/DASH output directories, and CORS configuration for `/dash`.

One configuration was adapted to match the actual AWS network environment. The `allow publish` directive uses the private subnet CIDR (`rtmp_publish_allow_cidr`), dynamically provided by Terraform, instead of the `127.0.0.0/16` and `192.168.0.0/16` ranges mentioned in the original assignment.

#### Video Streamer Configuration

| Requirement | Implementation Status | File / Role |
|  |  |  |
| Install FFmpeg | Implemented | `roles/streamer/tasks/main.yml` |
| Download Big Buck Bunny sample video | Implemented | Ansible `get_url` from `download.blender.org` |
| Configure continuous RTMP streaming | Implemented | `roles/streamer/templates/ffmpeg-stream.service.j2` |
| Stream to the Web instance through its private IP | Implemented | `rtmp://<web-ip>:1935/live/stream` |
| Configure automatic service startup | Implemented | systemd `ffmpeg-stream` service |

The Video Streamer uses FFmpeg to continuously transmit the sample video to the NGINX RTMP server running on the Web Frontend.

The second automation stage defined by the course, corresponding to server configuration and application deployment, is implemented through the following Ansible playbook:

`ansible/playbooks/deploy-all.yml`

Its execution sequence is:

text

```text
web-setup
    ↓
deploy-certificate
    ↓
deploy-website
    ↓
streamer-setup
    ↓
validate-streaming
```

#### DASH Streaming Configuration

Additional configuration was introduced to improve DASH compatibility and validation.

The implementation includes:

- Correct MIME types for `.m4v` and `.m4a` media segments.
- A DASH playlist duration of `60s`, configured through `dash_playlist_length 60s`.
- Validation checks for the MPD manifest and initialization segment MIME types.

These changes were deployed and verified.

### 2.3 Functional Results

The complete video streaming pipeline works in the demonstration environment.

The implemented workflow is:

text

```text
Video Streamer
     |
     | FFmpeg + systemd
     |
     v
RTMP :1935
     |
     v
Web Frontend
     |
     | NGINX RTMP
     |
     v
HLS / DASH Segments
     |
     v
HTTPS Video Playback
```

The following endpoints are available:

| Service | URL | Demonstration Status |
|  |  |  |
| HLS | [Webroot Classification: green<br>https://teambkn.devops.intuitivelabs.net/hls/stream.m3u8](<https://teambkn.devops.intuitivelabs.net/hls/stream.m3u8>) | Working — Recommended (Akamai, VLC) |
| DASH | [Webroot Classification: green<br>https://teambkn.devops.intuitivelabs.net/dash/stream.mpd](<https://teambkn.devops.intuitivelabs.net/dash/stream.mpd>) | Manifest and segments working; dash.js may present compatibility issues |
| Homepage | [Webroot Classification: green<br>https://teambkn.devops.intuitivelabs.net/](<https://teambkn.devops.intuitivelabs.net/>) | Working |

HLS is the recommended format for the final demonstration because it provides the most reliable playback experience in the tested environment.

DASH manifests and media segments are generated correctly, although some compatibility limitations remain when using dash.js, as discussed in Section 4.2.



## 3\. Additional Improvements Beyond the Course Requirements

Several features were introduced beyond the original assignment requirements to improve automation, reliability, security, and collaboration between team members.

| Improvement | Purpose | Implementation |
|  |  |  |
| **NAT Gateway** | Allows the private Video Streamer instance to install packages and download the sample video without requiring a public IP address | `terraform/main.tf` |
| **Web Frontend as an SSH Bastion** | Provides SSH access to the private instance through the public Web instance using `ProxyJump` | Generated `inventory.ini`, `streamer_ssh_from_web` security group |
| **FFmpeg systemd Service** | Ensures automatic startup and service recovery through `Restart=always`, instead of requiring manual execution | `roles/streamer/` |
| **Dedicated System User** | Runs FFmpeg under a dedicated `streamer` user instead of root | `roles/streamer/tasks/main.yml` |
| **Automatic Terraform-to-Ansible Inventory Generation** | Eliminates manual copying of IP addresses, domain names, and CIDR values | `local_file.ansible_inventory` |
| **Centralized Deployment Playbook** | Allows the complete deployment process to be executed through a single command | `ansible/playbooks/` |
| **Streaming Validation Playbook** | Checks HLS, DASH, NGINX, and FFmpeg after deployment | `ansible/playbooks/validate-streaming.yml` |
| **Demonstration Homepage** | Provides direct HLS and DASH playback links for the project presentation | `roles/web/templates/index.html.j2` |
| **GitLab Remote State** | Allows infrastructure state to be shared between team members | `init-backend.sh`, `providers.tf` |
| **GitHub Actions Pipeline** | Runs `tofu validate` and Ansible syntax checks on every push or pull request | `.github/workflows/validate.yml` |
| **Certbot Automatic Renewal** | Maintains certificate validity without manual intervention | `certificate.yml` |
| **NGINX Configuration Validation** | Executes `nginx -t` before restarting NGINX to avoid applying invalid configurations | `roles/web/handlers/main.yml` |
| **HTTP-01 Fallback** | Provides an alternative certificate validation method when `enable_dns01_iam = false` | `certificate.yml` |
| **Operational Documentation** | Provides project usage and implementation documentation | `README.md`, `docs/` |

These improvements make the deployment more reproducible and reduce the amount of manual configuration required during infrastructure provisioning and application deployment.



## 4\. Deviations, Errors, and Known Limitations

Although the main application workflow is functional, certain aspects of the implementation differ from the original architecture or remain partially constrained by the AWS laboratory environment.

This section documents these deviations and explains their causes.

### 4.1 HTTPS — DNS-01 and IAM: Implemented in Code but Not Deployable on DevopsLab

One of the main differences between the reference architecture and the deployed infrastructure concerns the DNS-01 certificate validation mechanism.

The original architecture requires Let's Encrypt to validate domain ownership through DNS-01, using Route 53 and IAM permissions.

The implementation includes the necessary Terraform and Ansible configuration, but the deployment of this mechanism was blocked by the permissions available in the DevopsLab AWS account.

| Expected Configuration | Code Implementation | Actual Deployment |
|  |  |  |
| Let's Encrypt DNS-01 validation | `iam.tf` and `certbot --dns-route53` | Not used |
| IAM role allowing the Web EC2 instance to modify Route 53 records | `enable_dns01_iam = true` by default in `variables.tf` | Role not created |
| Valid HTTPS certificate | HTTP-01 or DNS-01, depending on the configuration variable | HTTP-01 (webroot) |

#### Reason for the Limitation

The DevopsLab AWS SSO role does not have permission to execute `iam:CreateRole`.

This limitation was verified using the AWS CLI:

bash

```bash
aws sts get-caller-identity

aws iam create-role --role-name x-projectBKN-iam-probe-test \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
```

The command returned:

text

```text
AccessDenied: ... not authorized to perform: iam:CreateRole
```

The same permission error occurred when executing `tofu apply` with `enable_dns01_iam = true`, resulting in a 403 error for:

text

```text
aws_iam_role.x_projectBKN_web_certbot
```

#### Actual Configuration

To allow deployment within the DevopsLab environment, the following configuration is used in `terraform/terraform.tfvars`:

hcl

```hcl
enable_dns01_iam = false
```

This configuration produces the following deployment behavior:

- `certbot_challenge=webroot` is generated in `ansible/inventory.ini`.
- No IAM instance profile is attached to the Web EC2 instance.
- HTTP port **80** is used for the ACME HTTP-01 challenge.
- HTTPS traffic is still enabled, with HTTP requests redirected to HTTPS.

This is not an omission in the implementation. The DNS-01 workflow is implemented in the code, but the AWS laboratory account does not allow the creation of the required IAM roles.

To deploy the original DNS-01 architecture, an AWS account with `iam:CreateRole` permissions or an instance profile provided by an administrator would be required.

### 4.2 DASH — Deployed Corrections and dash.js Compatibility Limitations

Several issues were identified during DASH implementation and corrected in the deployed configuration.

| Problem | Correction | Status |
|  |  |  |
| `.m4v` and `.m4a` segments returned as `application/octet-stream` | Configured `video/mp4` and `audio/mp4` MIME types in `streamer.conf.j2` | Deployed |
| MPD playback window too short | Set `dash_playlist_length 60s` in `nginx.conf.j2` | Deployed |
| Insufficient DASH validation | Added MPD and initialization segment MIME checks in `validate-streaming.yml` | Deployed |
| Compatibility between nginx-rtmp MPD output and dash.js | No complete solution implemented | Remaining limitation |

The remaining DASH compatibility issue is related to limitations of the `libnginx-mod-rtmp` module, particularly the generated MPD manifest characteristics:

- `bandwidth="0"`.
- No `UTCTiming` information.

As a result, although the DASH manifest and media segments are generated correctly, playback through dash.js may remain unreliable.

For the final demonstration, HLS remains the preferred streaming format.

### 4.3 Additional Security Deviations

Some security configurations were relaxed to accommodate the available infrastructure and operational requirements.

| Security Aspect | Expected / Ideal Configuration | Actual Implementation | Severity |
|  |  |  |  |
| User access | HTTPS port 443 only | Port 443 enabled; port 80 also open for HTTPS redirection and HTTP-01 validation | Medium |
| Video Streamer egress | Minimal outbound access | `0.0.0.0/0` to allow package installation and video downloads | Low |
| SSH Bastion access | Restricted to team members | `admin_ssh_cidr_blocks` includes a campus `/16` CIDR range | Medium |
| Infrastructure tool | Terraform, as specified in the assignment | OpenTofu used in practice | Cosmetic |

These deviations are documented to distinguish the implemented security configuration from the stricter configuration originally intended.

### 4.4 Errors Corrected During Development

Several implementation issues were identified and corrected during the project:

- **Security group configuration:** The RTMP security group rule was extracted into a separate `aws_security_group_rule` resource to avoid security group configuration drift.
- **RTMP destination IP:** The streaming destination was corrected to use the Web instance's private IP address instead of its public IP.
- **DASH configuration:** MIME types for `.m4v` and `.m4a`, the DASH playlist duration, and validation checks were corrected, deployed, and verified.
- **DNS-01 configuration:** The code was aligned with the course architecture, with `enable_dns01_iam = true` as the default in `variables.tf`. However, deployment was blocked by the `iam:CreateRole` restriction in DevopsLab, requiring HTTP-01 for the production demonstration.

### 4.5 Features Not Implemented

Some features remained outside the project scope or could not be completed within the available development time.

These include:

- A complete CI/CD pipeline capable of automatically provisioning infrastructure and deploying the application. The existing CI pipeline only performs validation.
- AWS Systems Manager Session Manager as an alternative to the SSH bastion.
- CloudWatch monitoring and alarms for NGINX, FFmpeg, and HLS availability.
- Fine-grained outbound traffic restrictions for the Video Streamer, limiting access to package repositories and the video download URL.
- A dedicated infrastructure destruction runbook using `tofu destroy`, including cost alerts for the NAT Gateway.
- Deployment of the reference application [Webroot Classification: green
  IntuitiveSoft-net/stream-it](<https://github.com/IntuitiveSoft-net/stream-it>). A minimal custom homepage was implemented instead.



## 5\. Challenges Encountered and Solutions

During implementation, several technical and environmental challenges were encountered.

The following table summarizes the main difficulties and the solutions adopted.

| Challenge | Solution |
|  |  |
| Video Streamer instance has no public IP address | RTMP communication uses the Web instance's private IP; SSH access is provided through the bastion using `ProxyJump` |
| Package installation and video downloads from the private subnet | Added a NAT Gateway and a `0.0.0.0/0` route pointing to the NAT Gateway |
| DevopsLab account does not allow `iam:CreateRole` | Verified the restriction and configured `enable_dns01_iam = false` to use HTTP-01 instead of DNS-01 |
| Campus IP address changes | Introduced the configurable `admin_ssh_cidr_blocks` variable to avoid modifying the infrastructure code |
| Terraform and Ansible configuration synchronization | Terraform automatically regenerates `ansible/inventory.ini` after `tofu apply` |
| Validation before the final demonstration | Used `validate-streaming.yml` and manual playback tests with the Akamai player |

These solutions allowed the team to maintain a functional deployment despite the restrictions of the laboratory environment.



## 6\. Deployment Procedure

This section describes the commands required to provision the infrastructure, configure the application, and validate the streaming services.

### 6.1 Prerequisites

The following tools and resources are required:

- AWS CLI.
- OpenTofu.
- Ansible.
- SSH key pair.
- `glab` CLI for GitLab remote state initialization.
- Access to the AWS DevopsLab account.

### 6.2 Initialize the Remote Backend

Run the backend initialization script once:

bash

```bash
./terraform/init-backend.sh
```

This configures the GitLab remote state backend.

### 6.3 Configure Terraform Variables

For the DevopsLab environment, copy the example configuration and create the local variables file:

bash

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

The following setting is required:

hcl

```hcl
enable_dns01_iam = false
```

This disables the DNS-01 IAM deployment path and enables HTTP-01 certificate validation.

The `terraform.tfvars` file is ignored by Git and must be configured locally.

### 6.4 Provision AWS Infrastructure

From the repository root, execute:

bash

```bash
cd terraform

tofu init

tofu apply -var-file=terraform.tfvars

cd ..
```

This provisions the VPC, subnets, route tables, EC2 instances, security groups, Internet Gateway, NAT Gateway, Elastic IP, and Route 53 resources.

It also generates the Ansible inventory file.

### 6.5 Deploy the Application with Ansible

From the root of the `GIN207/` repository, execute:

bash

```bash
export ANSIBLE_CONFIG=ansible/ansible.cfg

ansible-playbook \
  -i ansible/inventory.ini \
  ansible/playbooks/deploy-all.yml
```

This playbook configures the Web Frontend and Video Streamer, deploys the streaming services, and configures the certificate.

### 6.6 Validate the Deployment

After deployment, execute:

bash

```bash
ansible-playbook \
  -i ansible/inventory.ini \
  ansible/playbooks/validate-streaming.yml
```

This checks the NGINX configuration, FFmpeg service, and HLS/DASH streaming endpoints.

### 6.7 DNS-01 Configuration on an AWS Account with IAM Permissions

The default configuration in `variables.tf` targets the original course architecture:

hcl

```hcl
enable_dns01_iam = true
```

However, DevopsLab does not permit the creation of IAM roles, as verified through the AWS CLI.

On an AWS account with the required IAM permissions, the following steps would be necessary:

1. Remove `enable_dns01_iam = false` from the local `terraform.tfvars` file or explicitly set it to `true`.
2. Execute `tofu apply` to create the IAM role and instance profile.
3. Run the certificate deployment playbook again.

bash

```bash
ansible-playbook \
  -i ansible/inventory.ini \
  ansible/playbooks/deploy-all.yml \
  --tags certificate
```

The operational instructions are also documented in:

- `README.md`
- `docs/architecture.md`



## 7\. Repository Structure

The repository is organized into infrastructure provisioning, application configuration, documentation, and CI pipeline components.

text

```text
GIN207/
|
├── terraform/                 # AWS infrastructure (OpenTofu)
│   ├── main.tf                # VPC, EC2, security groups, Route53, inventory
│   ├── iam.tf                 # IAM DNS-01 configuration
│   └── variables.tf           # Domain, SSH keys, enable_dns01_iam
│
├── ansible/
│   ├── playbooks/
│   │   ├── deploy-all.yml
│   │   └── validate-streaming.yml
│   │
│   └── roles/
│       ├── web/
│       └── streamer/
│
├── README.md                  # Project overview and deployment instructions
├── docs/
│   └── architecture.png
│
└── .github/workflows/validate.yml
```

### 7.1 Important Configuration Files

The following files contain the main implementation components:

| Component | File |
|  |  |
| Networking, EC2 instances, security groups, and DNS | `terraform/main.tf` |
| IAM configuration for Certbot DNS-01 | `terraform/iam.tf` |
| NGINX RTMP, HLS, and DASH configuration | `ansible/roles/web/templates/nginx.conf.j2` |
| HTTPS and Certbot configuration | `ansible/roles/web/tasks/certificate.yml` |
| Continuous RTMP streaming service | `ansible/roles/streamer/templates/ffmpeg-stream.service.j2` |

These files provide the starting point for understanding the infrastructure and application implementation.



## 8\. Overall Assessment and Conclusion

The project successfully implements the main objectives of the GIN207 assignment, including the deployment of a two-tier AWS architecture, infrastructure automation using OpenTofu, server configuration using Ansible, and a functional video streaming pipeline based on RTMP, HLS, and DASH.

The final implementation can be summarized as follows:

| Category | Result |
|  |  |
| **Course Objectives** | Two-tier architecture, Terraform-compatible infrastructure automation, Ansible configuration, RTMP-to-HLS/DASH streaming, and HTTPS access — achieved |
| **Technical Guide** | FFmpeg, NGINX, and streaming directory configuration reproduced through Ansible roles |
| **DNS-01 and IAM Architecture** | Implemented in code but not deployed because DevopsLab denies `iam:CreateRole` |
| **DASH Streaming** | Configuration corrections deployed (MIME types, playlist duration, and validation); HLS remains the preferred demonstration format |
| **Additional Improvements** | NAT Gateway, SSH bastion, systemd service, validation playbooks, GitLab CI, automatic inventory generation, and demonstration homepage |
| **Remaining Improvements** | AWS account with IAM permissions for DNS-01, dash.js compatibility, SSH and egress restrictions, and automated deployment through CI/CD |

Overall, the project delivers a **functional end-to-end video streaming application using HLS and HTTPS**. Infrastructure provisioning and application deployment are automated through OpenTofu and Ansible, while additional mechanisms improve service reliability and operational reproducibility.

The main deviation from the reference architecture concerns certificate validation: DNS-01 is implemented in the code but cannot be deployed in the DevopsLab environment because the AWS account does not allow IAM role creation. Consequently, HTTP-01 is used for the actual deployment, while HTTPS remains fully functional.

DASH generation and configuration have also been corrected and deployed. However, due to compatibility limitations in the `libnginx-mod-rtmp` module, HLS remains the most reliable format for the final demonstration.