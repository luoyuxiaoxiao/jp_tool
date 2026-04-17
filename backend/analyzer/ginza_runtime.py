"""Optional GiNZA parser + JA->ZH dictionary lookup.

This module is best-effort: if spaCy/GiNZA is not installed, it returns
empty token lists without breaking the main analysis flow.
"""

from __future__ import annotations

import json
import logging
import math
import os
import sqlite3
import sys
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


def _resolve_existing_path(raw: str, *, allow_dir: bool = True) -> str:
    text = (raw or "").strip()
    if not text:
        return ""

    p = Path(text).expanduser()
    candidates: list[Path] = []

    if p.is_absolute():
        candidates.append(p)
    else:
        project_root = Path(__file__).resolve().parents[2]
        exe_dir = Path(getattr(sys, "executable", "") or "").resolve().parent
        candidates.extend(
            [
                Path.cwd() / p,
                exe_dir / p,
                project_root / p,
                p,
            ]
        )

    for c in candidates:
        try:
            if c.is_file():
                return str(c.resolve())
            if allow_dir and c.is_dir():
                return str(c.resolve())
        except Exception:
            continue

    return ""


def _ginza_model_candidates() -> list[str]:
    raw = str(os.environ.get("RESOURCE_GINZA_MODEL_PATH", "")).strip()
    explicit = str(os.environ.get("JP_TOOL_GINZA_MODEL", "")).strip()

    out: list[str] = []
    if raw:
        resolved = _resolve_existing_path(raw, allow_dir=True)
        out.append(resolved or raw)
    if explicit:
        out.append(explicit)
    return out


def reset_ginza_runtime():
    global _NLP, _NLP_READY, _NLP_ERROR, _NLP_SPLIT_MODE

    with _NLP_LOCK:
        _NLP = None
        _NLP_READY = False
        _NLP_ERROR = ""
        _NLP_SPLIT_MODE = ""


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
        resolved = _resolve_existing_path(explicit, allow_dir=False)
        return resolved or ""

    env_path = str(os.environ.get("RESOURCE_DICT_DB_PATH", "")).strip()
    if not env_path:
        return ""

    return _resolve_existing_path(env_path, allow_dir=False)


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

_UD_MERGE_DEPS = {
    "fixed",
    "compound",
}

_UD_JOIN_MARKER_SURFACES = {
    "・",
    "･",
    "ー",
    "ｰ",
}

_UPOS_TO_JMDICT_POS_KEYWORDS = {
    "NOUN": ["noun", "futsuumeishi", "suru"],
    "PROPN": ["noun", "proper"],
    "VERB": ["verb", "ichidan", "godan", "kuru", "suru"],
    "AUX": ["auxiliary", "copula"],
    "ADJ": ["adjective", "keiyoushi", "adjectival", "keiyodoshi"],
    "ADV": ["adverb", "fukushi"],
    "PRON": ["pronoun"],
    "NUM": ["number", "numeric", "counter"],
    "ADP": ["particle", "joshi", "postposition", "case"],
    "PART": ["particle", "joshi"],
    "SCONJ": ["conjunction", "particle"],
    "CCONJ": ["conjunction"],
    "DET": ["determiner", "prenominal"],
    "INTJ": ["interjection"],
    "SYM": ["symbol"],
}

_SENSE_JOIN_SEP = "\u241E"


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


def _dep_label(token) -> str:
    return str(getattr(token, "dep_", "") or "").strip().lower()


def _is_join_marker_surface(text: str) -> bool:
    return str(text or "") in _UD_JOIN_MARKER_SURFACES


def _is_join_marker_token(token) -> bool:
    return _is_join_marker_surface(str(getattr(token, "text", "") or ""))


def _should_merge_by_ud_core(spacy_tokens: list, index_map: dict[int, int], left_idx: int, right_idx: int) -> bool:
    left = spacy_tokens[left_idx]
    right = spacy_tokens[right_idx]

    left_dep = _dep_label(left)
    right_dep = _dep_label(right)
    left_head = index_map.get(left.head.i, left_idx)
    right_head = index_map.get(right.head.i, right_idx)

    if left_dep in _UD_MERGE_DEPS and left_head == right_idx:
        return True
    if right_dep in _UD_MERGE_DEPS and right_head == left_idx:
        return True

    return False


