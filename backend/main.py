"""FastAPI backend — WebSocket server + text capture orchestration."""

from __future__ import annotations

import asyncio
import importlib.metadata
import hashlib
import json
import logging
import mimetypes
import os
import subprocess
import sys
from contextlib import asynccontextmanager

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, Response

from analyzer.models import BasicResult, DeepResult
from capture.http_receiver import router as http_router, set_callback

try:
    from backend.storage.settings_store import load_env_from_db, get_runtime_settings, save_runtime_settings
    from backend.storage.analysis_store import (
        get_cached_result,
        upsert_basic_result,
        upsert_deep_result,
        get_recent_results,
        prune_to_limit,
        delete_history_by_text,
        clear_history_all,
    )
    from backend.storage.grammar_store import clear_learned_grammar
except ModuleNotFoundError:
    from storage.settings_store import load_env_from_db, get_runtime_settings, save_runtime_settings
    from storage.analysis_store import (
        get_cached_result,
        upsert_basic_result,
        upsert_deep_result,
        get_recent_results,
        prune_to_limit,
        delete_history_by_text,
        clear_history_all,
    )
    from storage.grammar_store import clear_learned_grammar

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(name)s] %(message)s")
logger = logging.getLogger("jp_tool")

load_env_from_db()


def _resolve_server_host() -> str:
    host = str(os.environ.get("JP_TOOL_HOST", "0.0.0.0")).strip()
    return host or "0.0.0.0"


def _resolve_server_port() -> int:
    raw = str(os.environ.get("JP_TOOL_PORT", "8865")).strip()
    try:
        port = int(raw)
    except Exception:
        logger.warning("Invalid JP_TOOL_PORT=%r, fallback to 8865", raw)
        return 8865

    if port < 1 or port > 65535:
        logger.warning("Out-of-range JP_TOOL_PORT=%r, fallback to 8865", raw)
        return 8865

    return port


_SERVER_HOST = _resolve_server_host()
_SERVER_PORT = _resolve_server_port()


_clipboard_task: asyncio.Task | None = None
_clipboard_enabled = os.environ.get("JP_TOOL_CLIPBOARD", "on").lower() not in {
    "0", "false", "off", "no"
}

_deep_queue: asyncio.PriorityQueue[tuple[int, int, str, dict]] = asyncio.PriorityQueue()
_deep_queue_counter = 0
_deep_queue_pending: set[str] = set()
_deep_queue_inflight: set[str] = set()
_deep_worker_task: asyncio.Task | None = None
_deep_queue_dropped_prefetch = 0

_luna_stream_task: asyncio.Task | None = None
_luna_stream_connected = False


def _text_key(text: str) -> str:
    normalized = (text or "").strip()
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()


def _normalize_luna_ws_origin_url(raw: object) -> str:
    text = str(raw or "").strip()
    if not text:
        return ""

    if text.isdigit():
        return f"ws://127.0.0.1:{int(text)}/api/ws/text/origin"

    if text.startswith("ws://") or text.startswith("wss://"):
        return text

    if text.startswith("http://"):
        ws_url = "ws://" + text[len("http://") :]
    elif text.startswith("https://"):
        ws_url = "wss://" + text[len("https://") :]
    elif ":" in text and "/" not in text:
        ws_url = f"ws://{text}"
    else:
        ws_url = text

    parsed = None
    try:
        from urllib.parse import urlparse

        parsed = urlparse(ws_url)
    except Exception:
        parsed = None

    if parsed and parsed.scheme in {"ws", "wss"}:
        path = parsed.path or ""
        if not path or path == "/":
            return f"{parsed.scheme}://{parsed.netloc}/api/ws/text/origin"
    return ws_url


def _normalize_ginza_split_mode(raw: object) -> str:
    mode = str(raw or "").strip().upper()
    if mode in {"A", "B", "C"}:
        return mode
    return "C"


def _normalize_dependency_focus_style(raw: object) -> str:
    style = str(raw or "").strip().lower()
    if style in {"classic", "vivid"}:
        return style
    return "classic"


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


def _to_bool(value: object, default: bool = False) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return default
    return str(value).strip().lower() in {"1", "true", "on", "yes"}


def _get_grammar_auto_learn_enabled() -> bool:
    settings = get_runtime_settings()
    raw = os.environ.get(
        "JP_TOOL_GRAMMAR_AUTO_LEARN",
        settings.get("JP_TOOL_GRAMMAR_AUTO_LEARN", "on"),
    )
    return _to_bool(raw, default=True)


def _set_grammar_auto_learn_enabled(enabled: bool):
    os.environ["JP_TOOL_GRAMMAR_AUTO_LEARN"] = "on" if enabled else "off"
    save_runtime_settings(
        {
            "JP_TOOL_GRAMMAR_AUTO_LEARN": "on" if enabled else "off",
        }
    )


