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
from fastapi.responses import HTMLResponse, Response

from analyzer.tokenizer import tokenize_to_models
from analyzer.models import BasicResult, DeepResult
from capture.http_receiver import router as http_router, set_callback
from backend.storage.settings_store import load_env_from_db, get_runtime_settings, save_runtime_settings

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(name)s] %(message)s")
logger = logging.getLogger("jp_tool")

load_env_from_db()


_clipboard_task: asyncio.Task | None = None
_clipboard_enabled = os.environ.get("JP_TOOL_CLIPBOARD", "on").lower() not in {
    "0", "false", "off", "no"
}


async def _set_clipboard_enabled(enabled: bool):
    """Enable/disable clipboard watcher at runtime."""
    global _clipboard_enabled, _clipboard_task
    _clipboard_enabled = enabled
    os.environ["JP_TOOL_CLIPBOARD"] = "on" if enabled else "off"

    if enabled:
        if _clipboard_task is None or _clipboard_task.done():
            from capture.clipboard import watch_clipboard

            _clipboard_task = asyncio.create_task(watch_clipboard(on_new_text))
            logger.info("Clipboard monitor enabled")
    else:
        if _clipboard_task and not _clipboard_task.done():
            _clipboard_task.cancel()
            logger.info("Clipboard monitor disabled")
        _clipboard_task = None


def _clipboard_running() -> bool:
    return _clipboard_task is not None and not _clipboard_task.done()


def _normalize_shortcut(value: object, fallback: str) -> str:
    text = str(value or "").strip().lower().replace(" ", "")
    return text or fallback


def _get_shortcut_config() -> dict[str, str]:
    settings = get_runtime_settings()
    return {
        "toggle_clipboard": _normalize_shortcut(
            os.environ.get(
                "SHORTCUT_TOGGLE_CLIPBOARD",
                settings.get("SHORTCUT_TOGGLE_CLIPBOARD", "ctrl+shift+b"),
            ),
            "ctrl+shift+b",
        ),
        "submit_analyze": _normalize_shortcut(
            os.environ.get(
                "SHORTCUT_SUBMIT_ANALYZE",
                settings.get("SHORTCUT_SUBMIT_ANALYZE", "ctrl+enter"),
            ),
            "ctrl+enter",
        ),
        "focus_input": _normalize_shortcut(
            os.environ.get(
                "SHORTCUT_FOCUS_INPUT",
                settings.get("SHORTCUT_FOCUS_INPUT", "ctrl+l"),
            ),
            "ctrl+l",
        ),
    }


# ── Lifespan ─────────────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    set_callback(on_new_text)
    await _set_clipboard_enabled(_clipboard_enabled)
    logger.info("JP Grammar Analyzer backend started on ws://localhost:8765/ws")
    yield
    # Shutdown
    await _set_clipboard_enabled(False)


app = FastAPI(title="JP Grammar Analyzer", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])
app.include_router(http_router, prefix="/api")


# ── Serve frontend HTML ─────────────────────────────────────────────────────

def _find_frontend_file(name: str) -> str | None:
    """Locate frontend files in dev/packaged mode."""
    candidates = [
        os.path.join(os.path.dirname(__file__), "..", name),
        os.path.join(os.path.dirname(__file__), "frontend", name),
        os.path.join(getattr(sys, "_MEIPASS", ""), "frontend", name),
    ]
    for p in candidates:
        if os.path.isfile(p):
            return os.path.abspath(p)
    return None