def _should_merge_across_join_marker(spacy_tokens: list, index_map: dict[int, int], left_idx: int, right_idx: int) -> bool:
    left = spacy_tokens[left_idx]
    right = spacy_tokens[right_idx]

    if _is_join_marker_token(right):
        bridge_idx = right_idx + 1
        if bridge_idx < len(spacy_tokens):
            bridge = spacy_tokens[bridge_idx]
            if not bool(bridge.is_punct):
                return _should_merge_by_ud_core(spacy_tokens, index_map, left_idx, bridge_idx)

    if _is_join_marker_token(left):
        bridge_idx = left_idx - 1
        if bridge_idx >= 0:
            bridge = spacy_tokens[bridge_idx]
            if not bool(bridge.is_punct):
                return _should_merge_by_ud_core(spacy_tokens, index_map, bridge_idx, right_idx)

    return False


def _should_merge_adjacent_by_ud(spacy_tokens: list, index_map: dict[int, int], left_idx: int, right_idx: int) -> bool:
    if left_idx < 0 or right_idx <= left_idx or right_idx >= len(spacy_tokens):
        return False

    left = spacy_tokens[left_idx]
    right = spacy_tokens[right_idx]

    if _is_join_marker_token(left) or _is_join_marker_token(right):
        if _should_merge_across_join_marker(spacy_tokens, index_map, left_idx, right_idx):
            return True

    if bool(left.is_punct) or bool(right.is_punct):
        return False

    return _should_merge_by_ud_core(spacy_tokens, index_map, left_idx, right_idx)


def _build_ud_merge_groups(spacy_tokens: list, index_map: dict[int, int]) -> list[list[int]]:
    if not spacy_tokens:
        return []

    groups: list[list[int]] = []
    current: list[int] = [0]
    for i in range(len(spacy_tokens) - 1):
        if _should_merge_adjacent_by_ud(spacy_tokens, index_map, i, i + 1):
            current.append(i + 1)
        else:
            groups.append(current)
            current = [i + 1]
    groups.append(current)
    return groups


def _pick_representative_raw_index(group_indices: list[int], spacy_tokens: list, index_map: dict[int, int]) -> int:
    if not group_indices:
        return 0

    group_set = set(group_indices)

    for raw_idx in group_indices:
        if _dep_label(spacy_tokens[raw_idx]) == "root":
            return raw_idx

    for raw_idx in group_indices:
        head_raw = index_map.get(spacy_tokens[raw_idx].head.i, raw_idx)
        if head_raw not in group_set:
            return raw_idx

    return group_indices[0]


def _safe_reading(token) -> str:
    try:
        readings = token.morph.get("Reading")
        if readings:
            return str(readings[0])
    except Exception:
        pass
    return ""


def _safe_conjugation(token) -> str:
    try:
        inflections = token.morph.get("Inflection")
        if inflections:
            return ",".join([str(x) for x in inflections if str(x).strip()])
    except Exception:
        pass
    return ""


def _decode_blob_values(blob: object) -> list[str]:
    text = str(blob or "").strip()
    if not text:
        return []

    values = [part.strip() for part in text.split(_SENSE_JOIN_SEP)]
    return _unique_keep_order([v for v in values if v])


