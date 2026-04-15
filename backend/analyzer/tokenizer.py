"""Japanese tokenizer using fugashi (MeCab wrapper) + unidic."""

from __future__ import annotations

import logging
import os
import sys
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    pass

logger = logging.getLogger(__name__)

_tagger = None


def _resolve_dicdir() -> str | None:
    """Resolve dictionary directory from env/relative path first."""
    env_path = os.environ.get("JP_TOOL_DICDIR", "").strip()
    if env_path and os.path.isdir(env_path):
        return env_path

    roots = [
        os.path.dirname(getattr(sys, "executable", "") or ""),
        os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..")),
        os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")),
        os.getcwd(),
    ]
    rel_candidates = [
        os.path.join("resources", "backend", "dicdir"),
        os.path.join("backend", "dicdir"),
        os.path.join("unidic_lite", "dicdir"),
        "dicdir",
    ]

    for root in roots:
        if not root:
            continue
        for rel in rel_candidates:
            path = os.path.abspath(os.path.join(root, rel))
            if os.path.isdir(path):
                return path

    return None


def _dicdir_search_paths() -> list[str]:
    roots = [
        os.path.dirname(getattr(sys, "executable", "") or ""),
        os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..")),
        os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")),
        os.getcwd(),
    ]
    rel_candidates = [
        os.path.join("resources", "backend", "dicdir"),
        os.path.join("backend", "dicdir"),
        os.path.join("unidic_lite", "dicdir"),
        "dicdir",
    ]

    paths: list[str] = []
    for root in roots:
        if not root:
            continue
        for rel in rel_candidates:
            paths.append(os.path.abspath(os.path.join(root, rel)))

    return paths


def _feature_value(
    feature: object,
    *,
    attr_names: tuple[str, ...] = (),
    index_candidates: tuple[int, ...] = (),
    default: str = "",
) -> str:
    for name in attr_names:
        value = getattr(feature, name, None)
        if value is None:
            continue
        text = str(value).strip()
        if text and text != "*":
            return text

    values: list[str] | None = None
    if isinstance(feature, (list, tuple)):
        values = [str(item).strip() for item in feature]
    elif isinstance(feature, str):
        values = [item.strip() for item in feature.split(",")]

    if values is not None:
        for idx in index_candidates:
            if 0 <= idx < len(values):
                text = values[idx]
                if text and text != "*":
                    return text

    return default


def _get_tagger():
    """Lazy-init MeCab tagger (heavy on first call due to dict load)."""
    global _tagger
    if _tagger is None:
        import fugashi
        dicdir = _resolve_dicdir()
        if not dicdir:
            searched = "; ".join(_dicdir_search_paths())
            message = (
                "未找到 UniDic 词典目录。请将 unidic_lite/dicdir 或 resources/backend/dicdir "
                f"放到可执行文件旁边。已检查: {searched}"
            )
            logger.error(message)
            raise RuntimeError(message)

        args = f'-d "{dicdir}"'
        try:
            _tagger = fugashi.Tagger(args)
            logger.info("MeCab tagger initialized with Tagger dicdir=%s", dicdir)
        except Exception as e:
            logger.warning(
                "Tagger init failed, fallback to GenericTagger (dicdir=%s): %s",
                dicdir,
                e,
            )
            _tagger = fugashi.GenericTagger(args)
            logger.info("MeCab tagger initialized with GenericTagger dicdir=%s", dicdir)
    return _tagger


def tokenize(text: str) -> list[dict]:
    """Tokenize Japanese text and return a list of token dicts.

    Each dict contains: surface, reading, pos, pos_detail, base, conjugation.
    """
    tagger = _get_tagger()
    tokens = []
    for word in tagger(text):
        # Handle both Tagger (namedtuple features) and GenericTagger (list-like features).
        feat = word.feature
        tokens.append({
            "surface": word.surface,
            "reading": _feature_value(
                feat,
                attr_names=("kana", "pron", "pronBase", "reading"),
                index_candidates=(17, 8, 7),
                default="",
            ),
            "pos": _feature_value(
                feat,
                attr_names=("pos1", "pos"),
                index_candidates=(0,),
                default="",
            ),
            "pos_detail": _feature_value(
                feat,
                attr_names=("pos2", "pos_detail"),
                index_candidates=(1,),
                default="",
            ),
            "base": _feature_value(
                feat,
                attr_names=("lemma", "orthBase", "base"),
                index_candidates=(7, 10, 6),
                default=word.surface,
            ),
            "conjugation": _feature_value(
                feat,
                attr_names=("cForm", "conjugationForm", "conjugation"),
                index_candidates=(5, 4),
                default="",
            ),
        })
    return tokens


def tokenize_to_models(text: str):
    """Tokenize and return a list of Token model instances."""
    from .models import Token
    return [Token(**t) for t in tokenize(text)]
