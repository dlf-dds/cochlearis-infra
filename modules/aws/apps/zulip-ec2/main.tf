# Zulip EC2 Module
#
# Deploys Zulip on an EC2 instance using the standard installation script.
# This is the recommended approach after determining ECS Fargate is not
# compatible with Zulip's multi-process architecture.
#
# See gotchas.md "Zulip Cannot Run Self-Contained in ECS Fargate" for details.

locals {
  name_prefix    = "${var.project}-${var.environment}"
  domain         = "chat.${var.environment}.${var.domain_name}"
  google_enabled = var.google_client_id != "" && var.google_client_secret_arn != ""
  azure_enabled  = var.azure_client_id != "" && var.azure_client_secret_arn != "" && var.azure_tenant_id != ""
  smtp_enabled   = var.smtp_from_email != ""
}

# SSL Certificate
module "certificate" {
  source = "../../acm-certificate"

  project     = var.project
  environment = var.environment
  domain_name = local.domain
  zone_id     = var.route53_zone_id
}

# Add certificate to ALB
resource "aws_lb_listener_certificate" "main" {
  listener_arn    = var.alb_listener_arn
  certificate_arn = module.certificate.validation_certificate_arn
}

# Route53 record - points to ALB
resource "aws_route53_record" "main" {
  zone_id = var.route53_zone_id
  name    = local.domain
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

# Random suffix for secret names
resource "random_id" "secret_suffix" {
  byte_length = 4
}

# Generate random admin password
resource "random_password" "admin_password" {
  length  = 24
  special = false
}

# Store credentials in Secrets Manager
resource "aws_secretsmanager_secret" "zulip" {
  name        = "${local.name_prefix}-zulip-ec2-secrets-${random_id.secret_suffix.hex}"
  description = "Zulip EC2 credentials"

  tags = {
    Name = "${local.name_prefix}-zulip-ec2-secrets"
  }
}

resource "aws_secretsmanager_secret_version" "zulip" {
  secret_id = aws_secretsmanager_secret.zulip.id
  secret_string = jsonencode({
    admin_email    = var.admin_email
    admin_password = random_password.admin_password.result
  })
}

# SES SMTP user for email notifications
module "ses_user" {
  count  = local.smtp_enabled ? 1 : 0
  source = "../../ses-smtp-user"

  name = "${local.name_prefix}-zulip-ses"
  tags = {
    Name = "${local.name_prefix}-zulip-ses"
  }
}

# IAM role for EC2 instance
resource "aws_iam_role" "zulip" {
  name = "${local.name_prefix}-zulip-ec2"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-zulip-ec2"
  }
}

# Attach SSM policy for Systems Manager access
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.zulip.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Allow reading secrets
resource "aws_iam_role_policy" "secrets" {
  name = "${local.name_prefix}-zulip-secrets"
  role = aws_iam_role.zulip.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = concat(
          [aws_secretsmanager_secret.zulip.arn],
          local.google_enabled ? [var.google_client_secret_arn] : [],
          local.azure_enabled ? [var.azure_client_secret_arn] : [],
          local.smtp_enabled ? [module.ses_user[0].smtp_credentials_secret_arn] : []
        )
      }
    ]
  })
}

resource "aws_iam_instance_profile" "zulip" {
  name = "${local.name_prefix}-zulip-ec2"
  role = aws_iam_role.zulip.name
}

# Security group for the EC2 instance
resource "aws_security_group" "zulip" {
  name        = "${local.name_prefix}-zulip-ec2"
  description = "Security group for Zulip EC2 instance"
  vpc_id      = var.vpc_id

  # HTTP from ALB
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
    description     = "HTTP from ALB"
  }

  # HTTPS from ALB (in case Zulip handles TLS)
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
    description     = "HTTPS from ALB"
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name = "${local.name_prefix}-zulip-ec2"
  }
}