@lru_cache(maxsize=30000)
def _lookup_sense_candidates_cached(
    dict_path: str,
    term: str,
    sense_limit: int,
) -> tuple[tuple[int, tuple[str, ...], tuple[str, ...], tuple[str, ...]], ...]:
    if not dict_path or not term:
        return tuple()

    q = str(term or "").strip()
    if not q:
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

        if {"SenseGloss", "Sense", "Kana", "Kanji", "pos"}.issubset(tables):
            rows = cur.execute(
                """
                SELECT s.ID,
                       COALESCE((SELECT GROUP_CONCAT(text, ?) FROM pos WHERE sid = s.ID), ''),
                       COALESCE((SELECT GROUP_CONCAT(text, ?) FROM SenseGloss WHERE sid = s.ID AND lang = 'chn'), ''),
                       COALESCE((SELECT GROUP_CONCAT(text, ?) FROM SenseGloss WHERE sid = s.ID AND lang = 'eng'), '')
                FROM Sense s
                WHERE s.idseq IN (
                    SELECT idseq FROM Kana WHERE text = ?
                    UNION
                    SELECT idseq FROM Kanji WHERE text = ?
                )
                LIMIT ?
                """,
                (_SENSE_JOIN_SEP, _SENSE_JOIN_SEP, _SENSE_JOIN_SEP, q, q, int(max(1, sense_limit))),
            ).fetchall()

            out: list[tuple[int, tuple[str, ...], tuple[str, ...], tuple[str, ...]]] = []
            for sid, pos_blob, zh_blob, eng_blob in rows:
                pos_tags = tuple(_decode_blob_values(pos_blob))
                zh_glosses = tuple(_decode_blob_values(zh_blob))
                eng_glosses = tuple(_decode_blob_values(eng_blob))
                if not zh_glosses and not eng_glosses:
                    continue
                out.append((int(sid or 0), pos_tags, zh_glosses, eng_glosses))

            return tuple(out)

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
                (q, q, int(max(1, sense_limit))),
            ).fetchall()

            out: list[tuple[int, tuple[str, ...], tuple[str, ...], tuple[str, ...]]] = []
            for i, row in enumerate(rows):
                if not row or not row[0]:
                    continue
                raw = str(row[0])
                zh_glosses: list[str] = []
                try:
                    arr = json.loads(raw)
                    if isinstance(arr, list):
                        zh_glosses.extend([str(x) for x in arr if str(x).strip()])
                    else:
                        zh_glosses.append(raw)
                except Exception:
                    zh_glosses.append(raw)

                cleaned = tuple(_unique_keep_order(zh_glosses))
                if cleaned:
                    out.append((i + 1, tuple(), cleaned, tuple()))

            return tuple(out)

    except Exception:
        return tuple()
    finally:
        conn.close()

    return tuple()


def _lookup_sense_candidates(dict_path: str, lemma: str, surface: str, sense_limit: int = 24) -> list[dict[str, object]]:
    if not dict_path:
        return []

    terms = _unique_keep_order([surface, lemma])
    combined: dict[int, dict[str, object]] = {}

    for term in terms:
        candidates = _lookup_sense_candidates_cached(dict_path, term, sense_limit)
        for sid, pos_tags, zh_glosses, eng_glosses in candidates:
            if sid not in combined:
                combined[sid] = {
                    "sid": sid,
                    "pos_tags": list(pos_tags),
                    "zh_glosses": list(zh_glosses),
                    "eng_glosses": list(eng_glosses),
                }
                continue

            item = combined[sid]
            item["pos_tags"] = _unique_keep_order(list(item.get("pos_tags", [])) + list(pos_tags))
            item["zh_glosses"] = _unique_keep_order(list(item.get("zh_glosses", [])) + list(zh_glosses))
            item["eng_glosses"] = _unique_keep_order(list(item.get("eng_glosses", [])) + list(eng_glosses))

    return list(combined.values())


def _pos_keywords_for_upos(upos: str) -> list[str]:
    return _UPOS_TO_JMDICT_POS_KEYWORDS.get(str(upos or "").strip().upper(), [])


def _pos_match_candidate(upos: str, candidate_pos_tags: list[str]) -> bool:
    if not candidate_pos_tags:
        return True

    keywords = _pos_keywords_for_upos(upos)
    if not keywords:
        return True

    lowered_tags = [str(t or "").lower() for t in candidate_pos_tags]
    for tag in lowered_tags:
        for keyword in keywords:
            if keyword in tag:
                return True
    return False


def _sense_pos_prior_score(dep_label: str, group_size: int, candidate_pos_tags: list[str]) -> float:
    score = 0.0
    tags_text = " ".join([str(t or "").lower() for t in candidate_pos_tags])

    if dep_label == "fixed":
        if "expressions" in tags_text:
            score += 0.45
        if "adverb" in tags_text or "fukushi" in tags_text:
            score += 0.2
        if "particle" in tags_text or "joshi" in tags_text:
            score += 0.12
    elif dep_label == "compound":
        if "noun" in tags_text:
            score += 0.3
        if "prefix" in tags_text or "suffix" in tags_text:
            score += 0.12

    if group_size > 1 and "expressions" in tags_text:
        score += 0.08

    return score


def _is_katakana_surface(text: str) -> bool:
    s = str(text or "").strip()
    if not s:
        return False

    for ch in s:
        code = ord(ch)
        if ch in _UD_JOIN_MARKER_SURFACES:
            continue
        if 0x30A0 <= code <= 0x30FF:
            continue
        return False
    return True