def _get_deep_auto_analyze_enabled() -> bool:
    raw = os.environ.get("JP_TOOL_DEEP_AUTO_ANALYZE", "on")
    return _to_bool(raw, default=True)


def _set_deep_auto_analyze_enabled(enabled: bool):
    os.environ["JP_TOOL_DEEP_AUTO_ANALYZE"] = "on" if enabled else "off"
    save_runtime_settings(
        {
            "JP_TOOL_DEEP_AUTO_ANALYZE": "on" if enabled else "off",
        }
    )


def _get_follow_mode_enabled() -> bool:
    raw = os.environ.get("JP_TOOL_FOLLOW_MODE", "off")
    return _to_bool(raw, default=False)


def _set_follow_mode_enabled(enabled: bool):
    os.environ["JP_TOOL_FOLLOW_MODE"] = "on" if enabled else "off"
    save_runtime_settings(
        {
            "JP_TOOL_FOLLOW_MODE": "on" if enabled else "off",
        }
    )


def _resource_config_from_settings() -> dict[str, str | bool]:
    settings = get_runtime_settings()
    luna_enabled_raw = os.environ.get(
        "LUNA_WS_ENABLED",
        settings.get("LUNA_WS_ENABLED", "off"),
    )

    queue_max_raw = str(
        os.environ.get(
            "JP_TOOL_QUEUE_MAX_PENDING",
            settings.get("JP_TOOL_QUEUE_MAX_PENDING", "120"),
        )
    ).strip()
    try:
        queue_max_pending = int(queue_max_raw)
    except Exception:
        queue_max_pending = 120
    queue_max_pending = max(10, min(queue_max_pending, 5000))

    drop_prefetch_raw = os.environ.get(
        "JP_TOOL_QUEUE_DROP_PREFETCH_WHEN_BUSY",
        settings.get("JP_TOOL_QUEUE_DROP_PREFETCH_WHEN_BUSY", "on"),
    )

    luna_ws_origin = _normalize_luna_ws_origin_url(
        os.environ.get(
            "LUNA_WS_ORIGIN_URL",
            settings.get("LUNA_WS_ORIGIN_URL", ""),
        )
    )

    return {
        "dictionary_db_path": str(
            os.environ.get(
                "RESOURCE_DICT_DB_PATH",
                settings.get("RESOURCE_DICT_DB_PATH", ""),
            )
        ).strip(),
        "ginza_model_path": str(
            os.environ.get(
                "RESOURCE_GINZA_MODEL_PATH",
                settings.get("RESOURCE_GINZA_MODEL_PATH", ""),
            )
        ).strip(),
        "ginza_split_mode": _normalize_ginza_split_mode(
            os.environ.get(
                "RESOURCE_GINZA_SPLIT_MODE",
                settings.get("RESOURCE_GINZA_SPLIT_MODE", "C"),
            )
        ),
        "dependency_focus_style": _normalize_dependency_focus_style(
            os.environ.get(
                "RESOURCE_DEPENDENCY_FOCUS_STYLE",
                settings.get("RESOURCE_DEPENDENCY_FOCUS_STYLE", "classic"),
            )
        ),
        "onnx_model_path": str(
            os.environ.get(
                "RESOURCE_ONNX_MODEL_PATH",
                settings.get("RESOURCE_ONNX_MODEL_PATH", ""),
            )
        ).strip(),
        "luna_ws_enabled": _to_bool(luna_enabled_raw, default=False),
        "luna_ws_origin_url": luna_ws_origin,
        "queue_max_pending": queue_max_pending,
        "queue_drop_prefetch_when_busy": _to_bool(drop_prefetch_raw, default=True),
    }


def _get_luna_ws_enabled() -> bool:
    raw = os.environ.get("LUNA_WS_ENABLED", "off")
    return _to_bool(raw, default=False)


def _get_luna_ws_origin_url() -> str:
    return _normalize_luna_ws_origin_url(os.environ.get("LUNA_WS_ORIGIN_URL", ""))


def _get_queue_max_pending() -> int:
    try:
        value = int(str(os.environ.get("JP_TOOL_QUEUE_MAX_PENDING", "120")).strip())
    except Exception:
        value = 120
    return max(10, min(value, 5000))


