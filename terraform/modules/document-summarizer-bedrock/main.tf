# ------------------------------------------------------------------------------
# Local names and tags
# ------------------------------------------------------------------------------

locals {
  name = "${var.name_prefix}-${var.environment}"
  common_tags = merge(var.tags, {
    Module    = "document-summarizer-bedrock"
    Terraform = "true"
  })
}

# ------------------------------------------------------------------------------
# Security group for VPC interface endpoints (Bedrock, etc.)
# ------------------------------------------------------------------------------

resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${local.name}-endpoints-"
  description = "Security group for Bedrock and other VPC interface endpoints (document summarizer)."
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from VPC (private subnets)."
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound (endpoint ENIs are managed by AWS)."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name}-vpc-endpoints" })

  lifecycle {
    create_before_destroy = true
  }
}

# ------------------------------------------------------------------------------
# VPC Interface Endpoints for Amazon Bedrock (PrivateLink; no IGW/NAT needed)
# ------------------------------------------------------------------------------

# Control plane (e.g. ListFoundationModels, GetFoundationModel)
resource "aws_vpc_endpoint" "bedrock" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.bedrock"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, { Name = "${local.name}-bedrock" })
}

# Runtime (InvokeModel, InvokeModelWithResponseStream) — required for summarization
resource "aws_vpc_endpoint" "bedrock_runtime" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.bedrock-runtime"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  policy              = var.restrict_bedrock_endpoint_policy ? data.aws_iam_policy_document.bedrock_runtime_endpoint[0].json : null

  tags = merge(local.common_tags, { Name = "${local.name}-bedrock-runtime" })
}

data "aws_iam_policy_document" "bedrock_runtime_endpoint" {
  count = var.restrict_bedrock_endpoint_policy ? 1 : 0

  statement {
    sid    = "AllowInvokeModel"
    effect = "Allow"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream"
    ]
    resources = ["*"]
  }
}

# Optional: Bedrock Agents (build-time and runtime)
resource "aws_vpc_endpoint" "bedrock_agent" {
  count = var.enable_bedrock_agent_endpoints ? 1 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.bedrock-agent"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, { Name = "${local.name}-bedrock-agent" })
}

resource "aws_vpc_endpoint" "bedrock_agent_runtime" {
  count = var.enable_bedrock_agent_endpoints ? 1 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.bedrock-agent-runtime"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, { Name = "${local.name}-bedrock-agent-runtime" })
}

# ------------------------------------------------------------------------------
# VPC Interface Endpoint for Amazon Textract (PDF text extraction)
# ------------------------------------------------------------------------------

resource "aws_vpc_endpoint" "textract" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.textract"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, { Name = "${local.name}-textract" })
}

# ------------------------------------------------------------------------------
# S3 Gateway Endpoint (keeps S3 traffic in AWS; no NAT required)
# ------------------------------------------------------------------------------

resource "aws_vpc_endpoint" "s3" {
  count = var.enable_s3_gateway_endpoint && length(var.private_route_table_ids) > 0 ? 1 : 0

  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.private_route_table_ids

  tags = merge(local.common_tags, { Name = "${local.name}-s3" })
}

# ------------------------------------------------------------------------------
# Optional: Security group for the document summarizer app
# ------------------------------------------------------------------------------

resource "aws_security_group" "app" {
  count = var.create_app_security_group ? 1 : 0

  name_prefix = "${local.name}-app-"
  description = "Security group for document summarizer app (e.g. ECS, Lambda, App Runner)."
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = length(var.app_ingress_cidrs) > 0 || length(var.app_ingress_security_groups) > 0 ? var.app_ingress_ports : []
    content {
      description     = "App port ${ingress.value}"
      from_port       = ingress.value
      to_port         = ingress.value
      protocol        = "tcp"
      cidr_blocks     = length(var.app_ingress_cidrs) > 0 ? var.app_ingress_cidrs : null
      security_groups = length(var.app_ingress_security_groups) > 0 ? var.app_ingress_security_groups : null
    }
  }

  egress {
    description = "Outbound HTTPS (VPC endpoints, NAT for AWS APIs)."
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name}-app" })

  lifecycle {
    create_before_destroy = true
  }
}

# ------------------------------------------------------------------------------
# IAM role for the document summarizer (assumable by ECS, Lambda, etc.)
# ------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_iam_role" "summarizer" {
  name_prefix        = "${var.name_prefix}-${var.environment}-"
  assume_role_policy = data.aws_iam_policy_document.summarizer_assume.json
  description        = "Role for document summarizer app (Bedrock, S3, Textract)."

  tags = local.common_tags
}

data "aws_iam_policy_document" "summarizer_assume" {
  statement {
    sid     = "AllowECSAndLambda"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = [
        "ecs-tasks.amazonaws.com",
        "lambda.amazonaws.com",
        "ec2.amazonaws.com"
      ]
    }
  }
}

resource "aws_iam_role_policy" "summarizer_bedrock_s3" {
  name_prefix = "${var.name_prefix}-bedrock-s3-"
  role        = aws_iam_role.summarizer.id
  policy      = data.aws_iam_policy_document.summarizer_bedrock_s3.json
}

data "aws_iam_policy_document" "summarizer_bedrock_s3" {
  statement {
    sid       = "BedrockInvoke"
    effect    = "Allow"
    actions   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = ["*"]
  }

  statement {
    sid    = "BedrockListModels"
    effect = "Allow"
    actions = [
      "bedrock:ListFoundationModels",
      "bedrock:GetFoundationModel"
    ]
    resources = ["*"]
  }

  statement {
    sid       = "S3Documents"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
    resources = ["*"]
  }

  statement {
    sid       = "TextractPDF"
    effect    = "Allow"
    actions   = [
      "textract:DetectDocumentText",
      "textract:StartDocumentTextDetection",
      "textract:GetDocumentTextDetection"
    ]
    resources = ["*"]
  }

  statement {
    sid       = "CloudWatchLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }
}

# Optional: grant KMS decrypt/encrypt if customer key is used
resource "aws_iam_role_policy" "summarizer_kms" {
  count = var.create_kms_key ? 1 : 0

  name_prefix = "${var.name_prefix}-kms-"
  role        = aws_iam_role.summarizer.id
  policy      = data.aws_iam_policy_document.summarizer_kms[0].json
}

data "aws_iam_policy_document" "summarizer_kms" {
  count = var.create_kms_key ? 1 : 0

  statement {
    sid       = "KMSEncryptDecrypt"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.summarizer[0].arn]
  }
}

# ------------------------------------------------------------------------------
# Optional: KMS key for encryption at rest (compliance)
# ------------------------------------------------------------------------------

resource "aws_kms_key" "summarizer" {
  count = var.create_kms_key ? 1 : 0

  description             = "KMS key for document summarizer (Bedrock/S3 encryption)."
  deletion_window_in_days = var.kms_key_deletion_window_days
  enable_key_rotation     = true

  tags = merge(local.common_tags, { Name = "${local.name}-kms" })
}

resource "aws_kms_alias" "summarizer" {
  count = var.create_kms_key ? 1 : 0

  name          = "alias/${local.name}"
  target_key_id = aws_kms_key.summarizer[0].key_id
}