def _extract_group_syntax_features(
    spacy_tokens: list,
    index_map: dict[int, int],
    group_indices: list[int],
    representative_raw: int,
) -> dict[str, bool]:
    if not group_indices:
        return {
            "has_child_no_case": False,
            "has_child_ka_mark": False,
            "has_child_subject": False,
            "has_child_nominal": False,
            "has_following_suru": False,
            "is_katakana_surface": False,
        }

    group_set = set(group_indices)

    children_by_parent: dict[int, list[int]] = {}
    for raw_idx, tok in enumerate(spacy_tokens):
        parent = index_map.get(tok.head.i, raw_idx)
        if parent == raw_idx:
            continue
        children_by_parent.setdefault(parent, []).append(raw_idx)

    child_raw_indices: list[int] = []
    child_tokens = []
    for raw_idx in group_indices:
        for child_idx in children_by_parent.get(raw_idx, []):
            if child_idx in group_set:
                continue
            child_raw_indices.append(child_idx)
            child_tokens.append(spacy_tokens[child_idx])

    if child_raw_indices:
        seen_child: set[int] = set()
        dedup_raw: list[int] = []
        dedup_tokens = []
        for raw_idx, tok in zip(child_raw_indices, child_tokens):
            if raw_idx in seen_child:
                continue
            seen_child.add(raw_idx)
            dedup_raw.append(raw_idx)
            dedup_tokens.append(tok)
        child_raw_indices = dedup_raw
        child_tokens = dedup_tokens

    child_surfaces = [str(tok.text or "").strip() for tok in child_tokens]
    child_deps = [_dep_label(tok) for tok in child_tokens]

    def _child_has_no_case_marker(child_raw_idx: int) -> bool:
        for grand_idx in children_by_parent.get(child_raw_idx, []):
            grand_tok = spacy_tokens[grand_idx]
            if str(grand_tok.text or "").strip() != "の":
                continue
            if _dep_label(grand_tok) in {"case", "mark"}:
                return True
        return False

    has_direct_no_case = any(
        surf == "の" and dep in {"case", "mark"}
        for surf, dep in zip(child_surfaces, child_deps)
    )
    has_nested_no_case = any(
        dep in {"nmod", "obl", "det", "acl", "appos"}
        and _child_has_no_case_marker(raw_idx)
        for raw_idx, dep in zip(child_raw_indices, child_deps)
    )

    next_non_punct = ""
    for i in range(max(group_indices) + 1, len(spacy_tokens)):
        tok = spacy_tokens[i]
        if bool(tok.is_punct):
            continue
        next_non_punct = str(tok.text or "").strip()
        break

    group_surface = "".join([str(spacy_tokens[i].text or "") for i in group_indices])

    return {
        "has_child_no_case": has_direct_no_case or has_nested_no_case,
        "has_child_ka_mark": any(
            surf == "か" and dep in {"mark", "case", "discourse", "aux"}
            for surf, dep in zip(child_surfaces, child_deps)
        ),
        "has_child_subject": any(dep in {"nsubj", "csubj"} for dep in child_deps),
        "has_child_nominal": any(dep in {"nmod", "obl", "acl", "amod", "det", "appos"} for dep in child_deps),
        "has_following_suru": next_non_punct in {"する", "し", "した", "して", "します", "できる"},
        "is_katakana_surface": _is_katakana_surface(group_surface),
    }


