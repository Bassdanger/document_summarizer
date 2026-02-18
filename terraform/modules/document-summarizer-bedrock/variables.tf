# ------------------------------------------------------------------------------
# Network (existing private-only VPC; no public subnets / no IGW)
# ------------------------------------------------------------------------------

variable "vpc_id" {
  description = "ID of the existing VPC (private subnets only, with NAT gateways for outbound)."
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs (e.g. two subnets across AZs). Used for VPC interface endpoints and optional app placement."
  type        = list(string)
  validation {
    condition     = length(var.private_subnet_ids) >= 1
    error_message = "At least one private subnet ID is required."
  }
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC. Used for security group rules (e.g. allow HTTPS from VPC to endpoints)."
  type        = string
}

# ------------------------------------------------------------------------------
# Region and environment
# ------------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region (used for Bedrock VPC endpoint service names)."
  type        = string
}

variable "environment" {
  description = "Environment name (e.g. dev, staging, prod) for naming and tagging."
  type        = string
  default     = "prod"
}

variable "name_prefix" {
  description = "Prefix for resource names (e.g. project or team name)."
  type        = string
  default     = "doc-summarizer"
}

# ------------------------------------------------------------------------------
# VPC endpoints and security
# ------------------------------------------------------------------------------

variable "enable_bedrock_agent_endpoints" {
  description = "Create VPC endpoints for Bedrock Agents (bedrock-agent, bedrock-agent-runtime). Set true if using Agents for summarization."
  type        = bool
  default     = false
}

variable "enable_s3_gateway_endpoint" {
  description = "Create S3 gateway endpoint so document read/write stays within AWS network (no NAT)."
  type        = bool
  default     = true
}

variable "private_route_table_ids" {
  description = "Route table IDs for private subnets (used for S3 gateway endpoint). Required when enable_s3_gateway_endpoint is true."
  type        = list(string)
  default     = []
}

variable "restrict_bedrock_endpoint_policy" {
  description = "If true, attach a minimal endpoint policy to bedrock-runtime (InvokeModel* only). Improves compliance posture."
  type        = bool
  default     = true
}

# ------------------------------------------------------------------------------
# Optional: security group for the summarizer app
# ------------------------------------------------------------------------------

variable "create_app_security_group" {
  description = "Create a security group for the document summarizer app (e.g. ECS tasks, Lambda, App Runner)."
  type        = bool
  default     = true
}

variable "app_ingress_cidrs" {
  description = "CIDR blocks allowed to reach the document summarizer app (e.g. internal ALB or VPN). Empty list = no ingress."
  type        = list(string)
  default     = []
}

variable "app_ingress_security_groups" {
  description = "Security group IDs allowed to reach the document summarizer app (e.g. ALB SG)."
  type        = list(string)
  default     = []
}

variable "app_ingress_ports" {
  description = "Ports to open for app ingress (e.g. [80, 443] for HTTP/HTTPS)."
  type        = list(number)
  default     = [443]
}

# ------------------------------------------------------------------------------
# CloudWatch Logs (compliance / audit)
# ------------------------------------------------------------------------------

variable "create_cloudwatch_log_group" {
  description = "Create a CloudWatch log group for the summarizer app (audit and compliance logging)."
  type        = bool
  default     = true
}

variable "log_group_retention_days" {
  description = "Retention in days for the summarizer log group (0 = never expire)."
  type        = number
  default     = 90
}

variable "log_group_kms_key_id" {
  description = "Optional KMS key ID/ARN to encrypt the log group. Omit for default encryption."
  type        = string
  default     = null
}

variable "enable_logs_vpc_endpoint" {
  description = "Create CloudWatch Logs VPC endpoint so logs stay private (no NAT)."
  type        = bool
  default     = true
}

# ------------------------------------------------------------------------------
# Optional: KMS for encryption (compliance)
# ------------------------------------------------------------------------------

variable "create_kms_key" {
  description = "Create a customer-managed KMS key for encrypting summarizer data (e.g. S3, Bedrock)."
  type        = bool
  default     = false
}

variable "kms_key_deletion_window_days" {
  description = "Deletion window in days for the KMS key when destroyed."
  type        = number
  default     = 7
}

# ------------------------------------------------------------------------------
# Tags
# ------------------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}
