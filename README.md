# Document Summarizer (Bedrock)

Secure, compliant document summarization using **Amazon Bedrock**, designed for AWS accounts with **private subnets only** (no public subnets, no IGW). Includes Terraform for networking/IAM and a Python app that performs the summarization.

## What’s in this repo

| Part | Purpose |
|------|--------|
| **Terraform** (`terraform/`) | VPC endpoints for Bedrock, S3, Textract, and Comprehend; IAM role; optional app security group and KMS. Run this first so the app can call all services over PrivateLink. |
| **Python app** (`src/`) | Summarizes documents: plain text, **PDF** (Textract), **Word .docx** (python-docx). **PII/sensitive**: optional redaction or block via Amazon Comprehend before sending to Bedrock. |

## Using the summarization (how it fits together)

1. **Deploy the Terraform** in your account (same VPC as where the app will run).  
   See [terraform/README.md](terraform/README.md). You get:
   - Bedrock, S3, Textract, and Comprehend VPC endpoints
   - IAM role for the summarizer (Bedrock, S3, Textract, Comprehend)
   - Optional security group for the app

2. **Run the summarizer app** with that role, in the same VPC (so traffic goes through the VPC endpoints).  
   The app is standard boto3: no special config. It uses the **default AWS credential chain** (instance/task role when on ECS/Lambda, or profile/env when local).

### Option A — CLI (local or on a box in the VPC)

From the repo root:

```bash
pip install -r requirements.txt
```

Summarize a **local file** (text, PDF, or .docx):

```bash
python -m src.cli path/to/document.txt
python -m src.cli report.pdf
python -m src.cli memo.docx
```

Summarize a **document in S3** (text or PDF; when run in the VPC with the Terraform role, Bedrock, S3, and Textract use VPC endpoints):

```bash
python -m src.cli s3://your-bucket/path/to/doc.txt
python -m src.cli s3://your-bucket/reports/report.pdf
```

Summarize **stdin**:

```bash
cat document.txt | python -m src.cli -
```

Optional: write the summary to a file, or set region/model:

```bash
python -m src.cli document.txt -o summary.txt
python -m src.cli document.txt --region us-east-1 --model anthropic.claude-3-5-sonnet-20241022-v2:0
```

When you run this **inside the VPC** (e.g. EC2 or ECS task) and attach the Terraform-created **summarizer IAM role**, it automatically uses the Bedrock and S3 VPC endpoints (no code or env changes).

### Option B — Use the Python API in your own service

Use the same role and VPC as above, and call the summarizer from your app:

```python
from src.summarizer import summarize_text, summarize_document

# From a string
summary = summarize_text("Long document text here...")

# From a file path
summary = summarize_document("/tmp/report.txt")

# From S3 (text or PDF; role must have S3 + Textract access)
summary = summarize_document("s3://my-bucket/documents/report.txt")
summary = summarize_document("s3://my-bucket/documents/report.pdf")
```

Optional kwargs: `model_id`, `region_name`, `max_tokens`, `temperature`, `pii_mode`, `pii_language_code`, `pii_mask`.

### Option C — Run as Lambda or ECS

- **Lambda**: Package `src/` and `requirements.txt`, set the Lambda’s execution role to the Terraform output **`summarizer_role_arn`**, attach the Lambda to your **private subnets** (and optional Terraform app security group). Invoke with an event that includes a local path or S3 URI; handler calls `summarize_document(...)` and returns the summary.
- **ECS**: Run the same code in a task. Use **`summarizer_role_arn`** as the task role and **`app_security_group_id`** (and your private subnets). Traffic to Bedrock and S3 goes through the VPC endpoints.

In all cases, **actually using the summarization** = running this Python code (CLI or API) with the Terraform-created IAM role, in the same VPC so Bedrock (and S3) are reached via the endpoints.

## Quick reference

| I want to… | Do this |
|------------|--------|
| Deploy the secure Bedrock/S3 setup | Use [terraform/README.md](terraform/README.md) and apply the module (or example). |
| Summarize a file or S3 object from my machine | `pip install -r requirements.txt` then `python -m src.cli <file or s3://...>`. Use an AWS profile with Bedrock (and S3 if using s3://). |
| Summarize from code (same VPC + role) | `from src.summarizer import summarize_text, summarize_document` and call with text, path, or S3 URI. |
| Run in Lambda/ECS | Use **summarizer_role_arn** and private subnets (and **app_security_group_id** for ECS). No changes to the summarizer code. |

## What kinds of files can it summarize?

- **PDF** — via **Amazon Textract** (AWS). Local single-page PDF uses sync API; multi-page or S3 PDF uses async Textract (no SNS needed; the app polls until done). Terraform adds a Textract VPC endpoint and IAM permissions.
- **Word .docx** — via **python-docx** (runs in your Lambda/ECS). AWS has no managed Word-to-text API; this is the standard approach. Binary `.doc` is not supported.
- **Plain text** — read as UTF-8: `.txt`, `.md`, `.json`, `.html`, `.csv`, `.yaml`, source code, etc.

So: **PDF and Word are supported in-app**; PDF uses AWS (Textract), Word uses python-docx. No separate extraction step—just pass the file path or S3 URI to the CLI or `summarize_document()`.

---

## PII and sensitive documents

The app can handle documents that may contain **personally identifiable information (PII)** or other sensitive data so that raw PII is not sent to Bedrock.

- **Amazon Comprehend** is used to detect PII (names, emails, phone numbers, SSN, etc.) in the extracted text. Terraform adds a Comprehend VPC endpoint and IAM permission for `DetectPiiEntities`.

### Options

| Option | Behavior |
|--------|----------|
| **`pii_mode="redact"`** (default) | Comprehend detects PII; detected spans are replaced with a mask (e.g. `[REDACTED]`) before the text is sent to Bedrock. The summary is based on the redacted document. |
| **`pii_mode="block"`** | If Comprehend finds any PII, the request is refused and `PIIDetectedError` is raised. No call to Bedrock. Use when you must not process documents that contain PII. |
| **`pii_mode="off"`** | No PII check or redaction; document is sent to Bedrock as-is. Use only when the pipeline is already PII-free or out of scope. |

### CLI

```bash
# Default: redact PII before summarization
python -m src.cli document.pdf

# Refuse to summarize if PII is detected (exit 1)
python -m src.cli document.pdf --pii block

# Disable PII handling
python -m src.cli document.pdf --pii off
```

### API

```python
from src.summarizer import summarize_document, summarize_text, PIIDetectedError

# Redact PII (default), then summarize
summary = summarize_document("report.pdf", pii_mode="redact", pii_mask="[REDACTED]")

# Block if PII present
try:
    summary = summarize_document("report.pdf", pii_mode="block")
except PIIDetectedError:
    # Handle: log, return 403, etc.
    pass

# Optional: language for Comprehend (default "en")
summary = summarize_text(text, pii_mode="redact", pii_language_code="es")
```

Long documents are chunked for Comprehend (5 KB limit per request); redaction is applied across the full text before summarization.
