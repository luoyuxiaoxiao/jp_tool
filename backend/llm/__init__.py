"""LLM provider package.

Supported backends:
- ollama: local Ollama
- api: generic HTTP API provider (openai-compatible or anthropic)
- claude: backward-compatible alias for anthropic API
- off/none: disable deep analysis
"""

from __future__ import annotations

import logging
import os
from urllib.parse import urlsplit, urlunsplit

try:
    from backend.storage.settings_store import load_env_from_db
except ModuleNotFoundError:
    from storage.settings_store import load_env_from_db

logger = logging.getLogger(__name__)

_provider = None
_initialized = False


def get_provider():
    """Return the configured LLM provider, or None if disabled.

    Priority:
    1. JP_TOOL_LLM=ollama  -> Ollama (explicit)
    2. JP_TOOL_LLM=api     -> Generic API (openai/anthropic)
    3. JP_TOOL_LLM=claude  -> Anthropic API (compat alias)
    4. JP_TOOL_LLM not set -> auto-detect Ollama at 127.0.0.1:11434
    """
    global _provider, _initialized
    if _initialized:
        return _provider

    load_env_from_db()

    _initialized = True
    backend = os.environ.get("JP_TOOL_LLM", "auto").lower()

    if backend == "ollama":
        _init_ollama()

    elif backend == "api":
        _init_api()

    elif backend == "claude":
        _init_api(force_format="anthropic")

    elif backend == "anthropic":
        _init_api(force_format="anthropic")

    elif backend == "auto":
        # Auto-detect: try Ollama first
        _init_ollama(silent=True)
        if _provider is None:
            logger.info("No LLM provider detected. Deep analysis disabled.")
            logger.info("  To enable: install Ollama and run 'ollama pull qwen2.5:7b'")
            logger.info("  Or set JP_TOOL_LLM=api and provide API_KEY")

    elif backend == "none" or backend == "off":
        logger.info("LLM provider disabled by config")

    else:
        logger.warning("Unknown JP_TOOL_LLM='%s', ignoring", backend)

    return _provider


def _init_ollama(silent: bool = False):
    """Initialize Ollama provider."""
    global _provider
    model = os.environ.get("OLLAMA_MODEL", "qwen2.5:7b")
    base_url = _normalize_ollama_base_url(
        os.environ.get("OLLAMA_URL", "http://127.0.0.1:11434")
    )

    from .ollama_provider import OllamaProvider
    provider = OllamaProvider(base_url=base_url, model=model)

    # Quick connectivity check (sync, just test HTTP)
    import httpx
    try:
        resp = httpx.get(f"{base_url}/api/tags", timeout=3.0)
        if resp.status_code == 200:
            models = [m["name"] for m in resp.json().get("models", [])]
            found = any(model in m or model.split(":")[0] in m for m in models)
            if found:
                _provider = provider
                logger.info("LLM provider: Ollama (%s at %s)", model, base_url)
            else:
                if not silent:
                    logger.warning(
                        "Ollama running but model '%s' not found. Available: %s",
                        model, ", ".join(models) or "(none)"
                    )
                    logger.warning("Run: ollama pull %s", model)
        else:
            if not silent:
                logger.warning("Ollama returned HTTP %d", resp.status_code)
    except Exception as e:
        if not silent:
            logger.warning("Cannot connect to Ollama at %s: %s", base_url, e)


def _normalize_ollama_base_url(raw: object) -> str:
    text = str(raw or "").strip()
    if not text:
        return "http://127.0.0.1:11434"

    try:
        parts = urlsplit(text)
    except Exception:
        return text

    host = (parts.hostname or "").strip().lower()
    if host != "localhost":
        return text

    netloc = "127.0.0.1"
    if parts.port:
        netloc = f"{netloc}:{parts.port}"
    if parts.username:
        auth = parts.username
        if parts.password:
            auth = f"{auth}:{parts.password}"
        netloc = f"{auth}@{netloc}"

    return urlunsplit(
        (
            parts.scheme or "http",
            netloc,
            parts.path,
            parts.query,
            parts.fragment,
        )
    )


def _init_api(silent: bool = False, force_format: str | None = None):
    """Initialize generic API provider."""
    global _provider

    api_format = (force_format or os.environ.get("API_FORMAT", "openai")).strip().lower()
    if api_format == "claude":
        api_format = "anthropic"

    if api_format not in {"openai", "anthropic"}:
        if not silent:
            logger.warning("Unsupported API_FORMAT='%s' (expected openai/anthropic)", api_format)
        return

    if api_format == "anthropic":
        api_key = os.environ.get("API_KEY") or os.environ.get("ANTHROPIC_API_KEY", "")
        model = os.environ.get("API_MODEL") or os.environ.get(
            "ANTHROPIC_MODEL", "claude-sonnet-4-20250514"
        )
        base_url = os.environ.get("API_BASE_URL") or os.environ.get(
            "ANTHROPIC_BASE_URL", "https://api.anthropic.com"
        )
    else:
        api_key = os.environ.get("API_KEY") or os.environ.get("OPENAI_API_KEY", "")
        model = os.environ.get("API_MODEL") or os.environ.get("OPENAI_MODEL", "gpt-4o-mini")
        base_url = os.environ.get("API_BASE_URL") or os.environ.get(
            "OPENAI_BASE_URL", "https://api.openai.com"
        )

    if not api_key:
        if not silent:
            logger.warning("API key not set. Please set API_KEY.")
        return

    timeout_text = os.environ.get("API_TIMEOUT", "60")
    try:
        timeout = float(timeout_text)
    except Exception:
        timeout = 60.0

    from .api_provider import ApiProvider

    _provider = ApiProvider(
        api_key=api_key,
        model=model,
        base_url=base_url,
        api_format=api_format,
        timeout=timeout,
    )
    logger.info("LLM provider: API (%s, %s)", api_format, model)


def reconfigure(backend: str, **kwargs):
    """Reconfigure LLM provider at runtime (called from settings API)."""
    global _provider, _initialized
    _initialized = False
    _provider = None

    if backend:
        os.environ["JP_TOOL_LLM"] = backend
    for k, v in kwargs.items():
        if v is not None:
            os.environ[k.upper()] = str(v)

    return get_provider()
