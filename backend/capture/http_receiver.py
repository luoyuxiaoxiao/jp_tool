"""HTTP receiver — accepts text pushed from LunaTranslator plugin."""

from __future__ import annotations

import inspect

from fastapi import APIRouter

router = APIRouter()

# Will be set by main.py at startup
_text_callback = None


def set_callback(cb):
    global _text_callback
    _text_callback = cb


@router.post("/text")
async def receive_text(body: dict):
    """Receive text from LunaTranslator plugin.

    Expected body: {"text": "日本語テキスト"}
    """
    payload = body if isinstance(body, dict) else {}
    text = str(payload.get("text", "")).strip()
    if text and _text_callback:
        try:
            maybe = _text_callback(text, payload)
            if inspect.isawaitable(maybe):
                await maybe
        except TypeError:
            # Backward compatibility for old callback signature: cb(text)
            maybe = _text_callback(text)
            if inspect.isawaitable(maybe):
                await maybe
    return {"status": "ok"}
