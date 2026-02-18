# ------------------------------------------------------------------------------
# VPC Endpoints
# ------------------------------------------------------------------------------

output "bedrock_endpoint_id" {
  description = "ID of the Bedrock control plane VPC interface endpoint."
  value       = aws_vpc_endpoint.bedrock.id
}

output "bedrock_runtime_endpoint_id" {
  description = "ID of the Bedrock runtime VPC interface endpoint (InvokeModel)."
  value       = aws_vpc_endpoint.bedrock_runtime.id
}

output "bedrock_endpoint_dns_entries" {
  description = "DNS entries for the Bedrock runtime endpoint (private DNS enabled)."
  value       = aws_vpc_endpoint.bedrock_runtime.dns_entry
}

output "s3_gateway_endpoint_id" {
  description = "ID of the S3 gateway endpoint (if created)."
  value       = try(aws_vpc_endpoint.s3[0].id, null)
}

output "textract_endpoint_id" {
  description = "ID of the Textract VPC interface endpoint (PDF extraction)."
  value       = aws_vpc_endpoint.textract.id
}

# ------------------------------------------------------------------------------
# Security groups
# ------------------------------------------------------------------------------

output "vpc_endpoints_security_group_id" {
  description = "Security group ID attached to Bedrock (and other) VPC interface endpoints."
  value       = aws_security_group.vpc_endpoints.id
}

output "app_security_group_id" {
  description = "Security group ID for the document summarizer app (if created)."
  value       = try(aws_security_group.app[0].id, null)
}

# ------------------------------------------------------------------------------
# IAM
# ------------------------------------------------------------------------------

output "summarizer_role_arn" {
  description = "ARN of the IAM role for the document summarizer app (attach to ECS task, Lambda, etc.)."
  value       = aws_iam_role.summarizer.arn
}

output "summarizer_role_name" {
  description = "Name of the IAM role for the document summarizer app."
  value       = aws_iam_role.summarizer.name
}

# ------------------------------------------------------------------------------
# KMS (optional)
# ------------------------------------------------------------------------------

output "kms_key_arn" {
  description = "ARN of the KMS key for encryption (if created)."
  value       = try(aws_kms_key.summarizer[0].arn, null)
}

output "kms_key_id" {
  description = "ID of the KMS key (if created)."
  value       = try(aws_kms_key.summarizer[0].key_id, null)
}
