"""Japanese tokenizer using fugashi (MeCab wrapper) + unidic."""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    pass

logger = logging.getLogger(__name__)

_tagger = None


def _get_tagger():
    """Lazy-init MeCab tagger (heavy on first call due to dict load)."""
    global _tagger
    if _tagger is None:
        import fugashi
        _tagger = fugashi.Tagger()
        logger.info("MeCab tagger initialized")
    return _tagger


def tokenize(text: str) -> list[dict]:
    """Tokenize Japanese text and return a list of token dicts.

    Each dict contains: surface, reading, pos, pos_detail, base, conjugation.
    """
    tagger = _get_tagger()
    tokens = []
    for word in tagger(text):
        # fugashi Word exposes .feature which is a namedtuple (unidic fields)
        feat = word.feature
        tokens.append({
            "surface": word.surface,
            "reading": getattr(feat, "kana", "") or "",
            "pos": getattr(feat, "pos1", "") or "",
            "pos_detail": getattr(feat, "pos2", "") or "",
            "base": getattr(feat, "lemma", word.surface) or word.surface,
            "conjugation": getattr(feat, "cForm", "") or "",
        })
    return tokens


def tokenize_to_models(text: str):
    """Tokenize and return a list of Token model instances."""
    from .models import Token
    return [Token(**t) for t in tokenize(text)]
