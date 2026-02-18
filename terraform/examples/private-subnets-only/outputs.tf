output "bedrock_runtime_endpoint_id" {
  value = module.document_summarizer_bedrock.bedrock_runtime_endpoint_id
}

output "summarizer_role_arn" {
  value = module.document_summarizer_bedrock.summarizer_role_arn
}

output "app_security_group_id" {
  value = module.document_summarizer_bedrock.app_security_group_id
}

output "s3_gateway_endpoint_id" {
  value = module.document_summarizer_bedrock.s3_gateway_endpoint_id
}

output "kms_key_arn" {
  value = module.document_summarizer_bedrock.kms_key_arn
}

output "log_group_name" {
  value = module.document_summarizer_bedrock.log_group_name
}
