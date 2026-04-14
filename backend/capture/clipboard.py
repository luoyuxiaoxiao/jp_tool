"""Clipboard monitor — watches for new Japanese text on the clipboard."""

from __future__ import annotations

import asyncio
import logging
import re

logger = logging.getLogger(__name__)

# Match text that contains at least one Japanese character
_JP_RE = re.compile(r"[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF\uFF66-\uFF9F]")


def _has_japanese(text: str) -> bool:
    return bool(_JP_RE.search(text))


async def watch_clipboard(callback, interval: float = 0.3):
    """Poll clipboard for new Japanese text and invoke *callback(text)*.

    Uses pyperclip. Falls back gracefully if unavailable.
    """
    try:
        import pyperclip
    except ImportError:
        logger.warning("pyperclip not installed — clipboard monitoring disabled")
        return

    last = ""
    logger.info("Clipboard monitor started (interval=%.1fs)", interval)
    while True:
        try:
            current = pyperclip.paste()
        except Exception:
            await asyncio.sleep(interval)
            continue

        if current and current != last and _has_japanese(current):
            last = current
            text = current.strip()
            if text:
                logger.debug("Clipboard new text: %s", text[:40])
                await callback(text)

        await asyncio.sleep(interval)