def _get_queue_drop_prefetch_when_busy() -> bool:
    raw = os.environ.get("JP_TOOL_QUEUE_DROP_PREFETCH_WHEN_BUSY", "on")
    return _to_bool(raw, default=True)


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
        "toggle_grammar_auto_learn": _normalize_shortcut(
            os.environ.get(
                "SHORTCUT_TOGGLE_GRAMMAR_AUTO_LEARN",
                settings.get("SHORTCUT_TOGGLE_GRAMMAR_AUTO_LEARN", "ctrl+shift+g"),
            ),
            "ctrl+shift+g",
        ),
        "toggle_auto_follow_luna": _normalize_shortcut(
            os.environ.get(
                "SHORTCUT_TOGGLE_AUTO_FOLLOW_LUNA",
                settings.get("SHORTCUT_TOGGLE_AUTO_FOLLOW_LUNA", "ctrl+shift+f"),
            ),
            "ctrl+shift+f",
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


def _deep_queue_status() -> dict[str, object]:
    return {
        "pending": len(_deep_queue_pending),
        "inflight": len(_deep_queue_inflight),
        "queued_total": _deep_queue.qsize(),
        "max_pending": _get_queue_max_pending(),
        "drop_prefetch_when_busy": _get_queue_drop_prefetch_when_busy(),
        "dropped_prefetch": _deep_queue_dropped_prefetch,
    }


def _parse_tokens_with_optional_ginza(text: str) -> list:
    normalized = str(text or "").strip()
    if not normalized:
        return []

    try:
        from analyzer.ginza_runtime import parse_tokens_with_ginza
    except ModuleNotFoundError:
        try:
            from ginza_runtime import parse_tokens_with_ginza
        except Exception:
            return []

    try:
        split_mode = _normalize_ginza_split_mode(
            os.environ.get("RESOURCE_GINZA_SPLIT_MODE", "C")
        )
        return parse_tokens_with_ginza(normalized, split_mode=split_mode)
    except Exception as exc:
        logger.warning("GiNZA parse skipped: %s", exc)
        return []


def _get_ginza_runtime_status() -> dict[str, object]:
    try:
        from analyzer.ginza_runtime import get_ginza_status
    except ModuleNotFoundError:
        try:
            from ginza_runtime import get_ginza_status
        except Exception as exc:
            return {
                "enabled": False,
                "error": f"GiNZA runtime module unavailable: {exc}",
            }

    try:
        status = get_ginza_status()
        if isinstance(status, dict):
            return status
    except Exception as exc:
        return {
            "enabled": False,
            "error": f"GiNZA status failed: {exc}",
        }

    return {
        "enabled": False,
        "error": "GiNZA status unknown",
    }


async def _ensure_deep_worker_running():
    global _deep_worker_task
    if _deep_worker_task is None or _deep_worker_task.done():
        _deep_worker_task = asyncio.create_task(_deep_worker_loop())


async def _deep_worker_loop():
    logger.info("Deep analysis worker started")
    while True:
        priority, _, text, metadata = await _deep_queue.get()
        key = _text_key(text)
        _deep_queue_pending.discard(key)
        _deep_queue_inflight.add(key)
        try:
            prefetch = _to_bool(metadata.get("prefetch", False), default=False)
            follow_mode = _get_follow_mode_enabled()
            broadcast_result = (not prefetch) or (prefetch and follow_mode)
            source = str(metadata.get("source", "queue") or "queue")
            logger.info(
                "Deep worker consume text (priority=%s, source=%s): %s",
                priority,
                source,
                text[:60],
            )
            await _deep_analysis(text, broadcast_result=broadcast_result, source=source)
        except Exception:
            logger.exception("Deep worker task failed")
        finally:
            _deep_queue_inflight.discard(key)
            _deep_queue.task_done()


async def _enqueue_deep_analysis(
    text: str,
    *,
    priority: int,
    metadata: dict | None = None,
) -> bool:
    global _deep_queue_counter, _deep_queue_dropped_prefetch

    normalized = (text or "").strip()
    if not normalized:
        return False

    meta = dict(metadata or {})
    prefetch = _to_bool(meta.get("prefetch", False), default=False)
    force = _to_bool(meta.get("force", False), default=False)

    backlog = len(_deep_queue_pending) + len(_deep_queue_inflight)
    max_pending = _get_queue_max_pending()
    if not force and backlog >= max_pending:
        if prefetch and _get_queue_drop_prefetch_when_busy():
            _deep_queue_dropped_prefetch += 1
            logger.info(
                "Drop prefetch due queue busy (backlog=%s, max=%s): %s",
                backlog,
                max_pending,
                normalized[:60],
            )
            return False
        logger.warning(
            "Skip enqueue due queue busy (backlog=%s, max=%s): %s",
            backlog,
            max_pending,
            normalized[:60],
        )
        return False

    key = _text_key(normalized)
    if key in _deep_queue_pending or key in _deep_queue_inflight:
        return False

    _deep_queue_counter += 1
    _deep_queue_pending.add(key)
    _deep_queue.put_nowait((priority, _deep_queue_counter, normalized, meta))
    await _ensure_deep_worker_running()
    return True


def _extract_luna_text_message(message: str) -> str:
    raw = str(message or "").strip()
    if not raw:
        return ""

    try:
        parsed = json.loads(raw)
        if isinstance(parsed, str):
            return parsed.strip()
        if isinstance(parsed, dict):
            for key in ("text", "origin", "content", "sentence"):
                value = parsed.get(key)
                if isinstance(value, str) and value.strip():
                    return value.strip()
    except Exception:
        pass

    return raw


async def _stop_luna_stream_task():
    global _luna_stream_task, _luna_stream_connected
    if _luna_stream_task and not _luna_stream_task.done():
        _luna_stream_task.cancel()
        try:
            await _luna_stream_task
        except asyncio.CancelledError:
            pass
    _luna_stream_task = None
    _luna_stream_connected = False


async def _ensure_luna_stream_task():
    global _luna_stream_task

    enabled = _get_luna_ws_enabled()
    url = _get_luna_ws_origin_url()
    if not enabled or not url:
        await _stop_luna_stream_task()
        return

    if _luna_stream_task is None or _luna_stream_task.done():
        _luna_stream_task = asyncio.create_task(_luna_stream_loop())


async def _luna_stream_loop():
    global _luna_stream_connected
    logger.info("Luna stream worker started")

    while True:
        if not _get_luna_ws_enabled():
            _luna_stream_connected = False
            await asyncio.sleep(1.0)
            continue

        url = _get_luna_ws_origin_url()
        if not url:
            _luna_stream_connected = False
            await asyncio.sleep(1.0)
            continue

        try:
            import websockets

            logger.info("Connecting to Luna text stream: %s", url)
            async with websockets.connect(
                url,
                ping_interval=20,
                ping_timeout=20,
                close_timeout=5,
                max_size=2 ** 20,
            ) as ws:
                _luna_stream_connected = True
                logger.info("Luna text stream connected")

                async for message in ws:
                    text = _extract_luna_text_message(str(message))
                    if not text:
                        continue
                    await on_new_text(
                        text,
                        {
                            "source": "luna_ws",
                            "prefetch": True,
                        },
                    )
        except asyncio.CancelledError:
            _luna_stream_connected = False
            raise
        except Exception as e:
            _luna_stream_connected = False
            if _get_luna_ws_enabled():
                logger.warning("Luna stream disconnected: %s", e)
            await asyncio.sleep(2.0)


# ── Lifespan ─────────────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    set_callback(on_new_text)
    await _set_clipboard_enabled(_clipboard_enabled)
    await _ensure_deep_worker_running()
    await _ensure_luna_stream_task()
    visible_host = "localhost" if _SERVER_HOST in {"0.0.0.0", "::"} else _SERVER_HOST
    logger.info("JP Grammar Analyzer backend started on ws://%s:%d/ws", visible_host, _SERVER_PORT)
    yield
    # Shutdown
    await _stop_luna_stream_task()
    if _deep_worker_task and not _deep_worker_task.done():
        _deep_worker_task.cancel()
        try:
            await _deep_worker_task
        except asyncio.CancelledError:
            pass
    await _set_clipboard_enabled(False)


app = FastAPI(title="JP Grammar Analyzer", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])
app.include_router(http_router, prefix="/api")


