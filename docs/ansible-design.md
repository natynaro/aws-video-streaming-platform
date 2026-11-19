# Ansible Configuration Implementation

## Purpose of the Ansible folder

The `ansible/` folder is responsible for configuring the infrastructure created by Terraform. While Terraform provisions AWS resources (EC2, networking, DNS), Ansible installs software, configures services, and sets up the streaming pipeline inside the instances.

The folder is structured as follows:

```text
ansible/
├── ansible.cfg
├── inventory.example
├── video_streamer.yml
├── group_vars/
├── playbooks/
└── roles/
    ├── web/
    └── streamer/
```

The configuration follows a modular approach using **roles** and **playbooks**, allowing each part of the system to be deployed independently or as part of a full pipeline.

***

## What was required by the project diagram

According to the architecture, the Ansible configuration had to:

* Configure the **Web Frontend**:
  * install NGINX
  * install RTMP module
  * receive RTMP stream
  * generate HLS and DASH
  * serve stream over HTTP/HTTPS
* Configure the **Video Streamer**:
  * install FFmpeg
  * stream video continuously via RTMP
* Implement the streaming pipeline:

```text
Video Streamer → RTMP → Web Frontend → HLS/DASH → Users
```

* Configure HTTPS:
  * obtain Let's Encrypt certificate
  * use DNS‑01 validation via Route53
* Ensure automation:
  * no manual configuration steps
  * reproducible execution through playbooks

***

## What is currently implemented

The Ansible implementation successfully configures the system according to the requirements.

***

### Role-based structure

Ansible uses two roles:

```text
roles/
├── web
└── streamer
```

Each role is responsible for one part of the architecture.

***

### Web Frontend configuration

The Web role installs required packages:

```yaml
- nginx
- libnginx-mod-rtmp
- ffmpeg
```

The streaming directories are created:

```yaml
/var/www/html/stream/
/var/www/html/stream/hls
/var/www/html/stream/dash
```

The NGINX RTMP configuration is deployed:

```nginx
rtmp {
    server {
        listen 1935;

        application live {
            live on;

            hls on;
            dash on;
        }
    }
}
```

This enables ingestion of RTMP and generation of HLS/DASH segments.

The Web Frontend exposes content through:

```text
/hls  → HLS playlist
/dash → DASH manifest
```

***

### Video Streamer configuration

The streamer role installs FFmpeg:

```yaml
- name: Install ffmpeg
  apt:
    name: ffmpeg
```

A sample video is downloaded:

```yaml
url: "{{ sample_video_url }}"
```

The streaming pipeline is implemented through a systemd service:

```ini
ExecStart=/usr/bin/ffmpeg -stream_loop -1 -re \
  -i /videos/BigBuckBunny_320x180.mp4 \
  -f flv rtmp://<web-ip>:1935/live/stream
```

This ensures the video is continuously streamed to the Web Frontend.

***

### HTTPS and DNS automation

The certificate configuration supports two modes:

```yaml
certbot_challenge: dns-route53 | webroot
```

For the required architecture, DNS‑01 is used:

```yaml
certbot certonly --dns-route53
```

This relies on IAM permissions provided by Terraform.

The certificate acquisition process follows:

```text
1. Certbot requests certificate
2. Route53 TXT record created
3. Let's Encrypt validates domain
4. Certificate installed
```

The NGINX HTTPS configuration is then applied:

```nginx
listen 443 ssl;
ssl_certificate ...
ssl_certificate_key ...
```

This enables users to access the service securely:

```text
https://<domain>
```

***

### Playbook orchestration

The system uses multiple playbooks organized under `playbooks/`.

The full deployment is orchestrated via:

```yaml
deploy-all.yml
```

which includes:

```yaml
- web-setup.yml
- deploy-certificate.yml
- deploy-website.yml
- streamer-setup.yml
- validate-streaming.yml
```

This ensures the correct execution order:

