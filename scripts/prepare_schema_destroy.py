#!/usr/bin/env python3
"""Validate that a schema is retired, then remove it from config.yaml.

Preserves the hand-written layout as much as possible (line-oriented edit).
Also strips mappings that target that schema explicitly.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import yaml


def find_schema_status(data: dict, database: str, schema: str) -> str | None:
    databases = data.get("configuration", {}).get("databases") or {}
    if database not in databases:
        return None
    for entry in databases[database].get("schemas") or []:
        if isinstance(entry, str):
            name, status = entry, "active"
        else:
            name, status = entry.get("name"), entry.get("status", "active")
        if name == schema:
            return status
    return None


def remove_schema_block(lines: list[str], schema: str) -> list[str]:
    """Remove a '- name: <schema>' block (name + following indented status line)."""
    out: list[str] = []
    i = 0
    name_re = re.compile(rf"^(\s*)- name:\s*{re.escape(schema)}\s*(#.*)?$")
    while i < len(lines):
        m = name_re.match(lines[i])
        if not m:
            out.append(lines[i])
            i += 1
            continue
        indent = len(m.group(1))
        i += 1
        # Skip following more-indented lines (status, comments under the entry).
        while i < len(lines):
            line = lines[i]
            if line.strip() == "":
                break
            leading = len(line) - len(line.lstrip(" "))
            if leading <= indent:
                break
            i += 1
    return out


def remove_schema_mappings(lines: list[str], database: str, schema: str) -> list[str]:
    out: list[str] = []
    # Flow-style mapping lines used in this repo.
    pat = re.compile(
        rf"schema:\s*{re.escape(schema)}\b"
    )
    db_pat = re.compile(rf"database:\s*{re.escape(database)}\b")
    for line in lines:
        if pat.search(line) and db_pat.search(line):
            continue
        out.append(line)
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--database", required=True)
    parser.add_argument("--schema", required=True)
    parser.add_argument("--confirm", required=True)
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()

    if args.confirm != args.schema:
        print(
            f"Confirmation mismatch: expected schema name '{args.schema}', got '{args.confirm}'.",
            file=sys.stderr,
        )
        return 2

    text = args.config.read_text()
    data = yaml.safe_load(text)
    status = find_schema_status(data, args.database, args.schema)
    if status is None:
        print(
            f"Schema '{args.database}/{args.schema}' not found in config.yaml.",
            file=sys.stderr,
        )
        return 2
    if status != "retired":
        print(
            f"Schema '{args.database}/{args.schema}' status is '{status}', expected 'retired'. "
            "Retire it on the normal pipeline first.",
            file=sys.stderr,
        )
        return 2

    if args.check_only:
        print(f"OK: {args.database}/{args.schema} is retired.")
        return 0

    lines = text.splitlines(keepends=True)
    lines = remove_schema_block(lines, args.schema)
    lines = remove_schema_mappings(lines, args.database, args.schema)
    args.config.write_text("".join(lines))
    print(f"Removed {args.database}/{args.schema} from {args.config}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
