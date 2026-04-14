"""JLPT N1-N5 grammar database and pattern matcher.

Provides:
- match_grammar(text, tokens): match known grammar patterns (Phase 1)
- learn_from_deep_result(deep_result): auto-learn new patterns from LLM output (Phase 2)

The grammar database is loaded from data/jlpt_grammar.json and grows over time.
"""

from __future__ import annotations

import json
import logging
import os
import re
import threading

from .models import GrammarMatch, Token

logger = logging.getLogger(__name__)

_DATA_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "data")
_GRAMMAR_FILE = os.path.join(_DATA_DIR, "jlpt_grammar.json")

# In-memory grammar DB (loaded once, grows via learning)
_grammar_db: list[dict] = []
_known_patterns: set[str] = set()
_lock = threading.Lock()
_loaded = False


def _ensure_loaded():
    """Load grammar DB from disk on first access."""
    global _loaded
    if _loaded:
        return
    with _lock:
        if _loaded:
            return
        _load_from_disk()
        _loaded = True


def _load_from_disk():
    """Load grammar DB from JSON file."""
    global _grammar_db, _known_patterns
    if not os.path.exists(_GRAMMAR_FILE):
        logger.warning("Grammar DB not found at %s, starting empty", _GRAMMAR_FILE)
        _grammar_db = []
        _known_patterns = set()
        return
    try:
        with open(_GRAMMAR_FILE, encoding="utf-8") as f:
            _grammar_db = json.load(f)
        _known_patterns = {e.get("pattern", "") for e in _grammar_db}
        logger.info("Loaded %d grammar patterns from DB", len(_grammar_db))
    except Exception as e:
        logger.error("Failed to load grammar DB: %s", e)
        _grammar_db = []
        _known_patterns = set()


def _save_to_disk():
    """Persist current grammar DB to JSON file."""
    try:
        os.makedirs(_DATA_DIR, exist_ok=True)
        with open(_GRAMMAR_FILE, "w", encoding="utf-8") as f:
            json.dump(_grammar_db, f, ensure_ascii=False, indent=2)
        logger.info("Saved %d grammar patterns to DB", len(_grammar_db))
    except Exception as e:
        logger.error("Failed to save grammar DB: %s", e)


# ── Pattern matching (Phase 1) ───────────────────────────────────────────────


def match_grammar(text: str, tokens: list[Token]) -> list[GrammarMatch]:
    """Match JLPT grammar patterns against the text and its tokens.

    Uses two strategies:
    1. Surface-level regex matching against the original text
    2. Token-sequence matching for patterns that rely on morphological info
    """
    _ensure_loaded()
    matches: list[GrammarMatch] = []
    seen: set[tuple] = set()

    for entry in _grammar_db:
        pattern = entry.get("pattern", "")
        if not pattern:
            continue

        # Strategy 1: regex on surface text
        for regex in entry.get("regexes", [re.escape(pattern)]):
            try:
                for m in re.finditer(regex, text):
                    key = (entry["pattern"], m.start(), m.end())
                    if key not in seen:
                        seen.add(key)
                        matches.append(GrammarMatch(
                            pattern=entry["pattern"],
                            level=entry.get("level", ""),
                            meaning_zh=entry.get("meaning_zh", ""),
                            meaning_ja=entry.get("meaning_ja", ""),
                            example=entry.get("example", ""),
                            start=m.start(),
                            end=m.end(),
                        ))
            except re.error:
                continue

        # Strategy 2: token base-form sequence matching
        token_pattern = entry.get("token_pattern")
        if token_pattern:
            _match_tokens(tokens, token_pattern, entry, matches, seen)

    matches.sort(key=lambda m: (m.start, -len(m.pattern)))
    return matches


def _match_tokens(
    tokens: list[Token],
    pattern_seq: list[dict],
    entry: dict,
    matches: list[GrammarMatch],
    seen: set,
):
    """Match a sequence of token conditions against the token list."""
    plen = len(pattern_seq)
    for i in range(len(tokens) - plen + 1):
        if all(_token_matches(tokens[i + j], cond) for j, cond in enumerate(pattern_seq)):
            key = (entry["pattern"], i, i + plen)
            if key not in seen:
                seen.add(key)
                matches.append(GrammarMatch(
                    pattern=entry["pattern"],
                    level=entry.get("level", ""),
                    meaning_zh=entry.get("meaning_zh", ""),
                    meaning_ja=entry.get("meaning_ja", ""),
                    example=entry.get("example", ""),
                    start=i,
                    end=i + plen,
                ))


def _token_matches(token: Token, cond: dict) -> bool:
    """Check if a single token matches the given conditions."""
    for key, val in cond.items():
        if getattr(token, key, None) != val:
            return False
    return True


# ── Auto-learning from LLM results (Phase 2) ────────────────────────────────


def learn_from_deep_result(deep_result) -> int:
    """Extract new grammar patterns from an LLM DeepResult and add them to DB.

    Returns the number of new patterns learned.
    """
    _ensure_loaded()
    learned = 0

    # Learn from core_grammar entries
    for gp in deep_result.core_grammar:
        if not gp.grammar or gp.grammar in _known_patterns:
            continue

        # Build a regex from the grammar pattern name
        # Use the grammar name itself as a simple regex, escaped
        entry = {
            "pattern": gp.grammar,
            "level": gp.level or "",
            "meaning_zh": gp.function or "",
            "meaning_ja": "",
            "example": "",
            "regexes": [re.escape(gp.grammar)],
            "auto_learned": True,
        }

        with _lock:
            _grammar_db.append(entry)
            _known_patterns.add(gp.grammar)
        learned += 1
        logger.info("Learned new grammar: %s (%s)", gp.grammar, gp.level)

    # Learn from level_annotations (more precise — has actual text spans)
    for ann in deep_result.level_annotations:
        if not ann.grammar or ann.grammar in _known_patterns:
            continue

        entry = {
            "pattern": ann.grammar,
            "level": ann.level or "",
            "meaning_zh": "",
            "meaning_ja": "",
            "example": deep_result.text,
            "regexes": [re.escape(ann.grammar)],
            "auto_learned": True,
        }

        with _lock:
            _grammar_db.append(entry)
            _known_patterns.add(ann.grammar)
        learned += 1
        logger.info("Learned new grammar (annotation): %s (%s)", ann.grammar, ann.level)

    # Persist to disk if we learned anything
    if learned > 0:
        _save_to_disk()

    return learned


def get_stats() -> dict:
    """Return DB statistics."""
    _ensure_loaded()
    manual = sum(1 for e in _grammar_db if not e.get("auto_learned"))
    auto = sum(1 for e in _grammar_db if e.get("auto_learned"))
    by_level = {}
    for e in _grammar_db:
        lvl = e.get("level", "unknown")
        by_level[lvl] = by_level.get(lvl, 0) + 1
    return {"total": len(_grammar_db), "manual": manual, "auto_learned": auto, "by_level": by_level}