def _sense_syntax_prior_score(
    upos: str,
    candidate_pos_tags: list[str],
    syntax_features: dict[str, bool],
) -> float:
    score = 0.0
    tags_text = " ".join([str(t or "").lower() for t in candidate_pos_tags])

    is_noun_like = "noun" in tags_text or "futsuumeishi" in tags_text
    is_suru_like = "takes the aux. verb suru" in tags_text or " participle " in f" {tags_text} "

    upos_norm = str(upos or "").strip().upper()
    if upos_norm == "NOUN":
        if is_noun_like:
            score += 0.16
        if is_suru_like:
            score -= 0.08

    if syntax_features.get("has_child_no_case", False):
        if is_noun_like:
            score += 0.42
        if is_suru_like:
            score -= 0.62

    if syntax_features.get("has_child_ka_mark", False):
        if is_noun_like:
            score += 0.24
        if is_suru_like:
            score -= 0.28

    if syntax_features.get("has_child_subject", False) or syntax_features.get("has_child_nominal", False):
        if is_noun_like:
            score += 0.18
        if is_suru_like:
            score -= 0.24

    if is_suru_like:
        if syntax_features.get("has_following_suru", False):
            score += 0.56
        else:
            # For noun contexts (e.g. Xのマスターか), suppress suru-like senses.
            score -= 0.36
            if upos_norm == "NOUN":
                score -= 0.34
            if (
                syntax_features.get("has_child_no_case", False)
                or syntax_features.get("has_child_ka_mark", False)
                or syntax_features.get("has_child_nominal", False)
            ):
                score -= 0.22

    if syntax_features.get("is_katakana_surface", False) and is_noun_like:
        score += 0.08

    return score


def _build_group_context_text(
    spacy_tokens: list,
    index_map: dict[int, int],
    group_indices: list[int],
    representative_raw: int,
) -> str:
    if not group_indices:
        return ""

    group_set = set(group_indices)
    context_indices: set[int] = set(group_indices)

    rep = spacy_tokens[representative_raw]
    rep_head = index_map.get(rep.head.i, representative_raw)
    if rep_head not in group_set and 0 <= rep_head < len(spacy_tokens):
        context_indices.add(rep_head)

    for raw_idx, tok in enumerate(spacy_tokens):
        if raw_idx in group_set:
            continue
        parent = index_map.get(tok.head.i, raw_idx)
        if parent in group_set:
            context_indices.add(raw_idx)

    left_neighbor = min(group_indices) - 1
    right_neighbor = max(group_indices) + 1
    if left_neighbor >= 0:
        context_indices.add(left_neighbor)
    if right_neighbor < len(spacy_tokens):
        context_indices.add(right_neighbor)

    parts: list[str] = []
    for raw_idx in sorted(context_indices):
        tok = spacy_tokens[raw_idx]
        if bool(tok.is_punct):
            continue
        text = str(tok.text or "").strip()
        if text:
            parts.append(text)

    return "".join(parts)


def _similarity_soft_score(nlp, context_text: str, candidate_text: str) -> float:
    a = str(context_text or "").strip()
    b = str(candidate_text or "").strip()
    if not a or not b:
        return 0.0

    try:
        doc_a = nlp(a)
        doc_b = nlp(b)
        norm_a = float(getattr(doc_a, "vector_norm", 0.0) or 0.0)
        norm_b = float(getattr(doc_b, "vector_norm", 0.0) or 0.0)
        if norm_a <= 0 or norm_b <= 0:
            return 0.0

        score = float(doc_a.similarity(doc_b))
        if not math.isfinite(score):
            return 0.0
        return max(-1.0, min(1.0, score))
    except Exception:
        return 0.0


def _candidate_semantic_text(surface: str, candidate: dict[str, object]) -> str:
    eng = [str(x) for x in candidate.get("eng_glosses", []) if str(x).strip()]
    zh = [str(x) for x in candidate.get("zh_glosses", []) if str(x).strip()]
    if eng:
        return f"{surface} {' '.join(eng[:3])}".strip()
    if zh:
        return f"{surface} {' '.join(zh[:2])}".strip()
    return str(surface or "").strip()


def _rank_sense_candidates(
    *,
    nlp,
    candidates: list[dict[str, object]],
    upos: str,
    dep_label: str,
    group_size: int,
    context_text: str,
    surface: str,
    syntax_features: dict[str, bool],
) -> list[dict[str, object]]:
    if not candidates:
        return []

    hard_filtered = [
        c for c in candidates if _pos_match_candidate(upos, [str(x) for x in c.get("pos_tags", [])])
    ]
    base = hard_filtered if hard_filtered else candidates

    scored: list[tuple[float, dict[str, object]]] = []
    for cand in base:
        pos_tags = [str(x) for x in cand.get("pos_tags", [])]
        prior = _sense_pos_prior_score(dep_label, group_size, pos_tags)
        prior += _sense_syntax_prior_score(upos, pos_tags, syntax_features)

        semantic_text = _candidate_semantic_text(surface, cand)
        sim = _similarity_soft_score(nlp, context_text, semantic_text)

        sim_weight = 0.22
        if str(upos or "").strip().upper() == "NOUN":
            sim_weight = 0.14
            if syntax_features.get("is_katakana_surface", False):
                sim_weight = 0.10
            if (
                syntax_features.get("has_child_no_case", False)
                or syntax_features.get("has_child_ka_mark", False)
                or syntax_features.get("has_child_nominal", False)
            ):
                sim_weight = min(sim_weight, 0.08)

        score = prior + sim * sim_weight
        scored.append((score, cand))

    scored.sort(key=lambda x: x[0], reverse=True)
    return [item for _, item in scored]


