"""Ollama local LLM provider with robust error handling."""

from __future__ import annotations

import json
import logging

import httpx

from .base import BaseLLMProvider

logger = logging.getLogger(__name__)


class OllamaProvider(BaseLLMProvider):
    def __init__(self, base_url: str = "http://127.0.0.1:11434", model: str = "qwen2.5:7b"):
        self.base_url = base_url.rstrip("/")
        self.model = model
        self._available = None  # cached availability check

    async def check_available(self) -> bool:
        """Check if Ollama is running and the model is available."""
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.get(f"{self.base_url}/api/tags")
                resp.raise_for_status()
                models = [m["name"] for m in resp.json().get("models", [])]
                # Match model name (with or without :latest tag)
                found = any(
                    self.model in m or self.model.split(":")[0] in m
                    for m in models
                )
                if not found:
                    logger.warning(
                        "Model '%s' not found in Ollama. Available: %s",
                        self.model, ", ".join(models) or "(none)",
                    )
                return found
        except Exception as e:
            logger.error("Cannot connect to Ollama at %s: %s", self.base_url, e)
            return False

    async def list_models(self) -> list[str]:
        """List all available models in Ollama."""
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.get(f"{self.base_url}/api/tags")
                resp.raise_for_status()
                return [m["name"] for m in resp.json().get("models", [])]
        except Exception:
            return []

    async def _call(self, prompt: str) -> str:
        """Call Ollama API with retry logic."""
        # Check availability on first call
        if self._available is None:
            self._available = await self.check_available()
            if not self._available:
                raise RuntimeError(
                    f"Ollama model '{self.model}' not available. "
                    f"Run: ollama pull {self.model}"
                )

        last_error = None
        for attempt in range(2):  # 1 retry
            try:
                async with httpx.AsyncClient(timeout=120.0) as client:
                    resp = await client.post(
                        f"{self.base_url}/api/generate",
                        json={
                            "model": self.model,
                            "prompt": prompt,
                            "stream": False,
                            "options": {
                                "temperature": 0.3,
                                "num_predict": 4096,
                            },
                        },
                    )
                    resp.raise_for_status()
                    data = resp.json()

                    response_text = data.get("response", "")
                    # Log timing info
                    if "total_duration" in data:
                        secs = data["total_duration"] / 1e9
                        logger.info(
                            "Ollama response: %.1fs, %d tokens",
                            secs,
                            data.get("eval_count", 0),
                        )
                    return response_text

            except httpx.TimeoutException:
                last_error = "Timeout (>120s)"
                logger.warning("Ollama timeout, attempt %d/2", attempt + 1)
            except httpx.HTTPStatusError as e:
                last_error = f"HTTP {e.response.status_code}"
                logger.warning("Ollama HTTP error: %s", e)
            except Exception as e:
                last_error = str(e)
                logger.warning("Ollama error: %s", e)

        raise RuntimeError(f"Ollama failed after 2 attempts: {last_error}")
