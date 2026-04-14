"""LLM provider package — auto-detects Ollama if available."""

from __future__ import annotations

import logging
import os

logger = logging.getLogger(__name__)

_provider = None
_initialized = False


def get_provider():
    """Return the configured LLM provider, or None if disabled.

    Priority:
    1. JP_TOOL_LLM=claude  → Claude API (needs ANTHROPIC_API_KEY)
    2. JP_TOOL_LLM=ollama  → Ollama (explicit)
    3. JP_TOOL_LLM not set → auto-detect Ollama at localhost:11434
    """
    global _provider, _initialized
    if _initialized:
        return _provider

    _initialized = True
    backend = os.environ.get("JP_TOOL_LLM", "auto").lower()

    if backend == "claude":
        api_key = os.environ.get("ANTHROPIC_API_KEY", "")
        if api_key:
            from .claude_provider import ClaudeProvider
            _provider = ClaudeProvider(api_key)
            logger.info("LLM provider: Claude API")
        else:
            logger.warning("ANTHROPIC_API_KEY not set, Claude provider disabled")

    elif backend == "ollama":
        _init_ollama()

    elif backend == "auto":
        # Auto-detect: try Ollama first
        _init_ollama(silent=True)
        if _provider is None:
            logger.info("No LLM provider detected. Deep analysis disabled.")
            logger.info("  To enable: install Ollama and run 'ollama pull qwen2.5:7b'")
            logger.info("  Or set JP_TOOL_LLM=claude with ANTHROPIC_API_KEY")

    elif backend == "none" or backend == "off":
        logger.info("LLM provider disabled by config")

    else:
        logger.warning("Unknown JP_TOOL_LLM='%s', ignoring", backend)

    return _provider


def _init_ollama(silent: bool = False):
    """Initialize Ollama provider."""
    global _provider
    model = os.environ.get("OLLAMA_MODEL", "qwen2.5:7b")
    base_url = os.environ.get("OLLAMA_URL", "http://localhost:11434")

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
