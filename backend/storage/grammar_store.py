"""SQLite-backed learned grammar storage for JP Tool."""

from __future__ import annotations

import json
import sqlite3
import threading
from pathlib import Path

_DB_PATH = Path(__file__).parent / "data" / "app_settings.db"
_LOCK = threading.Lock()


def _connect() -> sqlite3.Connection:
    _DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(_DB_PATH)
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS learned_grammar (
            pattern_key TEXT PRIMARY KEY,
            pattern TEXT NOT NULL,
            level TEXT NOT NULL,
            meaning_zh TEXT NOT NULL DEFAULT '',
            meaning_ja TEXT NOT NULL DEFAULT '',
            example TEXT NOT NULL DEFAULT '',
            regexes_json TEXT NOT NULL DEFAULT '[]',
            updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
        """
    )
    conn.execute(
        """
        CREATE INDEX IF NOT EXISTS idx_learned_grammar_updated
        ON learned_grammar(updated_at DESC)
        """
    )
    return conn


def _pattern_key(pattern: str) -> str:
    return "".join((pattern or "").strip().lower().split())


def _normalize_regexes(regexes: object, pattern: str) -> list[str]:
    result: list[str] = []
    seen: set[str] = set()

    values = regexes if isinstance(regexes, list) else [pattern]
    for item in values:
        text = str(item or "").strip()
        if not text or text in seen:
            continue
        seen.add(text)
        result.append(text)

    if not result and pattern:
        result = [pattern]
    return result


def upsert_learned_grammar(entry: dict) -> bool:
    pattern = str(entry.get("pattern", "")).strip()
    key = _pattern_key(pattern)
    if not key:
        return False

    level = str(entry.get("level", "")).strip().upper()
    meaning_zh = str(entry.get("meaning_zh", ""))
    meaning_ja = str(entry.get("meaning_ja", ""))
    example = str(entry.get("example", ""))
    regexes = _normalize_regexes(entry.get("regexes", []), pattern)

    with _LOCK:
        conn = _connect()
        try:
            conn.execute(
                """
                INSERT INTO learned_grammar(
                    pattern_key, pattern, level, meaning_zh, meaning_ja, example, regexes_json
                ) VALUES(?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(pattern_key) DO UPDATE SET
                    pattern = excluded.pattern,
                    level = CASE
                        WHEN learned_grammar.level = '' THEN excluded.level
                        ELSE learned_grammar.level
                    END,
                    meaning_zh = CASE
                        WHEN learned_grammar.meaning_zh = '' THEN excluded.meaning_zh
                        ELSE learned_grammar.meaning_zh
                    END,
                    meaning_ja = CASE
                        WHEN learned_grammar.meaning_ja = '' THEN excluded.meaning_ja
                        ELSE learned_grammar.meaning_ja
                    END,
                    example = CASE
                        WHEN learned_grammar.example = '' THEN excluded.example
                        ELSE learned_grammar.example
                    END,
                    regexes_json = CASE
                        WHEN learned_grammar.regexes_json = '[]' THEN excluded.regexes_json
                        ELSE learned_grammar.regexes_json
                    END,
                    updated_at = CURRENT_TIMESTAMP
                """,
                (
                    key,
                    pattern,
                    level,
                    meaning_zh,
                    meaning_ja,
                    example,
                    json.dumps(regexes, ensure_ascii=False),
                ),
            )
            conn.commit()
            return True
        except Exception:
            return False
        finally:
            conn.close()


def load_learned_grammar(limit: int | None = None) -> list[dict]:
    query = (
        "SELECT pattern, level, meaning_zh, meaning_ja, example, regexes_json "
        "FROM learned_grammar ORDER BY datetime(updated_at) DESC"
    )
    args: tuple[object, ...] = ()

    if isinstance(limit, int) and limit > 0:
        query += " LIMIT ?"
        args = (limit,)

    with _LOCK:
        conn = _connect()
        try:
            rows = conn.execute(query, args).fetchall()
        finally:
            conn.close()

    items: list[dict] = []
    for pattern, level, meaning_zh, meaning_ja, example, regexes_json in rows:
        regexes: list[str] = []
        if isinstance(regexes_json, str) and regexes_json.strip():
            try:
                decoded = json.loads(regexes_json)
                if isinstance(decoded, list):
                    regexes = [str(x) for x in decoded if str(x).strip()]
            except Exception:
                regexes = []

        if not regexes and pattern:
            regexes = [pattern]

        items.append(
            {
                "pattern": str(pattern or ""),
                "level": str(level or ""),
                "meaning_zh": str(meaning_zh or ""),
                "meaning_ja": str(meaning_ja or ""),
                "example": str(example or ""),
                "regexes": regexes,
                "auto_learned": True,
            }
        )

    return items


def clear_learned_grammar() -> int:
    """Delete all learned grammar records and return affected row count."""
    with _LOCK:
        conn = _connect()
        try:
            cur = conn.execute("DELETE FROM learned_grammar")
            conn.commit()
            deleted = int(cur.rowcount or 0)
        finally:
            conn.close()

    return deleted
