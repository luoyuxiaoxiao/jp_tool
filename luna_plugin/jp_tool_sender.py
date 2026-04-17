"""LunaTranslator -> JP Tool bridge plugin.

This plugin pushes source text to JP Tool backend using a non-blocking HTTP call.
Compared with the original minimal version, it now includes metadata that allows
backend-side prefetch queueing and cache reuse.
"""

from __future__ import annotations

import json
import threading
import time
import urllib.request


# Backend endpoint (keep default fixed port unless explicitly changed).
JP_TOOL_URL = "http://127.0.0.1:8865/api/text"

# Network timeout (seconds), keep short to avoid impacting game loop.
TIMEOUT = 2

# Mark these messages as prefetch tasks so backend can queue them in low priority.
PREFETCH = True

# Lightweight sender identity for backend logs/metrics.
SOURCE = "luna_plugin"

# Skip immediate duplicates in a short time window (milliseconds).
DEDUP_WINDOW_MS = 220

_SEQ_LOCK = threading.Lock()
_SEQ = 0

_LAST_LOCK = threading.Lock()
_LAST_TEXT = ""
_LAST_TS_MS = 0


def _next_seq() -> int:
    global _SEQ
    with _SEQ_LOCK:
        _SEQ += 1
        return _SEQ


def _now_ms() -> int:
    return int(time.time() * 1000)


def _should_skip_duplicate(text: str) -> bool:
    global _LAST_TEXT, _LAST_TS_MS
    now = _now_ms()

    with _LAST_LOCK:
        same_text = text == _LAST_TEXT
        too_close = (now - _LAST_TS_MS) <= DEDUP_WINDOW_MS
        if same_text and too_close:
            return True

        _LAST_TEXT = text
        _LAST_TS_MS = now
        return False


def _build_payload(text: str, args, kwargs) -> dict:
    payload = {
        "text": text,
        "source": SOURCE,
        "prefetch": PREFETCH,
        "sequence": _next_seq(),
        "timestamp_ms": _now_ms(),
    }

    # Best-effort extraction for optional metadata from different plugin call styles.
    for key in ("speaker", "name", "role"):
        value = kwargs.get(key)
        if isinstance(value, str) and value.strip():
            payload["speaker"] = value.strip()
            break

    for key in ("trans", "translated", "translation", "translated_text"):
        value = kwargs.get(key)
        if isinstance(value, str) and value.strip():
            payload["translated_text"] = value.strip()
            break

    if args:
        payload["args_count"] = len(args)

    return payload


def _send_payload(payload: dict):
    try:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        req = urllib.request.Request(
            JP_TOOL_URL,
            data=data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=TIMEOUT):
            pass
    except Exception:
        # Silent fail to avoid affecting game flow.
        pass


def send_to_analyzer(text: str, *args, **kwargs):
    normalized = str(text or "").strip()
    if not normalized:
        return
    if _should_skip_duplicate(normalized):
        return

    payload = _build_payload(normalized, args, kwargs)
    t = threading.Thread(target=_send_payload, args=(payload,), daemon=True)
    t.start()


def output(text: str, *args, **kwargs):
    """LunaTranslator output plugin entrypoint."""
    send_to_analyzer(text, *args, **kwargs)


def copytranslator(text: str, *args, **kwargs):
    """LunaTranslator copytranslator plugin entrypoint."""
    send_to_analyzer(text, *args, **kwargs)
