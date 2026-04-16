"""Optional GiNZA parser + JA->ZH dictionary lookup.

This module is best-effort: if spaCy/GiNZA is not installed, it returns
empty token lists without breaking the main analysis flow.
"""

from __future__ import annotations

import json
import logging
import os
import sqlite3
import threading
from functools import lru_cache
from pathlib import Path

try:
    from .models import Token
except Exception:
    from models import Token

logger = logging.getLogger("jp_tool.ginza")

_NLP = None
_NLP_READY = False
_NLP_ERROR = ""
_NLP_SPLIT_MODE = ""
_NLP_LOCK = threading.Lock()


def _resolve_existing_path(raw: str) -> str:
    text = (raw or "").strip()
    if not text:
        return ""

    p = Path(text).expanduser()
    candidates: list[Path] = []

    if p.is_absolute():
        candidates.append(p)
    else:
        project_root = Path(__file__).resolve().parents[2]
        candidates.extend(
            [
                Path.cwd() / p,
                project_root / p,
                p,
            ]
        )

    for c in candidates:
        try:
            if c.is_file():
                return str(c.resolve())
        except Exception:
            continue

    return ""


def _ginza_model_candidates() -> list[str]:
    raw = str(os.environ.get("RESOURCE_GINZA_MODEL_PATH", "")).strip()
    explicit = str(os.environ.get("JP_TOOL_GINZA_MODEL", "")).strip()

    out: list[str] = []
    if raw:
        resolved = _resolve_existing_path(raw)
        out.append(resolved or raw)
    if explicit:
        out.append(explicit)

    # Common package model names.
    out.extend(["ja_ginza_electra", "ja_ginza"])
    return out


def _normalize_split_mode(raw: str) -> str:
    mode = str(raw or "").strip().upper()
    if mode in {"A", "B", "C"}:
        return mode
    return "C"


def _configured_split_mode(split_mode: str = "") -> str:
    requested = str(split_mode or "").strip()
    if requested:
        return _normalize_split_mode(requested)
    env_mode = str(os.environ.get("RESOURCE_GINZA_SPLIT_MODE", "")).strip()
    if env_mode:
        return _normalize_split_mode(env_mode)
    return "C"


def _apply_split_mode(nlp, split_mode: str) -> str:
    global _NLP_SPLIT_MODE

    mode = _configured_split_mode(split_mode)
    if nlp is None:
        return mode

    applied = False

    try:
        import ginza

        setter = getattr(ginza, "set_split_mode", None)
        if callable(setter):
            setter(nlp, mode)
            applied = True
    except Exception:
        applied = False

    tokenizer = getattr(nlp, "tokenizer", None)

    if not applied and tokenizer is not None:
        setter = getattr(tokenizer, "set_split_mode", None)
        if callable(setter):
            try:
                setter(mode)
                applied = True
            except Exception:
                applied = False

    if not applied and tokenizer is not None:
        for attr in ("split_mode", "mode"):
            if not hasattr(tokenizer, attr):
                continue
            try:
                setattr(tokenizer, attr, mode)
                applied = True
                break
            except Exception:
                continue

    if applied:
        _NLP_SPLIT_MODE = mode

    return mode


def _load_nlp():
    global _NLP, _NLP_READY, _NLP_ERROR, _NLP_SPLIT_MODE

    if _NLP_READY:
        return _NLP

    with _NLP_LOCK:
        if _NLP_READY:
            return _NLP

        try:
            import spacy
        except Exception as exc:
            _NLP_READY = True
            _NLP = None
            _NLP_ERROR = f"spacy import failed: {exc}"
            logger.warning("GiNZA unavailable: %s", _NLP_ERROR)
            return None

        last_err = ""
        for candidate in _ginza_model_candidates():
            try:
                _NLP = spacy.load(candidate)
                _NLP_SPLIT_MODE = ""
                configured_mode = _configured_split_mode()
                _apply_split_mode(_NLP, configured_mode)
                _NLP_READY = True
                _NLP_ERROR = ""
                logger.info("GiNZA model loaded: %s", candidate)
                return _NLP
            except Exception as exc:
                last_err = f"{candidate}: {exc}"

        _NLP_READY = True
        _NLP = None
        _NLP_ERROR = f"no GiNZA model could be loaded ({last_err})"
        logger.warning("GiNZA unavailable: %s", _NLP_ERROR)
        return None


def get_ginza_status() -> dict[str, object]:
    nlp = _load_nlp()
    if nlp is None:
        return {
            "enabled": False,
            "split_mode": _configured_split_mode(),
            "error": _NLP_ERROR,
        }

    model_name = ""
    try:
        model_name = str(nlp.meta.get("name", ""))
    except Exception:
        model_name = ""

    return {
        "enabled": True,
        "model": model_name,
        "split_mode": _NLP_SPLIT_MODE or _configured_split_mode(),
    }


def _resolve_dict_db_path(dict_db_path: str = "") -> str:
    explicit = (dict_db_path or "").strip()
    if explicit:
        resolved = _resolve_existing_path(explicit)
        return resolved or ""

    env_path = str(os.environ.get("RESOURCE_DICT_DB_PATH", "")).strip()
    if not env_path:
        return ""

    return _resolve_existing_path(env_path)


