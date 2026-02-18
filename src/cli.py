#!/usr/bin/env python3
"""
CLI to run document summarization.

Usage:
  # Summarize a local file (uses default AWS credentials / env)
  python -m src.cli document.txt

  # Summarize a document in S3 (uses Terraform IAM role when run in ECS/Lambda)
  python -m src.cli s3://my-bucket/path/to/doc.txt

  # Summarize stdin
  cat document.txt | python -m src.cli -

When run inside the VPC (e.g. ECS task or Lambda) with the Terraform-created
role, Bedrock and S3 are reached via VPC endpoints automatically.
"""

import argparse
import sys
from pathlib import Path

# Ensure repo root is on path when run as python -m src.cli
_repo_root = Path(__file__).resolve().parent.parent
if str(_repo_root) not in sys.path:
    sys.path.insert(0, str(_repo_root))

from src.summarizer.summarize import PIIDetectedError, summarize_text, summarize_document


def main():
    parser = argparse.ArgumentParser(
        description="Summarize a document using Amazon Bedrock (run in VPC with Terraform stack for private access)."
    )
    parser.add_argument(
        "source",
        help="File path, S3 URI (s3://bucket/key), or '-' for stdin",
    )
    parser.add_argument(
        "--model",
        default=None,
        help="Bedrock model ID (default: anthropic.claude-3-5-sonnet-20241022-v2:0)",
    )
    parser.add_argument(
        "--region",
        default=None,
        help="AWS region (default: from env or profile)",
    )
    parser.add_argument(
        "--max-tokens",
        type=int,
        default=1024,
        help="Max tokens in summary (default: 1024)",
    )
    parser.add_argument(
        "-o", "--output",
        default=None,
        help="Write summary to file (default: stdout)",
    )
    parser.add_argument(
        "--pii",
        choices=["redact", "block", "off"],
        default="redact",
        help="PII handling: redact (mask before Bedrock), block (refuse if PII), off (default: redact)",
    )
    args = parser.parse_args()

    try:
        if args.source == "-":
            text = sys.stdin.read()
            summary = summarize_text(
                text,
                model_id=args.model,
                region_name=args.region,
                max_tokens=args.max_tokens,
                pii_mode=args.pii,
            )
        else:
            summary = summarize_document(
                args.source,
                model_id=args.model,
                region_name=args.region,
                max_tokens=args.max_tokens,
                pii_mode=args.pii,
            )
    except PIIDetectedError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    if args.output:
        Path(args.output).write_text(summary, encoding="utf-8")
        print(f"Summary written to {args.output}", file=sys.stderr)
    else:
        print(summary)


if __name__ == "__main__":
    main()
