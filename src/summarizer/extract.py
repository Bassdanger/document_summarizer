"""
Extract text from PDF (Amazon Textract) and Word (.docx) for summarization.

- PDF: Uses Amazon Textract (AWS). Single-page via sync API; multi-page via
  async API (S3 only). When run in the VPC with the Terraform stack, Textract
  is reached via VPC endpoint.
- Word: Uses python-docx (runs in your Lambda/ECS). AWS has no managed
  Word-to-text API.
"""

from __future__ import annotations

import re
import time
from pathlib import Path
from typing import Optional

import boto3


def _textract_client(region_name: Optional[str] = None):
    return boto3.client("textract", region_name=region_name)


def _blocks_to_text(blocks: list[dict]) -> str:
    """Convert Textract Block list to plain text (LINE blocks, in order)."""
    lines = [
        b["Text"]
        for b in blocks
        if b.get("BlockType") == "LINE" and b.get("Text")
    ]
    return "\n".join(lines)


def extract_text_from_pdf_bytes(pdf_bytes: bytes, *, region_name: Optional[str] = None) -> str:
    """
    Extract text from a single-page PDF using Textract (sync).
    For multi-page PDFs, use extract_text_from_pdf_s3() with the file in S3.
    """
    client = _textract_client(region_name=region_name)
    resp = client.detect_document_text(Document={"Bytes": pdf_bytes})
    return _blocks_to_text(resp.get("Blocks", []))


def extract_text_from_pdf_s3(
    bucket: str,
    key: str,
    *,
    region_name: Optional[str] = None,
    poll_interval: float = 2.0,
    poll_timeout: float = 300.0,
) -> str:
    """
    Extract text from a PDF in S3 using Textract (async). Supports multi-page.
    Polls until the job completes (no SNS required).
    """
    client = _textract_client(region_name=region_name)
    start = client.start_document_text_detection(
        DocumentLocation={"S3Object": {"Bucket": bucket, "Name": key}}
    )
    job_id = start["JobId"]

    deadline = time.monotonic() + poll_timeout
    while time.monotonic() < deadline:
        result = client.get_document_text_detection(JobId=job_id)
        status = result["JobStatus"]

        if status == "SUCCEEDED":
            blocks = result.get("Blocks", [])
            while result.get("NextToken"):
                result = client.get_document_text_detection(
                    JobId=job_id, NextToken=result["NextToken"]
                )
                blocks.extend(result.get("Blocks", []))
            return _blocks_to_text(blocks)
        if status == "FAILED":
            raise RuntimeError(
                f"Textract job {job_id} failed: {result.get('StatusMessage', 'unknown')}"
            )

        time.sleep(poll_interval)

    raise TimeoutError(f"Textract job {job_id} did not complete within {poll_timeout}s")


def extract_text_from_docx(path: str) -> str:
    """
    Extract text from a .docx file using python-docx.
    AWS has no managed Word-to-text API; this runs in your Lambda/ECS.
    """
    from docx import Document as DocxDocument

    doc = DocxDocument(path)
    return "\n".join(p.text for p in doc.paragraphs if p.text.strip())


def extract_text_for_summary(
    source: str,
    *,
    region_name: Optional[str] = None,
) -> str:
    """
    Extract plain text from a file path or S3 URI for summarization.

    - s3://... .pdf → Textract (async, multi-page).
    - Local .pdf → Textract (sync, single-page).
    - Local .docx → python-docx.
    - Anything else → read as UTF-8 text.
    """
    source = source.strip()
    is_s3 = source.lower().startswith("s3://")

    if is_s3:
        match = re.match(r"^s3://([^/]+)/(.+)$", source)
        if not match:
            raise ValueError(f"Invalid S3 URI: {source}")
        bucket, key = match.groups()
        key_lower = key.lower()
        if key_lower.endswith(".pdf"):
            return extract_text_from_pdf_s3(bucket, key, region_name=region_name)
        # Text file in S3
        s3 = boto3.client("s3", region_name=region_name)
        resp = s3.get_object(Bucket=bucket, Key=key)
        return resp["Body"].read().decode("utf-8", errors="replace")

    path = Path(source)
    suffix = path.suffix.lower()
    if suffix == ".pdf":
        pdf_bytes = path.read_bytes()
        return extract_text_from_pdf_bytes(pdf_bytes, region_name=region_name)
    if suffix in (".docx", ".doc"):
        if suffix == ".doc":
            raise ValueError(
                "Binary .doc is not supported. Use .docx or convert to PDF and use Textract."
            )
        return extract_text_from_docx(str(path))
    # Plain text
    return path.read_text(encoding="utf-8", errors="replace")
