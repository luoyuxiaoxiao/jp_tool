"""FastAPI backend — WebSocket server + text capture orchestration."""

from __future__ import annotations

import asyncio
import json
import logging
import os
import sys
from contextlib import asynccontextmanager

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse

from analyzer.tokenizer import tokenize_to_models
from analyzer.models import BasicResult
from capture.http_receiver import router as http_router, set_callback

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(name)s] %(message)s")
logger = logging.getLogger("jp_tool")


# ── Lifespan ─────────────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    set_callback(on_new_text)
    from capture.clipboard import watch_clipboard
    task = asyncio.create_task(watch_clipboard(on_new_text))
    logger.info("JP Grammar Analyzer backend started on ws://localhost:8765/ws")
    yield
    # Shutdown
    task.cancel()


app = FastAPI(title="JP Grammar Analyzer", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])
app.include_router(http_router, prefix="/api")


# ── Serve frontend HTML ─────────────────────────────────────────────────────

def _find_frontend_html() -> str | None:
    """Locate the frontend HTML file (works both in dev and packaged mode)."""
    candidates = [
        os.path.join(os.path.dirname(__file__), "..", "test.html"),               # dev
        os.path.join(os.path.dirname(__file__), "frontend", "index.html"),        # packaged
        os.path.join(getattr(sys, "_MEIPASS", ""), "frontend", "index.html"),     # PyInstaller
    ]
    for p in candidates:
        if os.path.isfile(p):
            return os.path.abspath(p)
    return None


@app.get("/", response_class=HTMLResponse)
@app.get("/app", response_class=HTMLResponse)
async def serve_frontend():
    """Serve the frontend HTML — visit http://localhost:8765 in browser."""
    path = _find_frontend_html()
    if path:
        with open(path, encoding="utf-8") as f:
            return f.read()
    return "<h1>Frontend not found</h1><p>Place test.html next to backend/ or frontend/index.html</p>"


# ── REST API endpoints ───────────────────────────────────────────────────────

@app.get("/api/stats")
async def grammar_stats():
    """Return grammar DB statistics."""
    from analyzer.grammar_db import get_stats
    return get_stats()


@app.post("/api/analyze")
async def analyze_text(body: dict):
    """Manually trigger analysis via REST (useful for testing)."""
    text = body.get("text", "").strip()
    if not text:
        return {"error": "empty text"}
    await on_new_text(text)
    return {"status": "ok", "text": text}


@app.get("/api/llm/status")
async def llm_status():
    """Return current LLM provider status."""
    from llm import get_provider
    provider = get_provider()
    if provider is None:
        return {"enabled": False, "provider": None, "model": None}

    info = {"enabled": True, "provider": type(provider).__name__}
    if hasattr(provider, "model"):
        info["model"] = provider.model
    if hasattr(provider, "base_url"):
        info["base_url"] = provider.base_url
    # Check connectivity for Ollama
    if hasattr(provider, "check_available"):
        info["available"] = await provider.check_available()
        info["models"] = await provider.list_models()
    return info


@app.post("/api/llm/configure")
async def llm_configure(body: dict):
    """Reconfigure LLM provider at runtime.

    Body: {"backend": "ollama"|"claude"|"off", "ollama_model": "...", "ollama_url": "..."}
    """
    from llm import reconfigure
    backend = body.get("backend", "")
    kwargs = {}
    if "ollama_model" in body:
        kwargs["OLLAMA_MODEL"] = body["ollama_model"]
    if "ollama_url" in body:
        kwargs["OLLAMA_URL"] = body["ollama_url"]
    if "anthropic_api_key" in body:
        kwargs["ANTHROPIC_API_KEY"] = body["anthropic_api_key"]

    provider = reconfigure(backend, **kwargs)
    return {
        "status": "ok",
        "enabled": provider is not None,
        "provider": type(provider).__name__ if provider else None,
    }


# ── Connected WebSocket clients ──────────────────────────────────────────────

_clients: set[WebSocket] = set()


async def broadcast(message: str):
    """Send a message to all connected WebSocket clients."""
    dead = set()
    for ws in _clients:
        try:
            await ws.send_text(message)
        except Exception:
            dead.add(ws)
    _clients.difference_update(dead)


# ── Analysis pipeline ────────────────────────────────────────────────────────

async def on_new_text(text: str):
    """Handle new text from clipboard or HTTP push."""
    logger.info("New text: %s", text[:60])

    # Phase 1: local tokenization + grammar matching (fast)
    tokens = tokenize_to_models(text)

    from analyzer.grammar_db import match_grammar
    grammar_matches = match_grammar(text, tokens)

    basic = BasicResult(
        text=text,
        tokens=tokens,
        grammar_matches=grammar_matches,
    )
    await broadcast(basic.model_dump_json())

    # Phase 2: LLM deep analysis (async, optional)
    asyncio.create_task(_deep_analysis(text))


async def _deep_analysis(text: str):
    """Run LLM-based deep grammar analysis and broadcast result."""
    try:
        from llm import get_provider
        provider = get_provider()
        if provider is None:
            return
        result = await provider.analyze(text)
        if result:
            await broadcast(result.model_dump_json())
            # Auto-learn new grammar patterns from LLM output
            from analyzer.grammar_db import learn_from_deep_result
            n = learn_from_deep_result(result)
            if n > 0:
                logger.info("Auto-learned %d new grammar patterns", n)
    except Exception as e:
        logger.error("Deep analysis failed: %s", e)


# ── WebSocket endpoint ───────────────────────────────────────────────────────

@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket):
    await ws.accept()
    _clients.add(ws)
    logger.info("Client connected (%d total)", len(_clients))
    try:
        while True:
            data = await ws.receive_text()
            try:
                msg = json.loads(data)
                if msg.get("type") == "analyze" and msg.get("text"):
                    await on_new_text(msg["text"])
            except json.JSONDecodeError:
                if data.strip():
                    await on_new_text(data.strip())
    except WebSocketDisconnect:
        pass
    finally:
        _clients.discard(ws)
        logger.info("Client disconnected (%d total)", len(_clients))


# ── Run directly ─────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8765)
