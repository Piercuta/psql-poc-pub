#!/usr/bin/env python3
"""Drop a PostgreSQL schema after it has been archived.

Uses DROP SCHEMA ... CASCADE. Call only from the destroy-schema workflow.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", default="5432")
    parser.add_argument("--database", required=True)
    parser.add_argument("--schema", required=True)
    parser.add_argument("--username", required=True)
    args = parser.parse_args()

    if "PGPASSWORD" not in os.environ:
        print("PGPASSWORD must be set in the environment.", file=sys.stderr)
        return 2

    # Identifier quoting: only allow simple names (already validated by YAML keys).
    if not args.schema.replace("_", "").isalnum() or not args.database.replace("_", "").isalnum():
        print("database/schema names must be alphanumeric + underscore.", file=sys.stderr)
        return 2

    sql = f'DROP SCHEMA IF EXISTS "{args.schema}" CASCADE;'
    cmd = [
        "psql",
        "--host",
        args.host,
        "--port",
        str(args.port),
        "--username",
        args.username,
        "--dbname",
        args.database,
        "--set",
        "ON_ERROR_STOP=1",
        "--command",
        sql,
    ]
    env = os.environ.copy()
    env["PGSSLMODE"] = "require"
    print(f'Running: DROP SCHEMA IF EXISTS "{args.schema}" CASCADE;', flush=True)
    result = subprocess.run(cmd, env=env, capture_output=True, text=True)
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
