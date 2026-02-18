"""
Document summarization using Amazon Bedrock.

When run in a VPC with the Terraform-created VPC endpoints and IAM role,
the AWS SDK uses PrivateLink automatically (no code changes needed).

Supports: plain text, PDF (via Amazon Textract), and Word .docx (via python-docx).
"""

from __future__ import annotations

from typing import Optional

import boto3


class PIIDetectedError(Exception):
    """Raised when pii_mode='block' and the document contains detected PII."""

    pass

from .extract import extract_text_for_summary
from .pii import contains_pii, redact_pii


# Default model; override with BEDROCK_MODEL_ID env or parameter.
DEFAULT_MODEL_ID = "anthropic.claude-3-5-sonnet-20241022-v2:0"


def _get_client(region_name: Optional[str] = None):
    return boto3.client("bedrock-runtime", region_name=region_name)


def summarize_text(
    text: str,
    *,
    model_id: Optional[str] = None,
    region_name: Optional[str] = None,
    max_tokens: int = 1024,
    temperature: float = 0.3,
    pii_mode: str = "redact",
    pii_language_code: str = "en",
    pii_mask: str = "[REDACTED]",
) -> str:
    """
    Summarize plain text using Bedrock.

    pii_mode: "redact" (default) = replace PII with a mask before sending to Bedrock;
      "block" = raise PIIDetectedError if PII is found and do not call Bedrock;
      "off" = do not check or redact PII.
    Uses the Converse API. When running in the VPC with the document-summarizer
    Terraform stack, the default boto3 client uses the VPC endpoints and
    the task/instance role (no credentials needed).
    """
    client = _get_client(region_name=region_name)
    model_id = model_id or DEFAULT_MODEL_ID

    if not text or not text.strip():
        return ""

    if pii_mode == "block":
        if contains_pii(text, region_name=region_name, language_code=pii_language_code):
            raise PIIDetectedError(
                "Document contains PII; summarization blocked. Use pii_mode='redact' to summarize with PII masked."
            )
    elif pii_mode == "redact":
        text = redact_pii(
            text,
            region_name=region_name,
            language_code=pii_language_code,
            mask=pii_mask,
        )

    response = client.converse(
        modelId=model_id,
        messages=[
            {
                "role": "user",
                "content": [
                    {
                        "text": (
                            "Summarize the following document concisely. "
                            "Preserve key facts and conclusions. "
                            "Do not add commentary or meta text.\n\n"
                            f"{text}"
                        )
                    }
                ],
            }
        ],
        system=[{"text": "You are a document summarization assistant. Output only the summary, no preamble."}],
        inferenceConfig={
            "maxTokens": max_tokens,
            "temperature": temperature,
        },
    )

    # Converse response: output.message.content[].text
    output = response.get("output", {})
    message = output.get("message", {})
    parts = message.get("content", [])
    return "".join(block.get("text", "") for block in parts if block.get("text"))


def summarize_document(
    source: str,
    *,
    model_id: Optional[str] = None,
    region_name: Optional[str] = None,
    max_tokens: int = 1024,
    temperature: float = 0.3,
    pii_mode: str = "redact",
    pii_language_code: str = "en",
    pii_mask: str = "[REDACTED]",
) -> str:
    """
    Summarize a document from a local file path or S3 URI.

    - PDF: extracted via Amazon Textract (single-page local, multi-page from S3).
    - Word .docx: extracted via python-docx. (.doc not supported.)
    - Other: read as UTF-8 text (.txt, .md, .json, .html, etc.).

    PII: pii_mode "redact" (default) masks PII before sending to Bedrock;
    "block" raises PIIDetectedError if PII is found; "off" disables PII handling.

    When running with the Terraform IAM role in the VPC, Bedrock, S3, Textract,
    and Comprehend use VPC endpoints (no NAT needed for these calls).
    """
    text = extract_text_for_summary(source, region_name=region_name)

    return summarize_text(
        text,
        model_id=model_id,
        region_name=region_name,
        max_tokens=max_tokens,
        temperature=temperature,
        pii_mode=pii_mode,
        pii_language_code=pii_language_code,
        pii_mask=pii_mask,
    )
