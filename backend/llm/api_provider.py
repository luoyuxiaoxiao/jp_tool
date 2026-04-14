"""Generic HTTP API LLM provider.

Supports two wire formats:
- openai: /v1/chat/completions (OpenAI-compatible APIs)
- anthropic: /v1/messages
"""

from __future__ import annotations

import logging

import httpx

from .base import BaseLLMProvider

logger = logging.getLogger(__name__)


class ApiProvider(BaseLLMProvider):
    def __init__(
        self,
        api_key: str,
        model: str,
        base_url: str,
        api_format: str = "openai",
        timeout: float = 30.0,
    ):
        self.api_key = api_key.strip()
        self.model = model.strip()
        self.base_url = base_url.rstrip("/")
        self.api_format = api_format.lower().strip() or "openai"
        self.timeout = timeout

    def _url(self, path: str) -> str:
        path = path.lstrip("/")
        base = self.base_url
        if base.endswith("/v1") and path.startswith("v1/"):
            path = path[3:]
        return f"{base}/{path}"

    def _extract_model_ids(self, data: object) -> list[str]:
        """Extract model IDs from OpenAI-compatible or vendor-custom payloads."""
        if isinstance(data, dict):
            items = data.get("data")
            if isinstance(items, list):
                result = []
                for item in items:
                    if isinstance(item, dict):
                        model_id = item.get("id") or item.get("model") or item.get("name")
                        if model_id:
                            result.append(str(model_id))
                return result

            # Some providers return {"models": [...]} instead of {"data": [...]}.
            items = data.get("models")
            if isinstance(items, list):
                result = []
                for item in items:
                    if isinstance(item, dict):
                        model_id = item.get("id") or item.get("model") or item.get("name")
                        if model_id:
                            result.append(str(model_id))
                    elif isinstance(item, str):
                        result.append(item)
                return result

        if isinstance(data, list):
            result = []
            for item in data:
                if isinstance(item, str):
                    result.append(item)
                elif isinstance(item, dict):
                    model_id = item.get("id") or item.get("model") or item.get("name")
                    if model_id:
                        result.append(str(model_id))
            return result

        return []

    async def list_models_detailed(self) -> dict[str, object]:
        """Fetch model list with diagnostics for UI-facing configuration."""
        attempts: list[dict[str, object]] = []
        urls: list[str] = []
        for path in ("v1/models", "models"):
            url = self._url(path)
            if url not in urls:
                urls.append(url)

        async with httpx.AsyncClient(timeout=max(self.timeout, 8.0)) as client:
            for url in urls:
                try:
                    resp = await client.get(url, headers=self._auth_headers())
                except Exception as e:
                    attempts.append({
                        "url": url,
                        "error": str(e),
                    })
                    continue

                if resp.status_code >= 400:
                    body_preview = ""
                    try:
                        body_preview = (resp.text or "").strip().replace("\n", " ")[:220]
                    except Exception:
                        body_preview = ""

                    attempts.append({
                        "url": url,
                        "status_code": resp.status_code,
                        "error": body_preview or f"HTTP {resp.status_code}",
                    })
                    continue

                try:
                    data = resp.json()
                except Exception:
                    attempts.append({
                        "url": url,
                        "status_code": resp.status_code,
                        "error": "Response is not valid JSON",
                    })
                    continue

                models = sorted(set(self._extract_model_ids(data)))
                return {
                    "ok": True,
                    "models": models,
                    "used_url": url,
                    "attempts": attempts,
                }

        # No successful endpoint.
        status_code = None
        for item in reversed(attempts):
            if isinstance(item.get("status_code"), int):
                status_code = item.get("status_code")
                break

        return {
            "ok": False,
            "models": [],
            "status_code": status_code,
            "error": "Unable to fetch model list from provider",
            "attempts": attempts,
        }

    async def check_available(self) -> bool:
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.get(
                    self._url("v1/models"),
                    headers=self._auth_headers(),
                )
                return resp.status_code == 200
        except Exception:
            return False

    async def list_models(self) -> list[str]:
        try:
            detail = await self.list_models_detailed()
            models = detail.get("models")
            if isinstance(models, list):
                return [str(x) for x in models]
            return []
        except Exception:
            return []

    def _auth_headers(self) -> dict[str, str]:
        if self.api_format == "anthropic":
            return {
                "x-api-key": self.api_key,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            }
        return {
            "Authorization": f"Bearer {self.api_key}",
            "content-type": "application/json",
        }

    async def _call(self, prompt: str) -> str:
        if self.api_format == "anthropic":
            return await self._call_anthropic(prompt)
        return await self._call_openai(prompt)

    async def _call_openai(self, prompt: str) -> str:
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            resp = await client.post(
                self._url("v1/chat/completions"),
                headers=self._auth_headers(),
                json={
                    "model": self.model,
                    "messages": [{"role": "user", "content": prompt}],
                    "temperature": 0.3,
                    "max_tokens": 4096,
                },
            )
            resp.raise_for_status()
            data = resp.json()

        choices = data.get("choices", []) if isinstance(data, dict) else []
        if not choices:
            raise RuntimeError("API response has no choices")

        message = choices[0].get("message", {})
        content = message.get("content", "")

        if isinstance(content, str):
            return content

        # Some APIs return content as blocks.
        if isinstance(content, list):
            chunks = []
            for item in content:
                if isinstance(item, dict):
                    text = item.get("text")
                    if text:
                        chunks.append(str(text))
            if chunks:
                return "\n".join(chunks)

        raise RuntimeError("API response content format unsupported")

    async def _call_anthropic(self, prompt: str) -> str:
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            resp = await client.post(
                self._url("v1/messages"),
                headers=self._auth_headers(),
                json={
                    "model": self.model,
                    "max_tokens": 4096,
                    "messages": [{"role": "user", "content": prompt}],
                },
            )
            resp.raise_for_status()
            data = resp.json()

        blocks = data.get("content", []) if isinstance(data, dict) else []
        chunks = []
        for block in blocks:
            if isinstance(block, dict) and block.get("text"):
                chunks.append(str(block["text"]))
        if chunks:
            return "\n".join(chunks)

        raise RuntimeError("Anthropic response content is empty")