def _lookup_group_meaning_zh(
    *,
    nlp,
    context_text: str,
    dict_path: str,
    dep_label: str,
    group_size: int,
    surface: str,
    lemma: str,
    pos: str,
    is_punctuation: bool,
    limit: int,
    syntax_features: dict[str, bool],
) -> str:
    if not dict_path or not surface.strip() or is_punctuation:
        return ""

    if group_size <= 1 and not _should_lookup_meaning(pos, surface, is_punctuation):
        return ""

    candidates = _lookup_sense_candidates(dict_path, lemma, surface)
    if candidates:
        ranked = _rank_sense_candidates(
            nlp=nlp,
            candidates=candidates,
            upos=pos,
            dep_label=dep_label,
            group_size=group_size,
            context_text=context_text,
            surface=surface,
            syntax_features=syntax_features,
        )
        if ranked:
            best = ranked[0]
            zh_glosses = [str(x) for x in best.get("zh_glosses", []) if str(x).strip()]
            if zh_glosses:
                return " / ".join(_unique_keep_order(zh_glosses)[: max(1, limit)])

    return _lookup_meaning_zh(dict_path, lemma, surface, limit)


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

    groups = _build_ud_merge_groups(spacy_tokens, index_map)
    if not groups:
        return []

    raw_to_group: dict[int, int] = {}
    for group_idx, group in enumerate(groups):
        for raw_idx in group:
            raw_to_group[raw_idx] = group_idx

    out: list[Token] = []
    for group_idx, group in enumerate(groups):
        group_tokens = [spacy_tokens[i] for i in group]
        first = group_tokens[0]
        last = group_tokens[-1]

        representative_raw = _pick_representative_raw_index(group, spacy_tokens, index_map)
        representative_token = spacy_tokens[representative_raw]
        group_set = set(group)

        rep_head_raw = index_map.get(representative_token.head.i, representative_raw)
        if rep_head_raw in group_set:
            head_index = group_idx
        else:
            head_index = raw_to_group.get(rep_head_raw, group_idx)

        surface = "".join([str(t.text) for t in group_tokens])
        lemma = "".join([str(t.lemma_ or t.text) for t in group_tokens])
        pos = str(representative_token.pos_ or "")
        pos_detail = str(representative_token.tag_ or "")
        is_punctuation = all(bool(t.is_punct) for t in group_tokens)

        reading_parts = [part for part in [_safe_reading(t) for t in group_tokens] if part]
        conjugation_parts = [part for part in [_safe_conjugation(t) for t in group_tokens] if part]

        reading = "".join(reading_parts)
        conjugation = ",".join(_unique_keep_order(conjugation_parts))
        dep_label = _dep_label(representative_token)
        context_text = _build_group_context_text(
            spacy_tokens,
            index_map,
            group,
            representative_raw,
        )
        syntax_features = _extract_group_syntax_features(
            spacy_tokens,
            index_map,
            group,
            representative_raw,
        )

        meaning_zh = _lookup_group_meaning_zh(
            nlp=nlp,
            context_text=context_text,
            dict_path=dict_path,
            dep_label=dep_label,
            group_size=len(group),
            surface=surface,
            lemma=lemma,
            pos=pos,
            is_punctuation=is_punctuation,
            limit=meaning_limit,
            syntax_features=syntax_features,
        )

        out.append(
            Token(
                surface=surface,
                reading=reading,
                pos=pos,
                pos_detail=pos_detail,
                base=lemma,
                conjugation=conjugation,
                index=group_idx,
                head_index=head_index,
                dep=dep_label,
                char_start=int(first.idx),
                char_end=int(last.idx + len(str(last.text))),
                meaning_zh=meaning_zh,
                is_punctuation=is_punctuation,
            )
        )

    return out
