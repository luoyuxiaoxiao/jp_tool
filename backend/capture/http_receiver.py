"""HTTP receiver — accepts text pushed from LunaTranslator plugin."""

from __future__ import annotations

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
    text = body.get("text", "").strip()
    if text and _text_callback:
        await _text_callback(text)
    return {"status": "ok"}
