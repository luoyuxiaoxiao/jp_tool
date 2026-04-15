"""JLPT N1-N5 grammar database and pattern matcher.

Provides:
- match_grammar(text, tokens): match known grammar patterns (Phase 1)
- learn_from_deep_result(deep_result): auto-learn new patterns from LLM output (Phase 2)

The grammar database is loaded from SQLite first, with optional seed JSON
compatibility when data/jlpt_grammar.json exists.
"""

from __future__ import annotations

import json
import logging
import os
import re
import sys
import threading

try:
    from backend.storage.grammar_store import load_learned_grammar, upsert_learned_grammar
except ModuleNotFoundError:
    from storage.grammar_store import load_learned_grammar, upsert_learned_grammar

from .models import GrammarMatch, Token

logger = logging.getLogger(__name__)


def _grammar_file_candidates() -> list[str]:
    candidates: list[str] = []

    env_file = os.environ.get("JP_TOOL_GRAMMAR_FILE", "").strip()
    if env_file:
        candidates.append(os.path.abspath(env_file))

    env_dir = os.environ.get("JP_TOOL_GRAMMAR_DATA_DIR", "").strip()
    if env_dir:
        candidates.append(os.path.join(os.path.abspath(env_dir), "jlpt_grammar.json"))

    module_root = os.path.dirname(os.path.dirname(__file__))
    candidates.append(os.path.join(module_root, "data", "jlpt_grammar.json"))

    exe_dir = os.path.dirname(getattr(sys, "executable", "") or "")
    if exe_dir:
        candidates.extend([
            os.path.join(exe_dir, "data", "jlpt_grammar.json"),
            os.path.join(exe_dir, "backend", "data", "jlpt_grammar.json"),
            os.path.join(exe_dir, "resources", "backend", "data", "jlpt_grammar.json"),
        ])

    cwd = os.getcwd()
    if cwd:
        candidates.extend([
            os.path.join(cwd, "backend", "data", "jlpt_grammar.json"),
            os.path.join(cwd, "data", "jlpt_grammar.json"),
        ])

    unique: list[str] = []
    seen: set[str] = set()
    for c in candidates:
        n = os.path.abspath(c)
        if n in seen:
            continue
        seen.add(n)
        unique.append(n)

    return unique


def _resolve_grammar_file() -> str:
    candidates = _grammar_file_candidates()
    for path in candidates:
        if os.path.exists(path):
            return path
    return candidates[0] if candidates else os.path.abspath("jlpt_grammar.json")

# In-memory grammar DB (loaded once; DB entries + optional seed JSON compatibility)
_grammar_db: list[dict] = []
_known_patterns: set[str] = set()
_known_pattern_keys: set[str] = set()
_lock = threading.Lock()
_loaded = False

_VALID_LEVELS = {"N1", "N2", "N3", "N4", "N5"}


def _auto_learn_enabled() -> bool:
    return os.environ.get("JP_TOOL_GRAMMAR_AUTO_LEARN", "on").strip().lower() in {
        "1",
        "true",
        "on",
        "yes",
    }


def _pattern_key(pattern: str) -> str:
    """Normalize grammar pattern for duplicate checks."""
    return re.sub(r"\s+", "", (pattern or "")).strip().lower()


def _merge_entry(base: dict, incoming: dict) -> dict:
    """Merge duplicate entries, preferring non-auto-learned and non-empty fields."""
    winner = dict(base)

    base_auto = bool(base.get("auto_learned", False))
    incoming_auto = bool(incoming.get("auto_learned", False))
    if base_auto and not incoming_auto:
        winner = dict(incoming)
    else:
        for key in ("level", "meaning_zh", "meaning_ja", "example", "token_pattern"):
            if not winner.get(key) and incoming.get(key):
                winner[key] = incoming[key]

    base_regexes = base.get("regexes", []) if isinstance(base.get("regexes"), list) else []
    in_regexes = incoming.get("regexes", []) if isinstance(incoming.get("regexes"), list) else []
    merged_regexes: list[str] = []
    seen: set[str] = set()
    for regex in [*base_regexes, *in_regexes]:
        r = str(regex)
        if r not in seen:
            seen.add(r)
            merged_regexes.append(r)
    if merged_regexes:
        winner["regexes"] = merged_regexes

    return winner


