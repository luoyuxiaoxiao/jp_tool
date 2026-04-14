"""Pydantic data models for analysis results."""

from __future__ import annotations

from pydantic import BaseModel


class Token(BaseModel):
    """A single morphological token from MeCab."""
    surface: str
    reading: str = ""
    pos: str = ""          # 品詞 (part of speech)
    pos_detail: str = ""   # 品詞細分類
    base: str = ""         # 原形
    conjugation: str = ""  # 活用形


class GrammarMatch(BaseModel):
    """A matched JLPT grammar pattern."""
    pattern: str
    level: str             # N1-N5
    meaning_zh: str = ""
    meaning_ja: str = ""
    example: str = ""
    start: int = 0         # token start index
    end: int = 0           # token end index


class BasicResult(BaseModel):
    """Phase 1 result: local NLP analysis (<100ms)."""
    type: str = "basic_result"
    text: str
    tokens: list[Token] = []
    grammar_matches: list[GrammarMatch] = []


class SentenceComponent(BaseModel):
    """A component in the sentence breakdown."""
    fragment: str
    role: str              # e.g. 程度限定, 主语, 条件接续
    reading: str = ""


class GrammarPoint(BaseModel):
    """A core grammar analysis point."""
    grammar: str
    structure: str = ""
    function: str = ""
    comparison: str = ""
    level: str = ""


class ComparisonItem(BaseModel):
    """A near-synonym comparison entry."""
    expression: str
    example: str = ""
    score: str = ""        # e.g. 必然性打分 or 夸张度
    note: str = ""


class ComparisonGroup(BaseModel):
    """A group of near-synonym comparisons."""
    category: str          # e.g. 条件表达差异, 心理变化表达
    items: list[ComparisonItem] = []


class CommonMistake(BaseModel):
    """A common mistake entry."""
    wrong: str
    problem: str
    correct: str


class GrammarTreeNode(BaseModel):
    """A node in the grammar hierarchy tree."""
    label: str
    note: str = ""
    children: list[GrammarTreeNode] = []


class LevelAnnotation(BaseModel):
    """N1-N5 annotation for a text span."""
    start: int             # char offset in original text
    end: int
    level: str
    grammar: str


class DeepResult(BaseModel):
    """Phase 2 result: LLM deep analysis (2-5s)."""
    type: str = "deep_result"
    text: str
    core_grammar: list[GrammarPoint] = []
    sentence_breakdown: list[SentenceComponent] = []
    grammar_tree: list[GrammarTreeNode] = []
    comparisons: list[ComparisonGroup] = []
    common_mistakes: list[CommonMistake] = []
    cultural_context: str = ""
    applications: list[str] = []
    level_annotations: list[LevelAnnotation] = []