# ── Serve frontend (prefer Flutter Web) ─────────────────────────────────────

def _frontend_roots() -> list[str]:
    """Frontend search roots in priority order."""
    candidates = [
        os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "frontend", "build", "web")),
        os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "web_frontend")),
        os.path.abspath(os.path.join(os.path.dirname(__file__), "frontend", "web")),
        os.path.abspath(os.path.join(os.path.dirname(__file__), "frontend")),
        os.path.abspath(os.path.join(getattr(sys, "_MEIPASS", ""), "frontend", "web")),
        os.path.abspath(os.path.join(getattr(sys, "_MEIPASS", ""), "frontend")),
    ]

    roots: list[str] = []
    for p in candidates:
        if os.path.isdir(p) and p not in roots:
            roots.append(p)
    return roots


def _resolve_frontend_asset(rel_path: str) -> str | None:
    """Resolve a frontend asset safely from known roots."""
    normalized = (rel_path or "").replace("\\", "/").lstrip("/")
    if not normalized:
        normalized = "index.html"

    normalized = os.path.normpath(normalized).replace("\\", "/")
    if normalized == ".." or normalized.startswith("../"):
        return None

    for root in _frontend_roots():
        candidate = os.path.abspath(os.path.join(root, normalized))
        try:
            if os.path.commonpath([root, candidate]) != root:
                continue
        except ValueError:
            continue
        if os.path.isfile(candidate):
            return candidate

    return None


def _read_text(path: str) -> str:
    with open(path, encoding="utf-8") as f:
        return f.read()


def _read_bytes(path: str) -> bytes:
    with open(path, "rb") as f:
        return f.read()


@app.get("/", response_class=HTMLResponse)
@app.get("/app", response_class=HTMLResponse)
async def serve_frontend():
    """Serve frontend entry, preferring Flutter Web index.html."""
    index = _resolve_frontend_asset("index.html")
    if index:
        return _read_text(index)

    legacy = _resolve_frontend_asset("jp_manager.html")
    if legacy:
        return _read_text(legacy)

    return (
        "<h1>Frontend not found</h1>"
        "<p>Run <code>flutter build web</code> in <code>frontend/</code> first.</p>"
    )


