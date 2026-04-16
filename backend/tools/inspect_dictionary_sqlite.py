"""Inspect a dictionary SQLite file and emit a reusable profile.

Usage:
  python backend/tools/inspect_dictionary_sqlite.py \
      --db cache/jmdict.sqlite \
      --out-json cache/jmdict_profile.json \
      --out-md cache/jmdict_profile.md
"""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
from pathlib import Path
from typing import Any

CJK_RE = re.compile(r"[\u4e00-\u9fff]")


def _get_tables(conn: sqlite3.Connection) -> list[str]:
    cur = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
    )
    return [str(row[0]) for row in cur.fetchall()]


def _get_columns(conn: sqlite3.Connection, table: str) -> list[dict[str, Any]]:
    cur = conn.execute(f"PRAGMA table_info({table})")
    result: list[dict[str, Any]] = []
    for cid, name, col_type, notnull, default_value, pk in cur.fetchall():
        result.append(
            {
                "cid": int(cid),
                "name": str(name),
                "type": str(col_type or ""),
                "notnull": bool(notnull),
                "default": default_value,
                "pk": bool(pk),
            }
        )
    return result


def _count_rows(conn: sqlite3.Connection, table: str) -> int:
    cur = conn.execute(f"SELECT COUNT(*) FROM {table}")
    row = cur.fetchone()
    return int(row[0]) if row else 0


def _load_meta(conn: sqlite3.Connection) -> dict[str, str]:
    tables = set(_get_tables(conn))
    if "meta" not in tables:
        return {}

    cur = conn.execute("SELECT key, value FROM meta ORDER BY key")
    out: dict[str, str] = {}
    for key, value in cur.fetchall():
        out[str(key)] = "" if value is None else str(value)
    return out


def _senses_lang_counts(conn: sqlite3.Connection) -> list[dict[str, Any]]:
    tables = set(_get_tables(conn))
    if "senses" in tables:
        cur = conn.execute(
            "SELECT lang, COUNT(*) AS n FROM senses GROUP BY lang ORDER BY n DESC"
        )
    elif "SenseGloss" in tables:
        cur = conn.execute(
            "SELECT lang, COUNT(*) AS n FROM SenseGloss GROUP BY lang ORDER BY n DESC"
        )
    else:
        return []

    out: list[dict[str, Any]] = []
    for lang, count in cur.fetchall():
        out.append({"lang": "" if lang is None else str(lang), "count": int(count)})
    return out


def _senses_cjk_stats(conn: sqlite3.Connection) -> dict[str, Any]:
    tables = set(_get_tables(conn))
    if "senses" in tables:
        cur = conn.execute("SELECT glosses FROM senses")
    elif "SenseGloss" in tables:
        cur = conn.execute("SELECT text FROM SenseGloss")
    else:
        return {"rows_scanned": 0, "rows_with_cjk": 0, "ratio": 0.0}

    scanned = 0
    with_cjk = 0
    for (glosses,) in cur.fetchall():
        scanned += 1
        text = "" if glosses is None else str(glosses)
        if CJK_RE.search(text):
            with_cjk += 1

    ratio = (with_cjk / scanned) if scanned else 0.0
    return {
        "rows_scanned": scanned,
        "rows_with_cjk": with_cjk,
        "ratio": ratio,
    }


def inspect_dictionary(db_path: Path) -> dict[str, Any]:
    if not db_path.exists():
        return {
            "db_path": str(db_path),
            "exists": False,
            "error": "file_not_found",
        }

    conn = sqlite3.connect(db_path)
    try:
        tables = _get_tables(conn)
        table_profiles: dict[str, Any] = {}
        for table in tables:
            table_profiles[table] = {
                "row_count": _count_rows(conn, table),
                "columns": _get_columns(conn, table),
            }

        profile = {
            "db_path": str(db_path),
            "exists": True,
            "tables": table_profiles,
            "meta": _load_meta(conn),
            "senses_lang_counts": _senses_lang_counts(conn),
            "senses_cjk_stats": _senses_cjk_stats(conn),
        }
        return profile
    finally:
        conn.close()


def _write_markdown(profile: dict[str, Any], out_md: Path) -> None:
    lines: list[str] = []
    lines.append("# Dictionary DB Profile")
    lines.append("")
    lines.append(f"- db_path: {profile.get('db_path', '')}")
    lines.append(f"- exists: {profile.get('exists', False)}")

    meta = profile.get("meta", {})
    if isinstance(meta, dict) and meta:
        lines.append("")
        lines.append("## Meta")
        for key in sorted(meta.keys()):
            lines.append(f"- {key}: {meta[key]}")

    tables = profile.get("tables", {})
    if isinstance(tables, dict) and tables:
        lines.append("")
        lines.append("## Tables")
        for table_name in sorted(tables.keys()):
            table_info = tables[table_name]
            row_count = table_info.get("row_count", 0)
            lines.append(f"### {table_name}")
            lines.append(f"- row_count: {row_count}")
            lines.append("- columns:")
            for col in table_info.get("columns", []):
                lines.append(
                    "  - "
                    + f"{col.get('name', '')} "
                    + f"{col.get('type', '')} "
                    + f"pk={col.get('pk', False)} "
                    + f"notnull={col.get('notnull', False)}"
                )

    lang_counts = profile.get("senses_lang_counts", [])
    if isinstance(lang_counts, list) and lang_counts:
        lines.append("")
        lines.append("## Gloss Language Distribution")
        for item in lang_counts:
            lines.append(f"- {item.get('lang', '')}: {item.get('count', 0)}")

    cjk_stats = profile.get("senses_cjk_stats", {})
    if isinstance(cjk_stats, dict):
        lines.append("")
        lines.append("## CJK Coverage in Gloss Text")
        lines.append(f"- rows_scanned: {cjk_stats.get('rows_scanned', 0)}")
        lines.append(f"- rows_with_cjk: {cjk_stats.get('rows_with_cjk', 0)}")
        lines.append(f"- ratio: {cjk_stats.get('ratio', 0.0):.6f}")

    out_md.parent.mkdir(parents=True, exist_ok=True)
    out_md.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Inspect dictionary SQLite DB")
    parser.add_argument("--db", required=True, help="Path to dictionary sqlite file")
    parser.add_argument(
        "--out-json",
        default="",
        help="Optional output JSON path",
    )
    parser.add_argument(
        "--out-md",
        default="",
        help="Optional output Markdown path",
    )
    args = parser.parse_args()

    db_path = Path(args.db)
    profile = inspect_dictionary(db_path)

    if args.out_json:
        out_json = Path(args.out_json)
        out_json.parent.mkdir(parents=True, exist_ok=True)
        out_json.write_text(
            json.dumps(profile, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    if args.out_md:
        _write_markdown(profile, Path(args.out_md))

    print(json.dumps(profile, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