```text
1. Configure Web Frontend
2. Configure HTTPS
3. Deploy website
4. Configure Video Streamer
5. Validate system
```

***

### Validation playbook

A validation playbook ensures the system is functioning:

```yaml
- Check HLS endpoint
- Check DASH endpoint
- Verify nginx service
- Verify ffmpeg-stream service
```

Example:

```yaml
- name: Check HLS playlist
  uri:
    url: "https://{{ domain }}/hls/stream.m3u8"
```

This confirms the streaming pipeline is active.

***

### Bastion / ProxyJump configuration

Access to the private instance is configured using:

```ini
ansible_ssh_common_args=-o ProxyJump=ubuntu@<web_public_ip>
```

This implements the required architecture where the Web Frontend acts as a bastion host.

***

## Extra elements beyond requirements

Several improvements were added beyond the base requirements.

***

### Persistent FFmpeg service

Instead of manually running FFmpeg, a systemd service is used:

```ini
Restart=always
```

This ensures:

* automatic restart on failure
* continuous streaming
* no manual intervention

***

### Dedicated streaming user

A dedicated user is created:

```yaml
- name: Create dedicated streamer system user
```

and used in the service:

```ini
User={{ ffmpeg_stream_user }}
```

This improves security compared to running as root.

***

### Flexible certificate mode

The system supports both:

```text
dns-route53 → correct architecture
webroot     → fallback mode
```

This improves compatibility with environments where IAM creation is restricted.

***

### Parameterized configuration

Values are dynamically passed from Terraform:

```ini
rtmp_publish_allow_cidr
web_frontend_private_ip
certbot_challenge
```

This avoids hardcoding and improves maintainability.

***

### Deployment orchestration

The use of multiple playbooks with `deploy-all.yml` provides:

* modular execution
* reproducibility
* clear separation of responsibilities

***

### Validation automation

The presence of a validation playbook ensures that:

* services are running
* endpoints are reachable

This is not required but is very good DevOps practice.

***

## Current issues and future improvements

The implementation is correct, but some improvements can be made.

***

### 1. HTML formatting inside files (critical to verify)

Some values appear as:

```text
https://...
```

Instead of:

```text
https://...
```

This must be corrected in:

* inventory
* templates
* variables

Otherwise Ansible, NGINX or FFmpeg may fail.

***

### 2. Validation assumes HTTPS only

The validation playbook uses:

```yaml
https://{{ domain }}
```

If HTTPS is not correctly configured, validation may fail.

Improvement:

```text
Support fallback or allow disabling certificate validation
```

***

### 3. Certificate mode flexibility vs requirements

Although both modes are supported:

```yaml
dns-route53 | webroot
```

only `dns-route53` satisfies the project diagram.

Improvement:

```text
Ensure dns-route53 is enforced for final deployment
```

***

### 4. HTTP (port 80) still present

The configuration keeps HTTP for redirect:

```nginx
return 301 https://...
```

This is acceptable but optional in DNS‑01 setups.

***

### 5. Minor duplication in playbooks

There is duplication:

```text
deploy-website.yml (appears twice)
```

This does not break execution but should be cleaned.

***

### 6. System assumptions

The playbooks assume:

* Ubuntu-based images
* package availability via apt
* default paths (/var/www/html)

This is acceptable but reduces portability.

***

## Final Ansible evaluation

The Ansible implementation correctly configures the system and fully supports the architecture defined by the project.

It successfully:

* configures both EC2 instances
* implements the RTMP → HLS/DASH pipeline
* enables HTTPS using DNS‑01 Route53
* automates deployment through structured playbooks
* validates system availability

The system is fully functional and aligned with the diagram when `certbot_challenge = dns-route53`.

At the same time, several improvements make the implementation more robust than the base requirements, including service persistence, validation automation, modular deployment, and dynamic configuration.

The remaining issues are mostly minor and do not affect compliance with the architecture, but should be considered for production-quality refinement.
