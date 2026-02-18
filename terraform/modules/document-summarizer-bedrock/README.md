# Document Summarizer (Bedrock) — Terraform Module

Terraform module to deploy a **secure, compliant** document summarizer stack using **Amazon Bedrock** in an AWS environment with **private subnets only** (no public subnets, no Internet Gateway). Traffic to Bedrock and S3 stays on the AWS network via **VPC endpoints** (PrivateLink and S3 Gateway).

## Features

- **Private-only networking**: Uses VPC interface endpoints for Bedrock (and optional S3 gateway endpoint) so no IGW or NAT is required for Bedrock/S3 traffic.
- **Compliance-friendly**: Optional restricted VPC endpoint policy (InvokeModel only), optional KMS key, least-privilege IAM role.
- **Team-ready**: Parameterized for different environments and naming; optional app security group and route table association for S3.

## Prerequisites

- Existing VPC with **two (or more) private subnets** and **NAT gateways** for any outbound internet (e.g. CloudWatch, other APIs).
- No public subnets or IGW required for Bedrock/S3 if you use the provided VPC endpoints.

## Usage

```hcl
module "document_summarizer_bedrock" {
  source = "../../modules/document-summarizer-bedrock"

  vpc_id               = "vpc-xxxxx"
  private_subnet_ids   = ["subnet-aaaa", "subnet-bbbb"]
  vpc_cidr             = "10.0.0.0/16"
  aws_region           = "us-east-1"
  environment          = "prod"
  name_prefix          = "doc-summarizer"

  # S3 gateway endpoint (recommended): pass route tables used by private subnets
  enable_s3_gateway_endpoint = true
  private_route_table_ids    = ["rtb-xxxx", "rtb-yyyy"]

  # Optional: allow traffic to your app (e.g. from ALB)
  create_app_security_group = true
  app_ingress_security_groups = [aws_security_group.alb.id]
  app_ingress_ports         = [80, 443]

  # Optional: compliance
  restrict_bedrock_endpoint_policy = true
  create_kms_key                   = true

  tags = {
    Project = "DocumentSummarizer"
  }
}
```

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `vpc_id` | ID of the existing VPC | `string` | required |
| `private_subnet_ids` | Private subnet IDs (for interface endpoints) | `list(string)` | required |
| `vpc_cidr` | VPC CIDR (for endpoint SG rules) | `string` | required |
| `aws_region` | AWS region (for Bedrock endpoint names) | `string` | required |
| `environment` | Environment name | `string` | `"prod"` |
| `name_prefix` | Prefix for resource names | `string` | `"doc-summarizer"` |
| `enable_bedrock_agent_endpoints` | Create Bedrock Agents endpoints | `bool` | `false` |
| `enable_s3_gateway_endpoint` | Create S3 gateway endpoint | `bool` | `true` |
| `private_route_table_ids` | Route table IDs for S3 endpoint | `list(string)` | `[]` |
| `restrict_bedrock_endpoint_policy` | Restrict runtime endpoint to InvokeModel* | `bool` | `true` |
| `create_app_security_group` | Create SG for summarizer app | `bool` | `true` |
| `app_ingress_cidrs` | CIDRs allowed to app | `list(string)` | `[]` |
| `app_ingress_security_groups` | SGs allowed to app | `list(string)` | `[]` |
| `app_ingress_ports` | Ports for app ingress | `list(number)` | `[443]` |
| `create_kms_key` | Create KMS key for encryption | `bool` | `false` |
| `tags` | Tags for all resources | `map(string)` | `{}` |

## Outputs

| Name | Description |
|------|-------------|
| `bedrock_endpoint_id` | Bedrock control plane endpoint ID |
| `bedrock_runtime_endpoint_id` | Bedrock runtime endpoint ID |
| `summarizer_role_arn` | IAM role ARN for the app |
| `app_security_group_id` | App security group ID (if created) |
| `vpc_endpoints_security_group_id` | Security group for VPC endpoints |
| `s3_gateway_endpoint_id` | S3 gateway endpoint ID (if created) |
| `kms_key_arn` | KMS key ARN (if created) |

## Security and compliance

- **Bedrock**: Traffic stays in the VPC via PrivateLink; optional endpoint policy limits actions to `InvokeModel` / `InvokeModelWithResponseStream`.
- **S3**: Use the S3 gateway endpoint so document read/write does not traverse the public internet.
- **IAM**: Role has minimal permissions (Bedrock invoke/list models, S3 Get/Put/List, CloudWatch Logs).
- **Encryption**: Optional customer-managed KMS key with rotation for data at rest.

## License

See repository root.