# Get latest Ubuntu 22.04 AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# User data script for Zulip installation
locals {
  user_data = <<-EOF
#!/bin/bash
set -e

# Log everything
exec > >(tee /var/log/zulip-install.log) 2>&1
echo "Starting Zulip installation at $(date)"

# Create swap space (required for instances with < 5GB RAM)
echo "Creating 2GB swap file..."
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
echo "Swap configured:"
free -h

# Update system
apt-get update
apt-get upgrade -y

# Install dependencies
apt-get install -y wget curl jq awscli

# Get secrets from Secrets Manager
export AWS_DEFAULT_REGION="${var.region}"
SECRETS=$(aws secretsmanager get-secret-value --secret-id "${aws_secretsmanager_secret.zulip.arn}" --query SecretString --output text)
ADMIN_EMAIL=$(echo $SECRETS | jq -r '.admin_email')
ADMIN_PASSWORD=$(echo $SECRETS | jq -r '.admin_password')

# Download Zulip
cd /tmp
wget https://download.zulip.com/server/zulip-server-latest.tar.gz
tar -xf zulip-server-latest.tar.gz

# Install Zulip with standard installation
# Use --self-signed-cert since ALB handles TLS termination
cd zulip-server-*/
./scripts/setup/install --hostname="${local.domain}" --email="$ADMIN_EMAIL" --self-signed-cert

# Configure loadbalancer in zulip.conf (following vanilla docs)
# See: https://zulip.readthedocs.io/en/latest/production/reverse-proxies.html
cat >> /etc/zulip/zulip.conf <<ZULIPCONF

[loadbalancer]
ips = ${var.vpc_cidr}
ZULIPCONF

# Configure Zulip settings
cat >> /etc/zulip/settings.py <<'SETTINGS'

# SSL handled by ALB
EXTERNAL_HOST = "${local.domain}"
ALLOWED_HOSTS = ["${local.domain}"]

# Behind load balancer (trust ALB proxy headers)
USE_X_FORWARDED_HOST = True
SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')
LOADBALANCER_IPS = ["${var.vpc_cidr}"]

# Allow organization creation
OPEN_REALM_CREATION = True
SETTINGS

# Configure OAuth if enabled
%{ if local.azure_enabled }
AZURE_SECRET=$(aws secretsmanager get-secret-value --secret-id "${var.azure_client_secret_arn}" --query SecretString --output text | jq -r '.client_secret')
cat >> /etc/zulip/settings.py <<AZURE
# Azure AD OAuth
SOCIAL_AUTH_AZUREAD_OAUTH2_KEY = "${var.azure_client_id}"
SOCIAL_AUTH_AZUREAD_OAUTH2_SECRET = "$AZURE_SECRET"
AUTHENTICATION_BACKENDS = (
    'zproject.backends.AzureADAuthBackend',
    'zproject.backends.EmailAuthBackend',
)
AZURE
%{ endif }

%{ if local.google_enabled && !local.azure_enabled }
GOOGLE_SECRET=$(aws secretsmanager get-secret-value --secret-id "${var.google_client_secret_arn}" --query SecretString --output text | jq -r '.client_secret')
cat >> /etc/zulip/settings.py <<GOOGLE
# Google OAuth
SOCIAL_AUTH_GOOGLE_OAUTH2_KEY = "${var.google_client_id}"
SOCIAL_AUTH_GOOGLE_OAUTH2_SECRET = "$GOOGLE_SECRET"
AUTHENTICATION_BACKENDS = (
    'zproject.backends.GoogleAuthBackend',
    'zproject.backends.EmailAuthBackend',
)
GOOGLE
%{ endif }

%{ if local.smtp_enabled }
# Configure email via SES
SMTP_CREDS=$(aws secretsmanager get-secret-value --secret-id "${module.ses_user[0].smtp_credentials_secret_arn}" --query SecretString --output text)
SMTP_USER=$(echo $SMTP_CREDS | jq -r '.username')
SMTP_PASS=$(echo $SMTP_CREDS | jq -r '.password')

cat >> /etc/zulip/settings.py <<EMAIL
# Email configuration (AWS SES)
EMAIL_HOST = "${module.ses_user[0].smtp_endpoint}"
EMAIL_HOST_USER = "$SMTP_USER"
EMAIL_USE_TLS = True
EMAIL_PORT = 587
ADD_TOKENS_TO_NOREPLY_ADDRESS = True
TOKENIZED_NOREPLY_EMAIL_ADDRESS = "noreply-{token}@${var.domain_name}"
NOREPLY_EMAIL_ADDRESS = "${var.smtp_from_email}"
DEFAULT_FROM_EMAIL = "${var.smtp_from_name} <${var.smtp_from_email}>"
EMAIL

# Store SMTP password in zulip-secrets.conf (per Zulip docs)
echo "email_password = $SMTP_PASS" >> /etc/zulip/zulip-secrets.conf
%{ endif }

# Regenerate nginx config using puppet (follows vanilla Zulip docs)
# This creates the proper config based on [loadbalancer] in zulip.conf
/home/zulip/deployments/current/scripts/zulip-puppet-apply -f

# Initialize the database
su zulip -c '/home/zulip/deployments/current/scripts/setup/initialize-database'

# Restart services
su zulip -c '/home/zulip/deployments/current/scripts/restart-server'

echo "Zulip installation completed at $(date)"
echo "Access at: https://${local.domain}"
EOF
}

# EC2 Instance
resource "aws_instance" "zulip" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  iam_instance_profile   = aws_iam_instance_profile.zulip.name
  vpc_security_group_ids = [aws_security_group.zulip.id]
  subnet_id              = var.private_subnet_id

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  user_data = base64encode(local.user_data)

  tags = {
    Name = "${local.name_prefix}-zulip"
  }

  lifecycle {
    ignore_changes = [ami] # Don't recreate on new AMI
  }
}

# ALB Target Group
resource "aws_lb_target_group" "zulip" {
  name        = "${local.name_prefix}-zulip-ec2"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200-399,400"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${local.name_prefix}-zulip-ec2"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Register EC2 instance with target group
resource "aws_lb_target_group_attachment" "zulip" {
  target_group_arn = aws_lb_target_group.zulip.arn
  target_id        = aws_instance.zulip.id
  port             = 80
}

# ALB Listener Rule
resource "aws_lb_listener_rule" "zulip" {
  listener_arn = var.alb_listener_arn
  priority     = var.listener_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.zulip.arn
  }

  condition {
    host_header {
      values = [local.domain]
    }
  }
}