def _deduplicate_db(entries: list[dict]) -> list[dict]:
    """Deduplicate grammar DB entries by normalized pattern key."""
    unique: list[dict] = []
    index_by_key: dict[str, int] = {}
    for entry in entries:
        pattern = str(entry.get("pattern", ""))
        key = _pattern_key(pattern)
        if not key:
            continue

        if key in index_by_key:
            idx = index_by_key[key]
            unique[idx] = _merge_entry(unique[idx], entry)
            continue

        index_by_key[key] = len(unique)
        unique.append(entry)
    return unique


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
    """Load grammar DB from SQLite, then merge optional seed JSON."""
    global _grammar_db, _known_patterns, _known_pattern_keys
    grammar_file = _resolve_grammar_file()

    seed_entries: list[dict] = []
    db_entries: list[dict] = []

    try:
        db_entries = _deduplicate_db(load_learned_grammar())

        loaded = []
        if os.path.exists(grammar_file):
            with open(grammar_file, encoding="utf-8") as f:
                loaded = json.load(f)
        else:
            logger.debug("Optional grammar seed JSON not found at %s", grammar_file)

        if not isinstance(loaded, list):
            logger.warning("Grammar seed JSON at %s is not a list; ignored", grammar_file)
            loaded = []

        # Keep JSON as a curated seed file only; strip any historical auto_learned entries.
        seed_entries = [e for e in loaded if isinstance(e, dict) and not e.get("auto_learned")]
        seed_entries = _deduplicate_db(seed_entries)

        if len(seed_entries) != len(loaded):
            logger.info("Sanitized optional seed grammar JSON: %d -> %d", len(loaded), len(seed_entries))
            _save_seed_to_disk(seed_entries, grammar_file)

        _grammar_db = _deduplicate_db([*db_entries, *seed_entries])
        _known_patterns = {e.get("pattern", "") for e in _grammar_db}
        _known_pattern_keys = {_pattern_key(e.get("pattern", "")) for e in _grammar_db if e.get("pattern")}

        logger.info(
            "Loaded grammar patterns: total=%d (db=%d, seed=%d)",
            len(_grammar_db),
            len(db_entries),
            len(seed_entries),
        )
    except Exception as e:
        logger.error("Failed to load grammar DB: %s", e)
        _grammar_db = []
        _known_patterns = set()
        _known_pattern_keys = set()


def _save_seed_to_disk(entries: list[dict], grammar_file: str | None = None):
    """Persist only seed grammar entries to JSON file."""
    try:
        grammar_file = grammar_file or _resolve_grammar_file()
        seed_entries = [e for e in entries if isinstance(e, dict) and not e.get("auto_learned")]
        seed_entries = _deduplicate_db(seed_entries)
        os.makedirs(os.path.dirname(grammar_file), exist_ok=True)
        with open(grammar_file, "w", encoding="utf-8") as f:
            json.dump(seed_entries, f, ensure_ascii=False, indent=2)
        logger.info("Saved %d seed grammar patterns to %s", len(seed_entries), grammar_file)
    except Exception as e:
        logger.error("Failed to save seed grammar DB: %s", e)


def _clean_pattern_text(pattern: str) -> str:
    p = (pattern or "").strip()
    p = re.sub(r"[（(].*?[）)]", "", p).strip()
    return p


def _looks_like_japanese_text(text: str) -> bool:
    return bool(re.search(r"[\u3040-\u30ff\u3400-\u9fff々]", text or ""))


def _valid_level(level: str) -> bool:
    return (level or "").strip().upper() in _VALID_LEVELS


def _is_reasonable_auto_pattern(pattern: str, source_text: str) -> bool:
    p = _clean_pattern_text(pattern)
    if not p or len(p) > 40:
        return False
    if re.search(r"\s", p):
        return False
    if not _looks_like_japanese_text(p):
        return False
    # Require some grounding in original sentence to avoid hallucinated meta labels.
    if p not in (source_text or "") and (pattern or "") not in (source_text or ""):
        return False
    return True


