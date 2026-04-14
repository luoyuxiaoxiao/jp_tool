"""Abstract base class for LLM providers."""

from __future__ import annotations

import json
import logging
import re
from abc import ABC, abstractmethod

from analyzer.models import (
    DeepResult, GrammarPoint, SentenceComponent, GrammarTreeNode,
    ComparisonGroup, ComparisonItem, CommonMistake, LevelAnnotation,
)

logger = logging.getLogger(__name__)


class BaseLLMProvider(ABC):
    """Abstract LLM provider for deep grammar analysis."""

    @abstractmethod
    async def _call(self, prompt: str) -> str:
        """Send prompt to LLM and return raw response text."""
        ...

    async def analyze(self, text: str) -> DeepResult | None:
        """Run deep grammar analysis on the given Japanese text."""
        from .prompt_templates import build_analysis_prompt
        prompt = build_analysis_prompt(text)

        try:
            raw = await self._call(prompt)
            return self._parse_response(text, raw)
        except Exception as e:
            logger.error("LLM analysis failed: %s", e)
            return None

    def _parse_response(self, text: str, raw: str) -> DeepResult:
        """Parse LLM JSON response into DeepResult model.

        Handles common LLM output issues:
        - Markdown code blocks wrapping JSON
        - Trailing commas
        - Comments in JSON
        - Partial/truncated JSON
        """
        json_str = self._extract_json(raw)

        try:
            data = json.loads(json_str)
        except json.JSONDecodeError:
            # Try fixing common issues
            fixed = self._fix_json(json_str)
            try:
                data = json.loads(fixed)
            except json.JSONDecodeError as e:
                logger.warning("Failed to parse LLM JSON: %s", e)
                logger.debug("Raw response: %s", raw[:300])
                return DeepResult(text=text, cultural_context=raw[:500])

        return self._build_result(text, data)

    def _extract_json(self, raw: str) -> str:
        """Extract JSON from LLM response, handling code blocks."""
        # Try ```json ... ``` first
        m = re.search(r"```json\s*\n?(.*?)```", raw, re.DOTALL)
        if m:
            return m.group(1).strip()

        # Try ``` ... ```
        m = re.search(r"```\s*\n?(.*?)```", raw, re.DOTALL)
        if m:
            return m.group(1).strip()

        # Try finding { ... } directly
        m = re.search(r"\{.*\}", raw, re.DOTALL)
        if m:
            return m.group(0).strip()

        return raw.strip()

    def _fix_json(self, s: str) -> str:
        """Fix common JSON issues from LLM output."""
        # Remove trailing commas before } or ]
        s = re.sub(r",\s*([}\]])", r"\1", s)
        # Remove single-line comments
        s = re.sub(r"//.*$", "", s, flags=re.MULTILINE)
        # Remove control characters
        s = re.sub(r"[\x00-\x1f]", " ", s)
        return s

    def _build_result(self, text: str, data: dict) -> DeepResult:
        """Safely build DeepResult from parsed JSON dict."""
        return DeepResult(
            text=text,
            core_grammar=self._safe_list(data, "core_grammar", GrammarPoint),
            sentence_breakdown=self._safe_list(data, "sentence_breakdown", SentenceComponent),
            grammar_tree=self._safe_list(data, "grammar_tree", GrammarTreeNode),
            comparisons=self._safe_comparisons(data.get("comparisons", [])),
            common_mistakes=self._safe_list(data, "common_mistakes", CommonMistake),
            cultural_context=str(data.get("cultural_context", "")),
            applications=[str(a) for a in data.get("applications", []) if a],
            level_annotations=self._safe_list(data, "level_annotations", LevelAnnotation),
        )

    def _safe_list(self, data: dict, key: str, cls):
        """Safely parse a list of model objects, skipping bad entries."""
        result = []
        for item in data.get(key, []):
            if not isinstance(item, dict):
                continue
            try:
                result.append(cls(**item))
            except Exception as e:
                logger.debug("Skipping bad %s entry: %s", key, e)
        return result

    def _safe_comparisons(self, raw_list) -> list[ComparisonGroup]:
        """Safely parse comparison groups."""
        result = []
        if not isinstance(raw_list, list):
            return result
        for cg in raw_list:
            if not isinstance(cg, dict):
                continue
            try:
                items = []
                for item in cg.get("items", []):
                    if isinstance(item, dict):
                        try:
                            items.append(ComparisonItem(**item))
                        except Exception:
                            pass
                result.append(ComparisonGroup(
                    category=str(cg.get("category", "")),
                    items=items,
                ))
            except Exception:
                pass
        return result
