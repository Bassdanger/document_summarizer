variable "vpc_id" {
  description = "ID of your existing VPC (private subnets only, with NAT gateways)."
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs of the two (or more) private subnets."
  type        = list(string)
}

variable "private_route_table_ids" {
  description = "Route table IDs associated with the private subnets (for S3 gateway endpoint)."
  type        = list(string)
  default     = []
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
}

variable "aws_region" {
  description = "AWS region (must match VPC and where Bedrock is available)."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "name_prefix" {
  type    = string
  default = "doc-summarizer"
}

variable "enable_s3_gateway_endpoint" {
  description = "Create S3 gateway endpoint (set false if private_route_table_ids not provided)."
  type        = bool
  default     = true
}

variable "enable_bedrock_agent_endpoints" {
  type    = bool
  default = false
}

variable "app_ingress_cidrs" {
  description = "CIDR blocks allowed to reach the summarizer app (e.g. VPN)."
  type        = list(string)
  default     = []
}

variable "app_ingress_security_groups" {
  description = "Security group IDs allowed to reach the app (e.g. ALB)."
  type        = list(string)
  default     = []
}

variable "create_kms_key" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
