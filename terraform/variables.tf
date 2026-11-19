variable "team_ssh_public_keys" {
  type        = list(string)
  description = "Additional team SSH public keys (appended to ssh_public_key_path on both EC2 instances)."
  default = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEHINQBHG1cftsZlY9Ylr49iJYvFMQzFXk759HyPxcqv suzyjin0418@gmail.com",
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC9RtRRK9sN03XHpymQkUGPOjo+eP9CWT4EMfJ1aQ0enwUg25AbXQH3Mr8EkimjhXpamGjNRSf3v510MKDcny45LbvHKAkhrlEulvxJsAzqBrzlrWyIITyTfEK4KBJ6BF9HDmURG3+8E+z3xFhbKlDrO7Ckytg70FC7zm+fUjyPkvnvYw6W3nfyw4xXTqfpq+tC85Psn6QyE9H7iY9xNS19CoKwMWrxuOssEZb4u4K//6gU2j4inFPB6jg+uFRHK/gTsMegphnKppyuIR1tamCg/yN8fN35JZM/8pV0/zMu4mNgIzDTO5jXAcs+np6ANKyB6r/cY8iZEbadbeNu/ecvc1WQyf5p1wDYDyDMIie1UmK2wf0L8GkrENG6DCq8EiP1f6OETnpkQFRDKn3JgJlrGdHUO/iLIVtfLsyyxXqyB46pqYsfMnzawpN9ZS8SaistMwxvAAtJ+8/Es8Rc+HRGgpJJWDQ25MD9FTjL/kxjHfwX0KSMOs+w9Scfi7BYXRHRntB7PSMsOZLgRIr6gFXGBjzLOwdOgVxsyJQglZftI8KFbZ7PZ+lQYvc+uYTJRoORMpRtpbfts0ATjBch12SVWIptP+ex/sPG0D46IONQOTNDpLkyN7xLqAyk3dWz3SO6hXdVTK127wFA3pdaQW2gyI+RpILr2anIsbNL1mk/cQ== kailani@DESKTOP-VTF2NDB",
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCmawRcG77SwkaV2MfVlF8ONQJV72Tik40+omd2xRTSRh4gKfa6DLduNHu9OIb53WM16KEjTmvQW2wVbIgngV4r7dH6GMRcnl6EFwei41ZUr17Hp3IkgHaCjPhCWQkwAyg6jNbLKusqpceSNj+eAuVknMOPXf1G//aCYZw1lRjJWCj4SW9dW9TP11dNPVJZneGdZiq5kr2g35VZBPTceKLgGsqtjgb8b9ii2dIF5NDt8IJ7RvZZ2wtVc4sdrLZNtnclWuH1zKdorbch0u8+egdWgdQ2oZqP05/T+WNoqoc7UdarkF+VTCxATNJP8aULngnKlwmRmrQK/1JLFuhRGu/jdmKPzuNAv7lKO3gEImmjvyrhdnDjVswo54buH0RwP/OFg7HSNEChraWMLCQEJuNeun6YET6SeLCZ4ALt7UPbT6+XdrVeqgTjgKQ2I23z+UovBKUMnKHF34uXMK3imR2tD1jmh3cbgn8OFJz/n3x+EnLWOoABtgyTu1wl1Z1kblH4sJzr6IGHsM0C0W4e3+iNK+OxpBEyZtFfl4FOcmCk0sQ5KxUK2Jcr/wO7AncQGo/OqKBGio+8GRtKGOw8DfF5MFC2i0fK43WtDx/OtIlW49KfN9CFSmNtf/fBYZOfum/2h0aWA2xTgdN9DcsFDizgulYgDg3AScBfrwfhN85A5Q== Kailani@MacBook-Air-2.local",
  ]
}

variable "admin_ssh_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks allowed to SSH (port 22) to the Web bastion. Do not use 0.0.0.0/0."
  default = [
    "137.194.0.0/16", # Telecom Paris campus — Person 3 (bingrui); campus IP changes often
    "80.125.0.74/32", # teammate
  ]
}

variable "certbot_email" {
  type        = string
  description = "Email for Let's Encrypt certificate notifications (used in generated Ansible inventory)."
  default     = "suzyjin0418@gmail.com"
}

variable "ansible_ssh_private_key_file" {
  type        = string
  description = "Path to the SSH private key Ansible uses (written into generated inventory)."
  default     = "~/.ssh/id_ed25519"
}

variable "ssh_public_key_path" {
  type        = string
  description = "Path to the SSH public key for the EC2 key pair."
  default     = "~/.ssh/id_ed25519.pub"
}

variable "route53_zone_id" {
  type        = string
  description = "Route53 hosted zone for devops.intuitivelabs.net (team zone)."
  default     = "Z05166941X8L62XTVC2QE"
}

variable "stream_domain" {
  type        = string
  description = "Public HTTPS hostname (A record in Route53)."
  default     = "teambkn.devops.intuitivelabs.net"
}

variable "enable_dns01_iam" {
  type        = bool
  description = "Create IAM role/instance profile for certbot DNS-01 (course architecture). Set false only if iam:CreateRole is denied on the deployer account."
  default     = true
}
