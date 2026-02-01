# EFS Module
#
# Creates an EFS filesystem with mount targets for use with ECS Fargate

locals {
  name_prefix = "${var.project}-${var.environment}"
}

resource "aws_efs_file_system" "main" {
  creation_token = "${local.name_prefix}-${var.name}"
  encrypted      = true

  performance_mode                = var.performance_mode
  throughput_mode                 = var.throughput_mode
  provisioned_throughput_in_mibps = var.throughput_mode == "provisioned" ? var.provisioned_throughput_in_mibps : null

  lifecycle_policy {
    transition_to_ia = var.transition_to_ia
  }

  tags = {
    Name = "${local.name_prefix}-${var.name}"
  }
}

resource "aws_security_group" "efs" {
  name        = "${local.name_prefix}-${var.name}-efs-sg"
  description = "Security group for EFS mount targets"
  vpc_id      = var.vpc_id

  ingress {
    description     = "NFS from allowed security groups"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-${var.name}-efs-sg"
  }
}

resource "aws_efs_mount_target" "main" {
  count = length(var.subnet_ids)

  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = var.subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_access_point" "main" {
  file_system_id = aws_efs_file_system.main.id

  posix_user {
    gid = var.posix_user_gid
    uid = var.posix_user_uid
  }

  root_directory {
    path = var.root_directory_path

    creation_info {
      owner_gid   = var.posix_user_gid
      owner_uid   = var.posix_user_uid
      permissions = var.root_directory_permissions
    }
  }

  tags = {
    Name = "${local.name_prefix}-${var.name}-ap"
  }
}