def _find_frontend_html() -> str | None:
    """Locate the frontend HTML file (works both in dev and packaged mode)."""
    candidates = [
        os.path.join(os.path.dirname(__file__), "..", "jp_manager.html"),         # dev
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
    return "<h1>Frontend not found</h1><p>Place jp_manager.html next to backend/</p>"


@app.get("/jp_manager.html", response_class=HTMLResponse)
async def serve_jp_manager_html():
    path = _find_frontend_file("jp_manager.html")
    if not path:
        return "<h1>jp_manager.html not found</h1>"
    with open(path, encoding="utf-8") as f:
        return f.read()


@app.get("/jp_manager.ccs")
async def serve_jp_manager_ccs():
    path = _find_frontend_file("jp_manager.ccs")
    if not path:
        return Response("/* jp_manager.ccs not found */", media_type="text/css")
    with open(path, encoding="utf-8") as f:
        return Response(f.read(), media_type="text/css")


@app.get("/jp_manager.css")
async def serve_jp_manager_css_alias():
    # Compatibility alias in case browser tools or users request .css
    return await serve_jp_manager_ccs()


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


@app.get("/api/llm/config")
async def llm_config_get():
    """Return current LLM runtime config (persisted in SQLite)."""
    settings = get_runtime_settings()
    backend = os.environ.get("JP_TOOL_LLM", settings.get("JP_TOOL_LLM", "auto"))
    api_format = os.environ.get("API_FORMAT", settings.get("API_FORMAT", "openai"))
    return {
        "backend": backend,
        "ollama_model": os.environ.get("OLLAMA_MODEL", settings.get("OLLAMA_MODEL", "qwen2.5:7b")),
        "ollama_url": os.environ.get("OLLAMA_URL", settings.get("OLLAMA_URL", "http://localhost:11434")),
        "api_format": api_format,
        "api_base_url": os.environ.get("API_BASE_URL", settings.get("API_BASE_URL", "https://api.openai.com")),
        "api_model": os.environ.get("API_MODEL", settings.get("API_MODEL", "gpt-4o-mini")),
        "api_key": os.environ.get("API_KEY", settings.get("API_KEY", "")),
        "api_timeout": os.environ.get("API_TIMEOUT", settings.get("API_TIMEOUT", "30")),
    }


@app.post("/api/llm/models")
async def llm_models(body: dict):
    """Discover available models for current or draft LLM config.

    Body can be the same structure as /api/llm/configure.
    """
    from llm.api_provider import ApiProvider
    from llm.ollama_provider import OllamaProvider

    settings = get_runtime_settings()
    backend = str(
        body.get("backend")
        or os.environ.get("JP_TOOL_LLM", settings.get("JP_TOOL_LLM", "auto"))
    ).strip().lower()

    if backend in {"none", "off", ""}:
        return {
            "status": "error",
            "backend": backend or "off",
            "models": [],
            "error": "LLM backend is disabled",
            "hint": "请先把后端类型改为 Ollama 或 通用API",
        }

    if backend in {"claude", "anthropic"}:
        backend = "api"
        body = dict(body)
        body["api_format"] = "anthropic"

    if backend == "auto":
        return {
            "status": "error",
            "backend": "auto",
            "models": [],
            "error": "Auto backend cannot discover models deterministically",
            "hint": "请先在配置中选择明确的后端（Ollama 或 通用API）",
        }

    if backend == "ollama":
        model = str(
            body.get("ollama_model")
            or os.environ.get("OLLAMA_MODEL", settings.get("OLLAMA_MODEL", "qwen2.5:7b"))
        ).strip()
        base_url = str(
            body.get("ollama_url")
            or os.environ.get("OLLAMA_URL", settings.get("OLLAMA_URL", "http://localhost:11434"))
        ).strip()

        provider = OllamaProvider(base_url=base_url, model=model)
        models = await provider.list_models()
        available = await provider.check_available()

        if models:
            return {
                "status": "ok",
                "backend": "ollama",
                "models": models,
                "available": available,
                "model_count": len(models),
                "base_url": base_url,
            }

        return {
            "status": "error",
            "backend": "ollama",
            "models": [],
            "available": available,
            "error": "No models returned from Ollama",
            "hint": f"请确认 Ollama 已启动，并执行: ollama pull {model}",
            "base_url": base_url,
        }

    if backend != "api":
        return {
            "status": "error",
            "backend": backend,
            "models": [],
            "error": f"Unsupported backend: {backend}",
        }

    api_format = str(
        body.get("api_format")
        or os.environ.get("API_FORMAT", settings.get("API_FORMAT", "openai"))
    ).strip().lower()
    if api_format == "claude":
        api_format = "anthropic"

    api_key = str(
        body.get("api_key")
        or os.environ.get("API_KEY", settings.get("API_KEY", ""))
    ).strip()
    if not api_key:
        return {
            "status": "error",
            "backend": "api",
            "models": [],
            "error": "API key is empty",
            "hint": "请先填写 API Key 后再获取模型列表",
        }

    base_url_default = "https://api.anthropic.com" if api_format == "anthropic" else "https://api.openai.com"
    base_url = str(
        body.get("api_base_url")
        or os.environ.get("API_BASE_URL", settings.get("API_BASE_URL", base_url_default))
    ).strip()

    model_default = "claude-sonnet-4-20250514" if api_format == "anthropic" else "gpt-4o-mini"
    model = str(
        body.get("api_model")
        or os.environ.get("API_MODEL", settings.get("API_MODEL", model_default))
    ).strip() or model_default

    timeout_text = str(
        body.get("api_timeout")
        or os.environ.get("API_TIMEOUT", settings.get("API_TIMEOUT", "30"))
    ).strip()
    try:
        timeout = max(5.0, float(timeout_text))
    except Exception:
        timeout = 30.0

    provider = ApiProvider(
        api_key=api_key,
        model=model,
        base_url=base_url,
        api_format=api_format,
        timeout=timeout,
    )
    detail = await provider.list_models_detailed()
    raw_models = detail.get("models")
    models = [str(x) for x in raw_models] if isinstance(raw_models, list) else []

    if detail.get("ok") is True:
        return {
            "status": "ok",
            "backend": "api",
            "api_format": api_format,
            "base_url": base_url,
            "models": models,
            "model_count": len(models),
            "used_url": detail.get("used_url"),
        }

    status_code = detail.get("status_code")
    hint = "请检查 API Key、Base URL、API 格式是否匹配。"
    if status_code == 404:
        hint = "接口返回404：请确认 Base URL 与 API 格式是否匹配（OpenAI兼容通常是 https://.../v1）。"

    return {
        "status": "error",
        "backend": "api",
        "api_format": api_format,
        "base_url": base_url,
        "models": models,
        "status_code": status_code,
        "error": detail.get("error") or "Failed to fetch models",
        "attempts": detail.get("attempts", []),
        "hint": hint,
    }


@app.post("/api/llm/configure")
async def llm_configure(body: dict):
    """Reconfigure LLM provider at runtime.

    Body examples:
    - {"backend": "ollama", "ollama_model": "qwen2.5:7b"}
    - {"backend": "api", "api_format": "openai", "api_base_url": "...", "api_key": "...", "api_model": "..."}
    - {"backend": "off"}
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
    if "api_key" in body:
        kwargs["API_KEY"] = body["api_key"]
    if "api_model" in body:
        kwargs["API_MODEL"] = body["api_model"]
    if "api_base_url" in body:
        kwargs["API_BASE_URL"] = body["api_base_url"]
    if "api_format" in body:
        kwargs["API_FORMAT"] = body["api_format"]

    persisted = {}
    if backend:
        persisted["JP_TOOL_LLM"] = backend
    if "ollama_model" in body:
        persisted["OLLAMA_MODEL"] = body["ollama_model"]
    if "ollama_url" in body:
        persisted["OLLAMA_URL"] = body["ollama_url"]
    if "api_key" in body:
        persisted["API_KEY"] = body["api_key"]
    if "api_model" in body:
        persisted["API_MODEL"] = body["api_model"]
    if "api_base_url" in body:
        persisted["API_BASE_URL"] = body["api_base_url"]
    if "api_format" in body:
        persisted["API_FORMAT"] = body["api_format"]
    if "api_timeout" in body:
        persisted["API_TIMEOUT"] = body["api_timeout"]

    save_runtime_settings(persisted)
    provider = reconfigure(backend, **kwargs)
    return {
        "status": "ok",
        "enabled": provider is not None,
        "provider": type(provider).__name__ if provider else None,
    }


@app.get("/api/clipboard/status")
async def clipboard_status():
    """Return clipboard monitor status."""
    return {
        "enabled": _clipboard_enabled,
        "running": _clipboard_running(),
    }


@app.post("/api/clipboard/configure")
async def clipboard_configure(body: dict):
    """Enable or disable clipboard monitoring at runtime.

    Body: {"enabled": true|false}
    """
    enabled = bool(body.get("enabled", True))
    await _set_clipboard_enabled(enabled)
    save_runtime_settings({"JP_TOOL_CLIPBOARD": "on" if enabled else "off"})
    return {
        "status": "ok",
        "enabled": _clipboard_enabled,
        "running": _clipboard_running(),
    }


@app.get("/api/shortcuts/config")
async def shortcuts_config_get():
    return {
        "status": "ok",
        "shortcuts": _get_shortcut_config(),
    }


@app.post("/api/shortcuts/configure")
async def shortcuts_configure(body: dict):
    raw_shortcuts = body.get("shortcuts")
    incoming = raw_shortcuts if isinstance(raw_shortcuts, dict) else body
    if not isinstance(incoming, dict):
        incoming = {}
    current = _get_shortcut_config()

    toggle_clipboard = _normalize_shortcut(
        incoming.get("toggle_clipboard", current["toggle_clipboard"]),
        current["toggle_clipboard"],
    )
    submit_analyze = _normalize_shortcut(
        incoming.get("submit_analyze", current["submit_analyze"]),
        current["submit_analyze"],
    )
    focus_input = _normalize_shortcut(
        incoming.get("focus_input", current["focus_input"]),
        current["focus_input"],
    )

    save_runtime_settings(
        {
            "SHORTCUT_TOGGLE_CLIPBOARD": toggle_clipboard,
            "SHORTCUT_SUBMIT_ANALYZE": submit_analyze,
            "SHORTCUT_FOCUS_INPUT": focus_input,
        }
    )

    return {
        "status": "ok",
        "shortcuts": _get_shortcut_config(),
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
    from llm import get_provider
    if get_provider() is None:
        # Return an empty deep result to let clients close loading states.
        await broadcast(DeepResult(text=text).model_dump_json())
        return

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
        else:
            await broadcast(DeepResult(text=text).model_dump_json())
    except Exception as e:
        logger.error("Deep analysis failed: %s", e)
        await broadcast(DeepResult(text=text).model_dump_json())


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