def _annotation_span_pattern(text: str, start: int, end: int) -> str:
    source = text or ""
    if not source:
        return ""

    s = max(0, min(int(start), len(source)))
    e = max(s, min(int(end), len(source)))
    if s >= e:
        return ""

    span = source[s:e].strip()
    return _clean_pattern_text(span)


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

    if not _auto_learn_enabled():
        logger.debug("Grammar auto-learn disabled (JP_TOOL_GRAMMAR_AUTO_LEARN=off)")
        return 0

    learned = 0
    learned_core = 0
    learned_ann = 0

    core_meaning_map: dict[str, str] = {}
    for gp in deep_result.core_grammar:
        k = _pattern_key(gp.grammar or "")
        if not k:
            continue
        v = (gp.function or "").strip()
        if v and k not in core_meaning_map:
            core_meaning_map[k] = v

    # Learn from core_grammar entries
    for gp in deep_result.core_grammar:
        pattern = (gp.grammar or "").strip()
        key = _pattern_key(pattern)
        if not pattern or not key:
            continue
        if key in _known_pattern_keys:
            continue
        if not _valid_level(gp.level):
            continue
        if not _is_reasonable_auto_pattern(pattern, deep_result.text):
            continue

        # Build a regex from the grammar pattern name
        # Use the grammar name itself as a simple regex, escaped
        entry = {
            "pattern": pattern,
            "level": (gp.level or "").upper(),
            "meaning_zh": gp.function or "",
            "meaning_ja": "",
            "example": "",
            "regexes": [re.escape(pattern)],
            "auto_learned": True,
        }

        with _lock:
            if key in _known_pattern_keys:
                continue
            if not upsert_learned_grammar(entry):
                continue
            _grammar_db.append(entry)
            _known_patterns.add(pattern)
            _known_pattern_keys.add(key)
        learned += 1
        learned_core += 1
        logger.info("Learned new grammar: %s (%s)", pattern, entry["level"])

    # Learn from level_annotations (more precise — has actual text spans)
    for ann in deep_result.level_annotations:
        if not _valid_level(ann.level):
            continue

        grammar_name = _clean_pattern_text(ann.grammar or "")
        span_pattern = _annotation_span_pattern(deep_result.text, ann.start, ann.end)

        # Prefer real sentence span first; fallback to LLM grammar label.
        candidates = []
        if span_pattern:
            candidates.append(span_pattern)
        if grammar_name and grammar_name not in candidates:
            candidates.append(grammar_name)

        for pattern in candidates:
            key = _pattern_key(pattern)
            if not pattern or not key:
                continue
            if key in _known_pattern_keys:
                continue
            if not _is_reasonable_auto_pattern(pattern, deep_result.text):
                continue

            regexes = [re.escape(pattern)]
            if span_pattern and span_pattern != pattern:
                regexes.append(re.escape(span_pattern))

            meaning = core_meaning_map.get(_pattern_key(grammar_name), "")
            entry = {
                "pattern": pattern,
                "level": (ann.level or "").upper(),
                "meaning_zh": meaning,
                "meaning_ja": "",
                "example": deep_result.text,
                "regexes": regexes,
                "auto_learned": True,
            }

            with _lock:
                if key in _known_pattern_keys:
                    continue
                if not upsert_learned_grammar(entry):
                    continue
                _grammar_db.append(entry)
                _known_patterns.add(pattern)
                _known_pattern_keys.add(key)
            learned += 1
            learned_ann += 1
            logger.info(
                "Learned new grammar (annotation): %s (%s)",
                pattern,
                entry["level"],
            )
            break

    # Learned entries are persisted in SQLite by upsert_learned_grammar().

    logger.info(
        "Auto-learn summary: learned=%d (core=%d, ann=%d), db_total=%d",
        learned,
        learned_core,
        learned_ann,
        len(_grammar_db),
    )

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