@app.get("/jp_manager.html", response_class=HTMLResponse)
async def serve_jp_manager_html():
    path = _resolve_frontend_asset("jp_manager.html")
    if not path:
        return "<h1>jp_manager.html not found</h1>"
    return _read_text(path)


@app.get("/jp_manager.ccs")
async def serve_jp_manager_ccs():
    path = _resolve_frontend_asset("jp_manager.ccs")
    if not path:
        return Response("/* jp_manager.ccs not found */", media_type="text/css")
    return Response(_read_text(path), media_type="text/css")


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


@app.get("/api/grammar/stats")
async def grammar_stats_alias():
    """Alias for grammar DB statistics."""
    return await grammar_stats()


@app.post("/api/analyze")
async def analyze_text(body: dict):
    """Manually trigger analysis via REST (useful for testing)."""
    text = str(body.get("text", "")).strip()
    if not text:
        return {"error": "empty text"}
    await on_new_text(
        text,
        {
            "source": str(body.get("source", "api_manual") or "api_manual"),
            "prefetch": _to_bool(body.get("prefetch", False), default=False),
            "force": _to_bool(body.get("force", False), default=False),
        },
    )
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
        "api_timeout": os.environ.get("API_TIMEOUT", settings.get("API_TIMEOUT", "60")),
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
        or os.environ.get("API_TIMEOUT", settings.get("API_TIMEOUT", "60"))
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


@app.get("/api/grammar/auto-learn/status")
async def grammar_auto_learn_status():
    """Return grammar auto-learn status."""
    return {
        "status": "ok",
        "enabled": _get_grammar_auto_learn_enabled(),
    }


@app.post("/api/grammar/auto-learn/configure")
async def grammar_auto_learn_configure(body: dict):
    """Enable/disable grammar auto-learning from LLM results."""
    enabled = _to_bool(body.get("enabled", True), default=True)
    _set_grammar_auto_learn_enabled(enabled)
    return {
        "status": "ok",
        "enabled": enabled,
    }


@app.post("/api/grammar/learned/clear")
async def grammar_learned_clear():
    """Clear learned grammar table and refresh in-memory grammar cache."""
    deleted = await asyncio.to_thread(clear_learned_grammar)

    stats = None
    try:
        from analyzer.grammar_db import reset_runtime_cache, get_stats
    except ModuleNotFoundError:
        try:
            from grammar_db import reset_runtime_cache, get_stats
        except Exception:
            reset_runtime_cache = None
            get_stats = None

    if callable(reset_runtime_cache):
        reset_runtime_cache()
    if callable(get_stats):
        stats = await asyncio.to_thread(get_stats)

    return {
        "status": "ok",
        "deleted": deleted,
        "stats": stats,
    }


@app.get("/api/deep/auto/status")
async def deep_auto_status():
    """Return deep analysis auto-trigger status."""
    return {
        "status": "ok",
        "enabled": _get_deep_auto_analyze_enabled(),
    }


@app.post("/api/deep/auto/configure")
async def deep_auto_configure(body: dict):
    """Enable/disable automatic deep analysis on incoming text."""
    enabled = _to_bool(body.get("enabled", True), default=True)
    _set_deep_auto_analyze_enabled(enabled)
    return {
        "status": "ok",
        "enabled": enabled,
    }


@app.get("/api/follow/status")
async def follow_mode_status():
    """Return follow mode status for prefetch display channel."""
    return {
        "status": "ok",
        "enabled": _get_follow_mode_enabled(),
    }


@app.post("/api/follow/configure")
async def follow_mode_configure(body: dict):
    """Enable/disable follow mode for prefetch basic-result display."""
    enabled = _to_bool(body.get("enabled", False), default=False)
    _set_follow_mode_enabled(enabled)
    return {
        "status": "ok",
        "enabled": enabled,
    }


@app.get("/api/resources/config")
async def resources_config_get():
    """Return external resource paths and Luna prefetch config."""
    cfg = _resource_config_from_settings()
    return {
        "status": "ok",
        **cfg,
    }


