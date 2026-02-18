# Document Summarizer — Terraform

Terraform template for deploying a **secure, compliant** document summarizer using **Amazon Bedrock** in an AWS account with **private subnets only** (no public subnets, no Internet Gateway). Designed for teams to reuse across environments.

## Layout

- **`modules/document-summarizer-bedrock/`** — Reusable module:
  - VPC interface endpoints for Bedrock (PrivateLink), so Bedrock traffic never leaves the AWS network
  - Optional S3 gateway endpoint for document storage without NAT
  - IAM role for the summarizer app (Bedrock + S3 + logs)
  - Optional app security group and KMS key

- **`examples/private-subnets-only/`** — Example consumption of the module with two private subnets and NAT gateways.

## How someone would use this

### 1. Prerequisites

- An existing VPC with **two (or more) private subnets** and **NAT gateways** (e.g. one NAT per AZ). No public subnets or Internet Gateway required for Bedrock or S3 when using this module.
- You need: **VPC ID**, **private subnet IDs**, **VPC CIDR**, and the **route table IDs** for those private subnets (for the S3 gateway endpoint). Get them from the AWS console, CLI, or your existing Terraform.

### 2. Run the Terraform

**Option A — Use the example (fastest):**

```bash
cd terraform/examples/private-subnets-only
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and set:

- `vpc_id` — your VPC ID  
- `private_subnet_ids` — e.g. `["subnet-aaa", "subnet-bbb"]`  
- `private_route_table_ids` — route tables for those subnets (for S3 endpoint)  
- `vpc_cidr` — e.g. `"10.0.0.0/16"`  
- `aws_region` — e.g. `"us-east-1"`  
- Optionally `app_ingress_security_groups` or `app_ingress_cidrs` if something (e.g. ALB) will call your app  

Then:

```bash
terraform init
terraform plan
terraform apply
```

**Option B — Call the module from your own Terraform:**

In your repo (e.g. where you already manage the VPC), add a module block:

```hcl
module "document_summarizer_bedrock" {
  source = "./terraform/modules/document-summarizer-bedrock"   # or your path

  vpc_id                   = aws_vpc.main.id
  private_subnet_ids       = aws_subnet.private[*].id
  vpc_cidr                 = aws_vpc.main.cidr_block
  aws_region               = data.aws_region.current.name
  environment              = "prod"
  name_prefix              = "doc-summarizer"
  private_route_table_ids  = aws_route_table.private[*].id
  app_ingress_security_groups = [aws_security_group.alb.id]

  tags = { Project = "DocumentSummarizer" }
}
```

Then `terraform init`, `plan`, `apply` from that root.

### 3. Use the outputs when deploying your app

After `apply`, Terraform prints (or you run `terraform output`):

| Output | Use it for |
|--------|------------|
| `summarizer_role_arn` | **IAM role** for your summarizer app. Attach as ECS task role, Lambda execution role, or App Runner instance role. The app then has permission to call Bedrock and S3 without access keys. |
| `app_security_group_id` | **Security group** to attach to the app (ECS tasks, Lambda ENI, or App Runner VPC connector). Restrict ingress with `app_ingress_*` variables; egress is already set for HTTPS. |
| `s3_gateway_endpoint_id` | Informational; S3 traffic from the VPC already uses the gateway endpoint. |
| `kms_key_arn` | Only if you set `create_kms_key = true`. Use for S3 bucket encryption or Bedrock model invocation with a customer key. |

**Deploy the app in the same VPC and private subnets** so it uses the Bedrock and S3 VPC endpoints. No code changes needed: the AWS SDK resolves Bedrock/S3 to the private endpoints when private DNS is enabled (which the module does).

### 4. Summary

1. Fill in `terraform.tfvars` (or module variables) with your VPC, subnets, and route tables.  
2. `terraform init && terraform apply`.  
3. Deploy your document summarizer (ECS, Lambda, App Runner, etc.) in those private subnets, using `summarizer_role_arn` as its role and `app_security_group_id` as its security group.

## Security and compliance

- **No internet for Bedrock/S3**: Bedrock and S3 are reached via VPC endpoints (PrivateLink and S3 Gateway), so no IGW or NAT is required for those services.
- **Restricted endpoint policy**: Optional VPC endpoint policy limits Bedrock runtime to `InvokeModel` and `InvokeModelWithResponseStream`.
- **Least-privilege IAM**: Role scoped to Bedrock invoke/list, S3 read/write, and CloudWatch Logs.
- **Optional KMS**: Customer-managed key with rotation for encryption at rest.

See [modules/document-summarizer-bedrock/README.md](modules/document-summarizer-bedrock/README.md) for full inputs, outputs, and options.
