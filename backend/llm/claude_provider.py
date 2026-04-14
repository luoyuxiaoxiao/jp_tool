"""Claude API provider (Anthropic specialization)."""

from __future__ import annotations

from .api_provider import ApiProvider


class ClaudeProvider(ApiProvider):
    def __init__(self, api_key: str, model: str = "claude-sonnet-4-20250514"):
        super().__init__(
            api_key=api_key,
            model=model,
            base_url="https://api.anthropic.com",
            api_format="anthropic",
        )
