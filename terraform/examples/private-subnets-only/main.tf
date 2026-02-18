# ------------------------------------------------------------------------------
# Example: Document summarizer Bedrock module in a private-only VPC
# (No public subnets, no IGW — two private subnets with NAT gateways)
# ------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.0" }
  }
}

provider "aws" {
  region = var.aws_region
}

# ------------------------------------------------------------------------------
# Pass your existing VPC and private subnet IDs (no public subnets / no IGW)
# ------------------------------------------------------------------------------

module "document_summarizer_bedrock" {
  source = "../../modules/document-summarizer-bedrock"

  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids
  vpc_cidr           = var.vpc_cidr
  aws_region         = var.aws_region
  environment        = var.environment
  name_prefix        = var.name_prefix

  # S3 gateway endpoint: route tables used by your private subnets
  enable_s3_gateway_endpoint = var.enable_s3_gateway_endpoint
  private_route_table_ids    = var.private_route_table_ids

  # Restrict Bedrock runtime endpoint to InvokeModel* (compliance)
  restrict_bedrock_endpoint_policy = true

  # Optional: Bedrock Agents (set to true if using Agents for summarization)
  enable_bedrock_agent_endpoints = var.enable_bedrock_agent_endpoints

  # App security group: who can reach the summarizer (e.g. ALB SG or VPN CIDRs)
  create_app_security_group   = true
  app_ingress_cidrs          = var.app_ingress_cidrs
  app_ingress_security_groups = var.app_ingress_security_groups
  app_ingress_ports          = [80, 443]

  # Optional: customer-managed KMS for encryption
  create_kms_key = var.create_kms_key

  tags = var.tags
}
