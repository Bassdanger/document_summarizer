# Document Summarizer — Terraform

Terraform template for deploying a **secure, compliant** document summarizer using **Amazon Bedrock** in an AWS account with **private subnets only** (no public subnets, no Internet Gateway). Designed for teams to reuse across environments.

## Layout

- **`modules/document-summarizer-bedrock/`** — Reusable module:
  - VPC interface endpoints for Bedrock (PrivateLink), so Bedrock traffic never leaves the AWS network
  - Optional S3 gateway endpoint for document storage without NAT
  - IAM role for the summarizer app (Bedrock + S3 + logs)
  - Optional app security group and KMS key

- **`examples/private-subnets-only/`** — Example consumption of the module with two private subnets and NAT gateways.

## Quick start

1. Ensure you have an existing VPC with at least two **private** subnets and NAT gateways (no public subnets or IGW required for Bedrock/S3 if using the provided endpoints).
2. Copy the example and set your VPC/subnet/route table IDs:

   ```bash
   cp -r examples/private-subnets-only my-env
   cd my-env
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your vpc_id, private_subnet_ids, private_route_table_ids, vpc_cidr
   terraform init
   terraform plan
   terraform apply
   ```

3. Use the outputs (`summarizer_role_arn`, `app_security_group_id`) when deploying your document summarizer app (e.g. ECS, Lambda, App Runner) in the same VPC and subnets.

## Security and compliance

- **No internet for Bedrock/S3**: Bedrock and S3 are reached via VPC endpoints (PrivateLink and S3 Gateway), so no IGW or NAT is required for those services.
- **Restricted endpoint policy**: Optional VPC endpoint policy limits Bedrock runtime to `InvokeModel` and `InvokeModelWithResponseStream`.
- **Least-privilege IAM**: Role scoped to Bedrock invoke/list, S3 read/write, and CloudWatch Logs.
- **Optional KMS**: Customer-managed key with rotation for encryption at rest.

See [modules/document-summarizer-bedrock/README.md](modules/document-summarizer-bedrock/README.md) for full inputs, outputs, and options.
