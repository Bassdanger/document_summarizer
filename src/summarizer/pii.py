"""
PII and sensitive-document handling using Amazon Comprehend.

- Detect PII: DetectPiiEntities (chunked for long text; 5 KB limit per request).
- Redact: Replace detected PII spans with a mask before sending to Bedrock.
- Block: Optionally refuse to process when PII is detected.

When run in the VPC with the Terraform stack, Comprehend is reached via
the VPC endpoint (no NAT).
"""

from __future__ import annotations

from typing import Optional

import boto3

# Comprehend sync API limit is 5000 bytes per request; chunk to stay under.
_CHUNK_CHARS = 4000


def _comprehend_client(region_name: Optional[str] = None):
    return boto3.client("comprehend", region_name=region_name)


def _chunk_text_simple(text: str, max_chars: int = _CHUNK_CHARS) -> list[tuple[str, int]]:
    """Split by character count (safe under 5KB for ASCII; may be under for UTF-8)."""
    result: list[tuple[str, int]] = []
    for i in range(0, len(text), max_chars):
        chunk = text[i : i + max_chars]
        result.append((chunk, i))
    return result


def contains_pii(
    text: str,
    *,
    region_name: Optional[str] = None,
    language_code: str = "en",
) -> bool:
    """
    Return True if the text contains detected PII (Comprehend DetectPiiEntities).
    Chunks long text to respect the 5 KB per-request limit.
    """
    if not text or not text.strip():
        return False
    client = _comprehend_client(region_name=region_name)
    chunks = _chunk_text_simple(text)
    for chunk, _ in chunks:
        if not chunk.strip():
            continue
        try:
            resp = client.detect_pii_entities(Text=chunk, LanguageCode=language_code)
            if resp.get("Entities"):
                return True
        except Exception:
            # If we can't call Comprehend, treat as "might have PII" and report True to be safe
            return True
    return False


def redact_pii(
    text: str,
    *,
    region_name: Optional[str] = None,
    language_code: str = "en",
    mask: str = "[REDACTED]",
) -> str:
    """
    Replace detected PII with a mask so it is not sent to Bedrock.
    Uses Comprehend DetectPiiEntities; chunks long text (5 KB limit per request).
    Returns the redacted string (same length pattern not preserved; spans replaced by mask).
    """
    if not text or not text.strip():
        return text
    client = _comprehend_client(region_name=region_name)
    chunks = _chunk_text_simple(text)
    # Build list of (start, end) character ranges to redact (in original text coordinates).
    redact_ranges: list[tuple[int, int]] = []
    for chunk, char_offset in chunks:
        if not chunk.strip():
            continue
        try:
            resp = client.detect_pii_entities(Text=chunk, LanguageCode=language_code)
            for ent in resp.get("Entities", []):
                start = char_offset + ent["BeginOffset"]
                end = char_offset + ent["EndOffset"]
                redact_ranges.append((start, end))
        except Exception as e:
            # Fail closed: do not send potentially unredacted PII to Bedrock
            raise RuntimeError(
                "PII redaction failed (Comprehend error); document not sent to Bedrock."
            ) from e
    # Sort by start and merge overlapping/adjacent ranges.
    redact_ranges.sort(key=lambda r: r[0])
    merged: list[tuple[int, int]] = []
    for s, e in redact_ranges:
        if merged and s <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], e))
        else:
            merged.append((s, e))
    # Apply redactions from end to start so indices don't shift.
    result = list(text)  # work with list for mutable updates
    for start, end in reversed(merged):
        result[start:end] = list(mask)
    return "".join(result)