@app.post("/api/resources/configure")
async def resources_configure(body: dict):
    """Persist external resource paths and Luna prefetch stream settings."""
    incoming = body if isinstance(body, dict) else {}
    persisted: dict[str, str] = {}

    if "dictionary_db_path" in incoming:
        persisted["RESOURCE_DICT_DB_PATH"] = str(incoming.get("dictionary_db_path", "")).strip()
    if "ginza_model_path" in incoming:
        persisted["RESOURCE_GINZA_MODEL_PATH"] = str(incoming.get("ginza_model_path", "")).strip()
    if "ginza_split_mode" in incoming:
        persisted["RESOURCE_GINZA_SPLIT_MODE"] = _normalize_ginza_split_mode(
            incoming.get("ginza_split_mode", "C")
        )
    if "dependency_focus_style" in incoming:
        persisted["RESOURCE_DEPENDENCY_FOCUS_STYLE"] = _normalize_dependency_focus_style(
            incoming.get("dependency_focus_style", "classic")
        )
    if "onnx_model_path" in incoming:
        persisted["RESOURCE_ONNX_MODEL_PATH"] = str(incoming.get("onnx_model_path", "")).strip()
    if "luna_ws_enabled" in incoming:
        persisted["LUNA_WS_ENABLED"] = "on" if _to_bool(incoming.get("luna_ws_enabled", False), default=False) else "off"
    if "luna_ws_origin_url" in incoming:
        persisted["LUNA_WS_ORIGIN_URL"] = _normalize_luna_ws_origin_url(
            incoming.get("luna_ws_origin_url", "")
        )
    if "queue_max_pending" in incoming:
        raw = str(incoming.get("queue_max_pending", "")).strip()
        try:
            value = int(raw)
        except Exception:
            value = _get_queue_max_pending()
        value = max(10, min(value, 5000))
        persisted["JP_TOOL_QUEUE_MAX_PENDING"] = str(value)
    if "queue_drop_prefetch_when_busy" in incoming:
        persisted["JP_TOOL_QUEUE_DROP_PREFETCH_WHEN_BUSY"] = (
            "on"
            if _to_bool(incoming.get("queue_drop_prefetch_when_busy", True), default=True)
            else "off"
        )

    save_runtime_settings(persisted)
    try:
        from analyzer.ginza_runtime import reset_ginza_runtime
    except ModuleNotFoundError:
        try:
            from ginza_runtime import reset_ginza_runtime
        except Exception:
            reset_ginza_runtime = None

    if callable(reset_ginza_runtime):
        reset_ginza_runtime()

    await _stop_luna_stream_task()
    await _ensure_luna_stream_task()

    cfg = _resource_config_from_settings()
    return {
        "status": "ok",
        **cfg,
    }


@app.get("/api/luna/stream/status")
async def luna_stream_status():
    """Return current Luna prefetch stream status."""
    return {
        "status": "ok",
        "enabled": _get_luna_ws_enabled(),
        "origin_url": _get_luna_ws_origin_url(),
        "connected": _luna_stream_connected,
    }


@app.get("/api/analysis/queue/status")
async def analysis_queue_status():
    """Return deep analysis queue status."""
    return {
        "status": "ok",
        **_deep_queue_status(),
        "deep_auto_enabled": _get_deep_auto_analyze_enabled(),
        "luna_stream_connected": _luna_stream_connected,
    }


@app.get("/api/ginza/status")
async def ginza_status():
    """Return GiNZA runtime availability and loaded model info."""
    return {
        "status": "ok",
        **_get_ginza_runtime_status(),
    }


def _check_ginza_package_installed(package_name: str) -> tuple[bool, str]:
    name = str(package_name or "").strip()
    if not name:
        return False, ""

    try:
        version = importlib.metadata.version(name)
        return True, str(version)
    except Exception:
        return False, ""


@app.get("/api/ginza/package-status/{package_name}")
async def ginza_package_status(package_name: str):
    """Return whether a supported GiNZA pip package is already installed."""
    package_name = str(package_name or "").strip()
    if package_name not in {"ja_ginza_electra", "ja_ginza"}:
        return {
            "status": "error",
            "package_name": package_name,
            "installed": False,
            "version": "",
            "error": f"unsupported package: {package_name}",
        }

    installed, version = _check_ginza_package_installed(package_name)
    return {
        "status": "ok",
        "package_name": package_name,
        "installed": installed,
        "version": version,
    }


