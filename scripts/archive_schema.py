#!/usr/bin/env python3
"""Archive a PostgreSQL schema with pg_dump and upload it to S3.

Used by the destroy-schema GitHub Actions workflow before allow_destroy=true.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", default="5432")
    parser.add_argument("--database", required=True)
    parser.add_argument("--schema", required=True)
    parser.add_argument("--username", required=True)
    parser.add_argument("--password", required=True)
    parser.add_argument("--bucket", required=True)
    parser.add_argument("--environment", required=True)
    parser.add_argument("--ticket", default="")
    parser.add_argument("--actor", default="")
    parser.add_argument("--run-url", default="")
    args = parser.parse_args()

    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    prefix = f"archives/{args.environment}/{args.database}/{args.schema}/{timestamp}"
    dump_key = f"{prefix}/schema.dump"
    meta_key = f"{prefix}/metadata.json"

    env = os.environ.copy()
    env["PGPASSWORD"] = args.password
    env["PGSSLMODE"] = "require"

    with tempfile.TemporaryDirectory() as tmp:
        dump_path = Path(tmp) / "schema.dump"
        meta_path = Path(tmp) / "metadata.json"

        cmd = [
            "pg_dump",
            "--host",
            args.host,
            "--port",
            str(args.port),
            "--username",
            args.username,
            "--dbname",
            args.database,
            "--schema",
            args.schema,
            "--format",
            "custom",
            "--file",
            str(dump_path),
            "--no-owner",
            "--no-acl",
        ]
        print(f"Running: {' '.join(cmd[:-2])} ...", flush=True)
        result = subprocess.run(cmd, env=env, capture_output=True, text=True)
        if result.returncode != 0:
            print(result.stderr, file=sys.stderr)
            print("pg_dump failed — refuse to destroy without an archive.", file=sys.stderr)
            return result.returncode

        digest = hashlib.sha256(dump_path.read_bytes()).hexdigest()
        size = dump_path.stat().st_size
        metadata = {
            "environment": args.environment,
            "database": args.database,
            "schema": args.schema,
            "timestamp_utc": timestamp,
            "sha256": digest,
            "size_bytes": size,
            "ticket": args.ticket,
            "actor": args.actor,
            "run_url": args.run_url,
            "s3_dump": f"s3://{args.bucket}/{dump_key}",
            "s3_metadata": f"s3://{args.bucket}/{meta_key}",
        }
        meta_path.write_text(json.dumps(metadata, indent=2) + "\n")

        for local, key in ((dump_path, dump_key), (meta_path, meta_key)):
            put = subprocess.run(
                ["aws", "s3", "cp", str(local), f"s3://{args.bucket}/{key}"],
                capture_output=True,
                text=True,
            )
            if put.returncode != 0:
                print(put.stderr, file=sys.stderr)
                return put.returncode

        print(json.dumps(metadata, indent=2))
        # Expose path for downstream steps
        summary = os.environ.get("GITHUB_STEP_SUMMARY")
        if summary:
            with open(summary, "a", encoding="utf-8") as fh:
                fh.write("## Schema archive\n\n")
                fh.write(f"- Dump: `s3://{args.bucket}/{dump_key}`\n")
                fh.write(f"- SHA-256: `{digest}`\n")
                fh.write(f"- Size: {size} bytes\n")

        output = os.environ.get("GITHUB_OUTPUT")
        if output:
            with open(output, "a", encoding="utf-8") as fh:
                fh.write(f"archive_uri=s3://{args.bucket}/{dump_key}\n")
                fh.write(f"archive_prefix={prefix}\n")
                fh.write(f"sha256={digest}\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
