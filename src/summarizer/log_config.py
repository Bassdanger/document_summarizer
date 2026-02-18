"""
Structured logging for compliance and audit.

Log events are JSON-friendly (no PII or document content). When run in Lambda/ECS,
stdout/stderr is captured by the platform and sent to CloudWatch.
"""

from __future__ import annotations

import json
import logging
import os
from typing import Any

# Log group name can be set by Terraform output (e.g. for Lambda/ECS config)
LOG_GROUP_NAME = os.environ.get("DOCUMENT_SUMMARIZER_LOG_GROUP", "/document-summarizer/app")


def _structured_message(level: str, event: str, **kwargs: Any) -> str:
    """Build a single-line JSON message for audit; never include PII or document content."""
    payload = {"event": event, "level": level, **{k: v for k, v in kwargs.items() if v is not None}}
    return json.dumps(payload)


class StructuredAuditLogger:
    """Logger that emits JSON audit events (no PII)."""

    def __init__(self, name: str = "document_summarizer"):
        self._logger = logging.getLogger(name)

    def audit(self, event: str, **kwargs: Any) -> None:
        self._logger.info(_structured_message("INFO", event, **kwargs))

    def error_audit(self, event: str, **kwargs: Any) -> None:
        self._logger.error(_structured_message("ERROR", event, **kwargs))


def configure_logging(level: str = "INFO") -> None:
    """Configure root logger so Lambda/ECS capture logs to CloudWatch."""
    logging.basicConfig(
        level=getattr(logging, level.upper(), logging.INFO),
        format="%(message)s",
        datefmt=None,
    )
    # Reduce noise from boto3
    logging.getLogger("botocore").setLevel(logging.WARNING)
    logging.getLogger("boto3").setLevel(logging.WARNING)


# Module-level audit logger for summarizer
audit_log = StructuredAuditLogger()