@app.post("/api/ginza/install")
async def ginza_install(body: dict):
    """Install a supported GiNZA model package via pip and persist it."""
    incoming = body if isinstance(body, dict) else {}
    package_name = str(incoming.get("package_name", "ja_ginza_electra") or "").strip()
    if package_name not in {"ja_ginza_electra", "ja_ginza"}:
        return {
            "status": "error",
            "error": f"unsupported package: {package_name}",
            "package_name": package_name,
        }

    installed, version = _check_ginza_package_installed(package_name)
    if installed:
        save_runtime_settings({"RESOURCE_GINZA_MODEL_PATH": package_name})
        try:
            from analyzer.ginza_runtime import reset_ginza_runtime
        except ModuleNotFoundError:
            try:
                from ginza_runtime import reset_ginza_runtime
            except Exception:
                reset_ginza_runtime = None

        if callable(reset_ginza_runtime):
            reset_ginza_runtime()

        return {
            "status": "ok",
            "package_name": package_name,
            "already_installed": True,
            "version": version,
            "message": f"{package_name} 已安装，无需重复下载",
        }

    command = [sys.executable, "-m", "pip", "install", package_name]

    def _run_install():
        return subprocess.run(command, capture_output=True, text=True, check=False)

    result = await asyncio.to_thread(_run_install)
    stdout = (result.stdout or "").strip()
    stderr = (result.stderr or "").strip()

    if result.returncode != 0:
        return {
            "status": "error",
            "package_name": package_name,
            "error": stderr or stdout or f"pip exited with code {result.returncode}",
        }

    save_runtime_settings({"RESOURCE_GINZA_MODEL_PATH": package_name})
    try:
        from analyzer.ginza_runtime import reset_ginza_runtime
    except ModuleNotFoundError:
        try:
            from ginza_runtime import reset_ginza_runtime
        except Exception:
            reset_ginza_runtime = None

    if callable(reset_ginza_runtime):
        reset_ginza_runtime()

    return {
        "status": "ok",
        "package_name": package_name,
        "already_installed": False,
        "message": f"{package_name} 已安装并写入配置",
        "stdout": stdout[-2000:],
        "stderr": stderr[-2000:],
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
    toggle_grammar_auto_learn = _normalize_shortcut(
        incoming.get("toggle_grammar_auto_learn", current["toggle_grammar_auto_learn"]),
        current["toggle_grammar_auto_learn"],
    )
    toggle_auto_follow_luna = _normalize_shortcut(
        incoming.get("toggle_auto_follow_luna", current["toggle_auto_follow_luna"]),
        current["toggle_auto_follow_luna"],
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
            "SHORTCUT_TOGGLE_GRAMMAR_AUTO_LEARN": toggle_grammar_auto_learn,
            "SHORTCUT_TOGGLE_AUTO_FOLLOW_LUNA": toggle_auto_follow_luna,
            "SHORTCUT_SUBMIT_ANALYZE": submit_analyze,
            "SHORTCUT_FOCUS_INPUT": focus_input,
        }
    )

    return {
        "status": "ok",
        "shortcuts": _get_shortcut_config(),
    }


@app.get("/api/analysis/history")
async def analysis_history(limit: int = 50):
    """Return recent analysis records stored in SQLite (deduplicated by text)."""
    items = await asyncio.to_thread(get_recent_results, max(1, min(limit, 500)))
    return {
        "status": "ok",
        "count": len(items),
        "items": items,
    }


@app.post("/api/analysis/history/prune")
async def analysis_history_prune(body: dict):
    """Prune old analysis records and keep only newest max_rows entries."""
    raw = body.get("max_rows", 1000)
    try:
        max_rows = int(raw)
    except Exception:
        max_rows = 1000

    deleted = await asyncio.to_thread(prune_to_limit, max_rows)
    return {
        "status": "ok",
        "deleted": deleted,
        "max_rows": max_rows,
    }


@app.post("/api/analysis/history/delete")
async def analysis_history_delete(body: dict):
    """Delete one analysis record by exact source text."""
    text = str(body.get("text", "")).strip()
    if not text:
        return {
            "status": "error",
            "error": "empty text",
            "deleted": 0,
        }

    deleted = await asyncio.to_thread(delete_history_by_text, text)
    return {
        "status": "ok",
        "deleted": deleted,
        "text": text,
    }


@app.post("/api/analysis/history/clear")
async def analysis_history_clear():
    """Delete all analysis history/cache records."""
    deleted = await asyncio.to_thread(clear_history_all)
    return {
        "status": "ok",
        "deleted": deleted,
    }


@app.get("/{asset_path:path}")
async def serve_frontend_asset(asset_path: str):
    """Serve frontend static assets with SPA fallback for Flutter Web."""
    path = (asset_path or "").strip("/")

    # Keep API and websocket paths owned by their dedicated routes.
    if path.startswith("api/") or path == "ws":
        return Response("Not Found", status_code=404)

    resolved = _resolve_frontend_asset(path)
    if resolved:
        media_type, _ = mimetypes.guess_type(resolved)
        return Response(
            content=_read_bytes(resolved),
            media_type=media_type or "application/octet-stream",
        )

    # SPA history fallback: non-file paths should return index.html.
    leaf = os.path.basename(path)
    if path and "." not in leaf:
        index = _resolve_frontend_asset("index.html")
        if index:
            return HTMLResponse(_read_text(index))

    return Response("Not Found", status_code=404)


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

