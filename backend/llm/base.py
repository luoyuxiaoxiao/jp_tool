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
        - Full-width punctuation mixed into JSON delimiters
        - Missing commas and trailing commas
        - Extra explanatory text before/after JSON
        """
        candidates = self._build_parse_candidates(raw)

        last_error: Exception | None = None
        for candidate in candidates:
            try:
                data = self._try_parse_json(candidate)
                if isinstance(data, dict):
                    return self._build_result(text, data)
            except Exception as e:
                last_error = e

        if last_error:
            logger.warning("Failed to parse LLM JSON: %s", last_error)
        else:
            logger.warning("Failed to parse LLM JSON: no valid JSON object found")

        logger.debug("Raw response preview: %s", raw[:500])
        return DeepResult(
            text=text,
            cultural_context="LLM返回内容不是有效JSON，已保留原始文本片段。\n" + raw[:500],
        )

    def _build_parse_candidates(self, raw: str) -> list[str]:
        extracted = self._extract_json(raw)
        sources = [extracted, raw]
        variants: list[str] = []

        for source in sources:
            if not source:
                continue
            s = source.strip()
            if not s:
                continue

            normalized = self._normalize_json_text(s)
            trimmed = self._trim_to_json_object(normalized)

            variants.extend(
                [
                    s,
                    self._fix_json(s),
                    normalized,
                    self._fix_json(normalized),
                    trimmed,
                    self._fix_json(trimmed),
                ]
            )

        deduped: list[str] = []
        seen: set[str] = set()
        for item in variants:
            t = item.strip()
            if not t or t in seen:
                continue
            seen.add(t)
            deduped.append(t)
        return deduped

    def _try_parse_json(self, s: str) -> dict | None:
        s = s.strip()
        if not s:
            return None

        try:
            obj = json.loads(s)
            if isinstance(obj, dict):
                return obj
        except Exception:
            pass

        decoder = json.JSONDecoder()
        start = s.find("{")
        while start >= 0:
            try:
                obj, _ = decoder.raw_decode(s[start:])
                if isinstance(obj, dict):
                    return obj
            except Exception:
                pass
            start = s.find("{", start + 1)

        return None

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
        # If full stop is mistakenly used as separator, convert to comma.
        s = s.replace('".。', '",')
        s = s.replace('".，', '",')
        s = re.sub(r'"\s*[。．]\s*(?=\s*")', '", ', s)
        s = re.sub(r'"\s*[。．]\s*(?=\s*[}\]])', '"', s)
        # Attempt to补逗号 between object/list end and next key.
        s = re.sub(r"([}\]])\s*(\"[A-Za-z_][A-Za-z0-9_]*\"\s*:)", r"\1, \2", s)
        # Remove control characters
        s = re.sub(r"[\x00-\x1f]", " ", s)
        return s

    def _normalize_json_text(self, s: str) -> str:
        """Normalize full-width punctuation that often breaks JSON parsing."""
        table = {
            "“": '"',
            "”": '"',
            "‘": "'",
            "’": "'",
            "，": ",",
            "：": ":",
            "（": "(",
            "）": ")",
        }
        for a, b in table.items():
            s = s.replace(a, b)
        return s

    def _trim_to_json_object(self, s: str) -> str:
        """Trim text to the first balanced JSON object block if possible."""
        start = s.find("{")
        if start < 0:
            return s

        depth = 0
        in_string = False
        escaped = False
        for i in range(start, len(s)):
            ch = s[i]
            if in_string:
                if escaped:
                    escaped = False
                elif ch == "\\":
                    escaped = True
                elif ch == '"':
                    in_string = False
                continue

            if ch == '"':
                in_string = True
                continue
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return s[start : i + 1]

        # Fallback: clip to last closing brace if full balance not found.
        end = s.rfind("}")
        if end > start:
            return s[start : end + 1]
        return s[start:]

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