def _unique_keep_order(values: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for v in values:
        item = (v or "").strip()
        if not item or item in seen:
            continue
        seen.add(item)
        out.append(item)
    return out


@lru_cache(maxsize=50000)
def _lookup_zh_cached(dict_path: str, term: str, limit: int) -> tuple[str, ...]:
    if not dict_path or not term:
        return tuple()

    term = term.strip()
    if not term:
        return tuple()

    try:
        conn = sqlite3.connect(f"file:{dict_path}?mode=ro", uri=True)
    except Exception:
        return tuple()

    try:
        cur = conn.cursor()
        tables = {
            str(row[0])
            for row in cur.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            ).fetchall()
        }

        # jamdict style
        if {"SenseGloss", "Sense", "Kana", "Kanji"}.issubset(tables):
            rows = cur.execute(
                """
                SELECT DISTINCT sg.text
                FROM SenseGloss sg
                JOIN Sense s ON s.ID = sg.sid
                LEFT JOIN Kana k ON k.idseq = s.idseq
                LEFT JOIN Kanji kj ON kj.idseq = s.idseq
                WHERE sg.lang = 'chn'
                  AND (k.text = ? OR kj.text = ?)
                LIMIT ?
                """,
                (term, term, int(max(1, limit))),
            ).fetchall()
            return tuple(_unique_keep_order([str(r[0]) for r in rows if r and r[0]]))

        # compact jmdict style
        if {"entries", "senses"}.issubset(tables):
            rows = cur.execute(
                """
                SELECT glosses
                FROM senses
                WHERE lang IN ('chi', 'chn')
                  AND ent_seq IN (
                    SELECT ent_seq
                    FROM entries
                    WHERE kana = ? OR kanji = ?
                  )
                LIMIT ?
                """,
                (term, term, int(max(1, limit))),
            ).fetchall()

            decoded: list[str] = []
            for row in rows:
                if not row or not row[0]:
                    continue
                raw = str(row[0])
                try:
                    arr = json.loads(raw)
                    if isinstance(arr, list):
                        decoded.extend([str(x) for x in arr if str(x).strip()])
                    else:
                        decoded.append(raw)
                except Exception:
                    decoded.append(raw)

            return tuple(_unique_keep_order(decoded)[: max(1, limit)])

    except Exception:
        return tuple()
    finally:
        conn.close()

    return tuple()


def _lookup_meaning_zh(dict_path: str, lemma: str, surface: str, limit: int = 2) -> str:
    if not dict_path:
        return ""

    candidates = _unique_keep_order([lemma, surface])
    for candidate in candidates:
        values = _lookup_zh_cached(dict_path, candidate, limit)
        if values:
            return " / ".join(values[:limit])

    return ""


_DICT_LOOKUP_ALLOWED_POS = {
    "NOUN",
    "PROPN",
    "VERB",
    "ADJ",
    "ADV",
    "NUM",
    "PRON",
    "INTJ",
    "SYM",
}


def _should_lookup_meaning(pos: str, surface: str, is_punctuation: bool) -> bool:
    if is_punctuation:
        return False

    text = str(surface or "").strip()
    if not text:
        return False

    pos_tag = str(pos or "").strip().upper()
    if pos_tag and pos_tag not in _DICT_LOOKUP_ALLOWED_POS:
        return False

    return True


def _is_tameni_pair(first: Token, second: Token) -> bool:
    first_surface = str(first.surface or "").strip()
    first_base = str(first.base or "").strip()
    second_surface = str(second.surface or "").strip()
    second_base = str(second.base or "").strip()

    if (second_surface != "に") and (second_base != "に"):
        return False

    return first_surface in {"ため", "為"} or first_base in {"ため", "為"}


def _apply_phrase_meaning_overrides(tokens: list[Token]):
    if not tokens:
        return

    for i in range(len(tokens) - 1):
        first = tokens[i]
        second = tokens[i + 1]
        if _is_tameni_pair(first, second):
            first.meaning_zh = "ために（语法）：为了（表目的）/因为（表原因）"
            second.meaning_zh = "与前词构成「ために」语法"


def parse_tokens_with_ginza(
    text: str,
    *,
    dict_db_path: str = "",
    meaning_limit: int = 2,
    split_mode: str = "",
) -> list[Token]:
    normalized = (text or "").strip()
    if not normalized:
        return []

    nlp = _load_nlp()
    if nlp is None:
        return []

    target_mode = _configured_split_mode(split_mode)
    if _NLP_SPLIT_MODE != target_mode:
        _apply_split_mode(nlp, target_mode)

    try:
        doc = nlp(normalized)
    except Exception as exc:
        logger.warning("GiNZA parse failed: %s", exc)
        return []

    spacy_tokens = [t for t in doc if not t.is_space]
    if not spacy_tokens:
        return []

    index_map = {token.i: idx for idx, token in enumerate(spacy_tokens)}
    dict_path = _resolve_dict_db_path(dict_db_path)

    out: list[Token] = []
    for idx, token in enumerate(spacy_tokens):
        reading = ""
        conjugation = ""

        try:
            readings = token.morph.get("Reading")
            if readings:
                reading = str(readings[0])
        except Exception:
            reading = ""

        try:
            inflections = token.morph.get("Inflection")
            if inflections:
                conjugation = ",".join([str(x) for x in inflections if str(x).strip()])
        except Exception:
            conjugation = ""

        surface = str(token.text)
        lemma = str(token.lemma_ or surface)
        head_index = index_map.get(token.head.i, idx)

        pos = str(token.pos_ or "")
        is_punctuation = bool(token.is_punct)
        if _should_lookup_meaning(pos, surface, is_punctuation):
            meaning_zh = _lookup_meaning_zh(dict_path, lemma, surface, meaning_limit)
        else:
            meaning_zh = ""

        out.append(
            Token(
                surface=surface,
                reading=reading,
                pos=pos,
                pos_detail=str(token.tag_ or ""),
                base=lemma,
                conjugation=conjugation,
                index=idx,
                head_index=head_index,
                dep=str(token.dep_ or ""),
                char_start=int(token.idx),
                char_end=int(token.idx + len(surface)),
                meaning_zh=meaning_zh,
                is_punctuation=is_punctuation,
            )
        )

    _apply_phrase_meaning_overrides(out)

    return out