async def on_new_text(text: str, metadata: dict | None = None):
    """Handle new text from clipboard/Luna/frontend, with queue+cache strategy."""
    normalized = str(text or "").strip()
    if not normalized:
        return

    meta = metadata if isinstance(metadata, dict) else {}
    source = str(meta.get("source", "unknown") or "unknown").strip() or "unknown"
    prefetch = _to_bool(meta.get("prefetch", False), default=False)
    force = _to_bool(meta.get("force", False), default=False)
    follow_mode = _get_follow_mode_enabled()
    should_broadcast = (not prefetch) or (prefetch and follow_mode)
    logger.info(
        "New text source=%s prefetch=%s force=%s: %s",
        source,
        prefetch,
        force,
        normalized[:60],
    )

    cached = None
    if not force:
        cached = await asyncio.to_thread(get_cached_result, normalized)

    basic: BasicResult | None = None
    if cached and isinstance(cached.get("basic_result"), dict):
        try:
            basic = BasicResult.model_validate(cached["basic_result"])
        except Exception:
            basic = None

    if basic is not None and not basic.tokens:
        # Backfill old cache entries (created before GiNZA token enrichment).
        enriched_tokens = await asyncio.to_thread(_parse_tokens_with_optional_ginza, normalized)
        if enriched_tokens:
            basic = BasicResult(
                text=basic.text,
                tokens=enriched_tokens,
                grammar_matches=basic.grammar_matches,
            )
            await asyncio.to_thread(upsert_basic_result, normalized, basic.model_dump_json())

    if basic is None:
        tokens = await asyncio.to_thread(_parse_tokens_with_optional_ginza, normalized)
        grammar_matches = []
        try:
            from analyzer.grammar_db import match_grammar

            grammar_matches = match_grammar(normalized, tokens)
        except Exception as e:
            logger.error("Local grammar matching failed, fallback to deep-analysis-only mode: %s", e)

        basic = BasicResult(
            text=normalized,
            tokens=tokens,
            grammar_matches=grammar_matches,
        )
        await asyncio.to_thread(upsert_basic_result, normalized, basic.model_dump_json())

    if should_broadcast:
        await broadcast(basic.model_dump_json())

    from llm import get_provider

    provider = get_provider()
    cached_deep: DeepResult | None = None
    if cached and isinstance(cached.get("deep_result"), dict):
        try:
            cached_deep = DeepResult.model_validate(cached["deep_result"])
        except Exception:
            cached_deep = None

    if provider is None:
        if should_broadcast:
            await broadcast(
                cached_deep.model_dump_json()
                if cached_deep is not None
                else DeepResult(text=normalized).model_dump_json()
            )
        return

    if cached_deep is not None and not force:
        if should_broadcast:
            await broadcast(cached_deep.model_dump_json())
        return

    auto_enabled = _get_deep_auto_analyze_enabled()
    should_enqueue = force or prefetch or auto_enabled
    if not should_enqueue:
        if not prefetch:
            await broadcast(
                DeepResult(
                    text=normalized,
                    cultural_context="深度分析已关闭（可在设置中开启自动深度分析，或手动触发）。",
                ).model_dump_json()
            )
        return

    priority = 10 if prefetch else 0
    queued = await _enqueue_deep_analysis(
        normalized,
        priority=priority,
        metadata={
            "source": source,
            "prefetch": prefetch,
            "force": force,
        },
    )

    if not queued and should_broadcast:
        await broadcast(
            DeepResult(
                text=normalized,
                cultural_context="深度分析队列拥塞，已跳过本次入队。可稍后重试或使用手动强制分析。",
            ).model_dump_json()
        )


async def _deep_analysis(
    text: str,
    *,
    broadcast_result: bool = True,
    source: str = "queue",
):
    """Run LLM-based deep grammar analysis, persist result, optionally broadcast."""
    try:
        from llm import get_provider
        provider = get_provider()
        if provider is None:
            return

        logger.info("Deep analysis start source=%s: %s", source, text[:60])
        result = await provider.analyze(text)
        if result:
            if broadcast_result:
                await broadcast(result.model_dump_json())

            try:
                await asyncio.to_thread(upsert_deep_result, text, result.model_dump_json())
            except Exception as persist_error:
                logger.warning("Persist deep result failed: %s", persist_error)

            # Auto-learn failure should not mask a successful deep analysis response.
            try:
                from analyzer.grammar_db import learn_from_deep_result
                n = learn_from_deep_result(result)
                if n > 0:
                    logger.info("Auto-learned %d new grammar patterns", n)
            except Exception as learn_error:
                logger.warning("Auto-learn skipped due error: %s", learn_error)
        else:
            if broadcast_result:
                await broadcast(
                    DeepResult(
                        text=text,
                        cultural_context="深度分析返回为空，请稍后重试。",
                    ).model_dump_json()
                )
    except Exception as e:
        logger.exception("Deep analysis failed for text: %s", text[:80])
        if broadcast_result:
            await broadcast(
                DeepResult(
                    text=text,
                    cultural_context=f"深度分析失败：{e}",
                ).model_dump_json()
            )


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
                    await on_new_text(
                        str(msg["text"]),
                        {
                            "source": "frontend_ws",
                            "prefetch": False,
                            "force": _to_bool(msg.get("force", False), default=False),
                        },
                    )
            except json.JSONDecodeError:
                if data.strip():
                    await on_new_text(
                        data.strip(),
                        {
                            "source": "frontend_ws",
                            "prefetch": False,
                        },
                    )
    except WebSocketDisconnect:
        pass
    finally:
        _clients.discard(ws)
        logger.info("Client disconnected (%d total)", len(_clients))


# ── Run directly ─────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=_SERVER_HOST, port=_SERVER_PORT)
