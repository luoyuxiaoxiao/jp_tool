"""SQLite-backed analysis result storage with deduplication by source text."""

from __future__ import annotations

import hashlib
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
        CREATE TABLE IF NOT EXISTS analysis_history (
            text_hash TEXT PRIMARY KEY,
            text TEXT NOT NULL,
            basic_json TEXT,
            deep_json TEXT,
            hit_count INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
        """
    )
    conn.execute(
        """
        CREATE INDEX IF NOT EXISTS idx_analysis_history_updated
        ON analysis_history(updated_at DESC)
        """
    )
    return conn


def _text_hash(text: str) -> str:
    normalized = (text or "").strip()
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()


def upsert_basic_result(text: str, basic_json: str):
    """Insert or update basic analysis result by unique source text."""
    normalized = (text or "").strip()
    if not normalized:
        return

    with _LOCK:
        conn = _connect()
        try:
            conn.execute(
                """
                INSERT INTO analysis_history(text_hash, text, basic_json, hit_count)
                VALUES(?, ?, ?, 1)
                ON CONFLICT(text_hash) DO UPDATE SET
                    text = excluded.text,
                    basic_json = excluded.basic_json,
                    hit_count = analysis_history.hit_count + 1,
                    updated_at = CURRENT_TIMESTAMP
                """,
                (_text_hash(normalized), normalized, basic_json),
            )
            conn.commit()
        finally:
            conn.close()


def upsert_deep_result(text: str, deep_json: str):
    """Insert or update deep analysis result by unique source text."""
    normalized = (text or "").strip()
    if not normalized:
        return

    with _LOCK:
        conn = _connect()
        try:
            conn.execute(
                """
                INSERT INTO analysis_history(text_hash, text, deep_json, hit_count)
                VALUES(?, ?, ?, 1)
                ON CONFLICT(text_hash) DO UPDATE SET
                    text = excluded.text,
                    deep_json = excluded.deep_json,
                    hit_count = analysis_history.hit_count + 1,
                    updated_at = CURRENT_TIMESTAMP
                """,
                (_text_hash(normalized), normalized, deep_json),
            )
            conn.commit()
        finally:
            conn.close()


def get_recent_results(limit: int = 50) -> list[dict]:
    """Fetch most recent analysis records, newest first."""
    n = max(1, min(int(limit), 500))
    with _LOCK:
        conn = _connect()
        try:
            rows = conn.execute(
                """
                SELECT text, basic_json, deep_json, hit_count, created_at, updated_at
                FROM analysis_history
                ORDER BY datetime(updated_at) DESC
                LIMIT ?
                """,
                (n,),
            ).fetchall()
        finally:
            conn.close()

    items: list[dict] = []
    for text, basic_json, deep_json, hit_count, created_at, updated_at in rows:
        basic_obj = None
        deep_obj = None

        if isinstance(basic_json, str) and basic_json.strip():
            try:
                basic_obj = json.loads(basic_json)
            except Exception:
                basic_obj = None

        if isinstance(deep_json, str) and deep_json.strip():
            try:
                deep_obj = json.loads(deep_json)
            except Exception:
                deep_obj = None

        items.append(
            {
                "text": text,
                "basic_result": basic_obj,
                "deep_result": deep_obj,
                "hit_count": int(hit_count or 0),
                "created_at": created_at,
                "updated_at": updated_at,
            }
        )

    return items


def get_cached_result(text: str) -> dict | None:
    """Fetch cached basic/deep result for a specific source text."""
    normalized = (text or "").strip()
    if not normalized:
        return None

    with _LOCK:
        conn = _connect()
        try:
            row = conn.execute(
                """
                SELECT text, basic_json, deep_json, hit_count, created_at, updated_at
                FROM analysis_history
                WHERE text_hash = ?
                """,
                (_text_hash(normalized),),
            ).fetchone()
        finally:
            conn.close()

    if not row:
        return None

    text_val, basic_json, deep_json, hit_count, created_at, updated_at = row
    basic_obj = None
    deep_obj = None

    if isinstance(basic_json, str) and basic_json.strip():
        try:
            basic_obj = json.loads(basic_json)
        except Exception:
            basic_obj = None

    if isinstance(deep_json, str) and deep_json.strip():
        try:
            deep_obj = json.loads(deep_json)
        except Exception:
            deep_obj = None

    return {
        "text": text_val,
        "basic_result": basic_obj,
        "deep_result": deep_obj,
        "hit_count": int(hit_count or 0),
        "created_at": created_at,
        "updated_at": updated_at,
    }


def prune_to_limit(max_rows: int = 1000) -> int:
    """Prune old records and keep only newest max_rows entries."""
    keep = max(50, min(int(max_rows), 20000))
    with _LOCK:
        conn = _connect()
        try:
            before = conn.execute("SELECT COUNT(1) FROM analysis_history").fetchone()[0]
            conn.execute(
                """
                DELETE FROM analysis_history
                WHERE text_hash NOT IN (
                    SELECT text_hash FROM analysis_history
                    ORDER BY datetime(updated_at) DESC
                    LIMIT ?
                )
                """,
                (keep,),
            )
            conn.commit()
            after = conn.execute("SELECT COUNT(1) FROM analysis_history").fetchone()[0]
        finally:
            conn.close()

    return int(before or 0) - int(after or 0)


def delete_history_by_text(text: str) -> int:
    """Delete one analysis record by source text and return affected row count."""
    normalized = (text or "").strip()
    if not normalized:
        return 0

    with _LOCK:
        conn = _connect()
        try:
            cur = conn.execute(
                "DELETE FROM analysis_history WHERE text_hash = ?",
                (_text_hash(normalized),),
            )
            conn.commit()
            deleted = int(cur.rowcount or 0)
        finally:
            conn.close()

    return deleted


def clear_history_all() -> int:
    """Delete all analysis history records and return affected row count."""
    with _LOCK:
        conn = _connect()
        try:
            cur = conn.execute("DELETE FROM analysis_history")
            conn.commit()
            deleted = int(cur.rowcount or 0)
        finally:
            conn.close()

    return deleted
