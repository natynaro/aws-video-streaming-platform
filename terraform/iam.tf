########################################
# IAM — Let's Encrypt DNS-01 via Route53 (optional; needs iam:CreateRole)
########################################

data "aws_iam_policy_document" "x_projectBKN_web_certbot_assume" {
  count = var.enable_dns01_iam ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "x_projectBKN_web_certbot" {
  count = var.enable_dns01_iam ? 1 : 0

  name               = "x-projectBKN-web-certbot"
  assume_role_policy = data.aws_iam_policy_document.x_projectBKN_web_certbot_assume[0].json

  tags = {
    Name = "x-projectBKN-web-certbot"
  }
}

data "aws_iam_policy_document" "x_projectBKN_web_certbot_route53" {
  count = var.enable_dns01_iam ? 1 : 0

  statement {
    sid    = "CertbotListZones"
    effect = "Allow"
    actions = [
      "route53:GetChange",
      "route53:ListHostedZones",
      "route53:ListHostedZonesByName",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "CertbotChangeTXT"
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets",
    ]
    resources = [
      "arn:aws:route53:::hostedzone/${var.route53_zone_id}",
    ]
  }
}

resource "aws_iam_role_policy" "x_projectBKN_web_certbot_route53" {
  count = var.enable_dns01_iam ? 1 : 0

  name   = "x-projectBKN-web-certbot-route53"
  role   = aws_iam_role.x_projectBKN_web_certbot[0].id
  policy = data.aws_iam_policy_document.x_projectBKN_web_certbot_route53[0].json
}

resource "aws_iam_instance_profile" "x_projectBKN_web_certbot" {
  count = var.enable_dns01_iam ? 1 : 0

  name = "x-projectBKN-web-certbot"
  role = aws_iam_role.x_projectBKN_web_certbot[0].name

  tags = {
    Name = "x-projectBKN-web-certbot"
  }
}
