"""SQLite-backed runtime settings for JP Tool."""

from __future__ import annotations

import os
import sqlite3
import threading
from pathlib import Path

_DB_PATH = Path(__file__).parent / "data" / "app_settings.db"
_LOCK = threading.Lock()

DEFAULT_SETTINGS = {
    "JP_TOOL_LLM": "auto",
    "JP_TOOL_GRAMMAR_AUTO_LEARN": "on",
    "JP_TOOL_DEEP_AUTO_ANALYZE": "on",
    "JP_TOOL_FOLLOW_MODE": "off",
    "OLLAMA_MODEL": "qwen2.5:7b",
    "OLLAMA_URL": "http://localhost:11434",
    "API_FORMAT": "openai",
    "API_BASE_URL": "https://api.openai.com",
    "API_MODEL": "gpt-4o-mini",
    "API_KEY": "",
    "API_TIMEOUT": "30",
    "JP_TOOL_CLIPBOARD": "on",
    "SHORTCUT_TOGGLE_CLIPBOARD": "ctrl+shift+b",
    "SHORTCUT_TOGGLE_GRAMMAR_AUTO_LEARN": "ctrl+shift+g",
    "SHORTCUT_TOGGLE_AUTO_FOLLOW_LUNA": "ctrl+shift+f",
    "SHORTCUT_SUBMIT_ANALYZE": "ctrl+enter",
    "SHORTCUT_FOCUS_INPUT": "ctrl+l",
    "RESOURCE_DICT_DB_PATH": "",
    "RESOURCE_GINZA_MODEL_PATH": "",
    "RESOURCE_GINZA_SPLIT_MODE": "C",
    "RESOURCE_DEPENDENCY_FOCUS_STYLE": "classic",
    "RESOURCE_ONNX_MODEL_PATH": "",
    "LUNA_WS_ENABLED": "off",
    "LUNA_WS_ORIGIN_URL": "",
    "JP_TOOL_QUEUE_MAX_PENDING": "120",
    "JP_TOOL_QUEUE_DROP_PREFETCH_WHEN_BUSY": "on",
}


def _connect() -> sqlite3.Connection:
    _DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(_DB_PATH)
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
        """
    )
    return conn


def _ensure_defaults(conn: sqlite3.Connection):
    for key, value in DEFAULT_SETTINGS.items():
        conn.execute(
            "INSERT OR IGNORE INTO settings(key, value) VALUES(?, ?)",
            (key, str(value)),
        )


def load_env_from_db():
    """Load persisted settings into process environment."""
    with _LOCK:
        conn = _connect()
        try:
            _ensure_defaults(conn)
            conn.commit()
            rows = conn.execute("SELECT key, value FROM settings").fetchall()
        finally:
            conn.close()

    for key, value in rows:
        if key not in DEFAULT_SETTINGS:
            continue
        if value == "":
            os.environ.pop(key, None)
        else:
            os.environ[key] = value


def get_runtime_settings() -> dict[str, str]:
    """Return all managed settings from DB (with defaults)."""
    result = dict(DEFAULT_SETTINGS)
    with _LOCK:
        conn = _connect()
        try:
            _ensure_defaults(conn)
            conn.commit()
            rows = conn.execute("SELECT key, value FROM settings").fetchall()
        finally:
            conn.close()

    for key, value in rows:
        if key in result:
            result[key] = value
    return result


def save_runtime_settings(values: dict[str, object]):
    """Persist managed settings and sync to process environment."""
    if not values:
        return

    normalized: dict[str, str] = {}
    for key, value in values.items():
        if key not in DEFAULT_SETTINGS:
            continue
        normalized[key] = "" if value is None else str(value)

    if not normalized:
        return

    with _LOCK:
        conn = _connect()
        try:
            _ensure_defaults(conn)
            for key, value in normalized.items():
                conn.execute(
                    """
                    INSERT INTO settings(key, value) VALUES(?, ?)
                    ON CONFLICT(key) DO UPDATE SET
                        value = excluded.value,
                        updated_at = CURRENT_TIMESTAMP
                    """,
                    (key, value),
                )
            conn.commit()
        finally:
            conn.close()

    for key, value in normalized.items():
        if value == "":
            os.environ.pop(key, None)
        else:
            os.environ[key] = value
