"""Prompt templates for LLM-based deep grammar analysis."""

from __future__ import annotations

import os

PROMPT_PROFILE_JSON = "json"
PROMPT_PROFILE_MARKDOWN = "markdown"

ANALYSIS_PROMPT_JSON = """\
你是日语语法讲解专家。请分析下面的日语句子，并严格返回一个可被 json.loads 解析的 JSON 对象。

分析目标：
{text}

硬性要求：
1. 只输出 JSON，不要 Markdown 代码块，不要任何额外文本。
2. JSON 必须合法：
   - 不能有尾随逗号
   - 不能有注释
   - 字符串中的双引号必须转义
3. 以下字段的说明必须使用简体中文：
   function, comparison, role, note, category, score, problem, cultural_context, applications
4. 以下字段保留日文内容：
   grammar, fragment, expression, wrong, correct, example
5. level 只能使用 N1/N2/N3/N4/N5 之一。
6. 可选返回词语释义字段 word_meanings（数组），仅在有把握时提供；meaning_zh 必须是简体中文。
7. 请尽量提供更完整、可教学的中文解释，避免过度简短：
  - core_grammar 建议 2-4 条，function 尽量写成完整中文句（建议 >=20 字）
  - sentence_breakdown 建议覆盖整句（通常 >=4 段）
  - comparisons 建议至少 1 组且每组 >=2 条（确实无可比时可为空）
  - cultural_context 如有内容，尽量给出更具体中文说明（建议 >=60 字）

输出 JSON 结构（字段名必须完全一致，以下是一个模板实例）：
{{
  "core_grammar": [
    {{
      "grammar": "语法点（日文）",
      "structure": "接续结构（可中日混合）",
      "function": "功能说明（简体中文）",
      "comparison": "与近义语法对比（简体中文）",
      "level": "N1"
    }}
  ],
  "word_meanings": [
    {{
      "word": "词语或短语（日文原文）",
      "meaning_zh": "简体中文释义（尽量具体）"
    }}
  ],
  "sentence_breakdown": [
    {{
      "fragment": "原文片段（日文）",
      "role": "语法角色（简体中文）",
      "reading": "假名读音"
    }}
  ],
  "grammar_tree": [
    {{
      "label": "节点名称",
      "note": "说明（简体中文）",
      "children": [
        {{
          "label": "子节点",
          "note": "说明（简体中文）",
          "children": []
        }}
      ]
    }}
  ],
  "comparisons": [
    {{
      "category": "对比类别（简体中文）",
      "items": [
        {{
          "expression": "表达（日文）",
          "example": "例句（日文）",
          "score": "特征说明（简体中文）",
          "note": "补充（简体中文）"
        }}
      ]
    }}
  ],
  "common_mistakes": [
    {{
      "wrong": "错误表达（日文）",
      "problem": "问题说明（简体中文）",
      "correct": "正确表达（日文）"
    }}
  ],
  "cultural_context": "文化语境说明（简体中文）",
  "applications": ["应用场景1（简体中文）", "应用场景2（简体中文）"],
  "level_annotations": [
    {{
      "start": 0,
      "end": 3,
      "level": "N4",
      "grammar": "语法点（日文）"
    }}
  ]
}}
"""

# Backward-compatible alias for old imports.
ANALYSIS_PROMPT = ANALYSIS_PROMPT_JSON

ANALYSIS_PROMPT_MARKDOWN = """\
你是日语语法讲解专家。请对下面句子做深入讲解，并直接输出 Markdown 正文。

分析目标：
{text}

输出要求：
1. 只输出 Markdown 正文，不要输出 JSON，不要输出“下面开始分析”等额外客套。
2. 解释使用简体中文；日语表达、语法项、例句请保留日文原文。
3. 按以下层级组织内容（标题文案可微调，但层级请保留）：
   - # 句子总览
   - # 核心语法点
     - ## 语法点1
     - ## 语法点2
   - # 逐片段拆解
   - # 易错点与替换表达
   - # 语境与语感
   - # 练习建议（可选）
4. 每个核心语法点尽量覆盖：接续/结构、核心含义、语气限制、近义对比、例句与中文释义。
5. 内容要实用、可学习迁移，避免空洞总结。
6. 不要用 Markdown 代码块包裹整段答案。

请直接开始输出 Markdown。
"""


def normalize_prompt_profile(raw: object | None) -> str:
    mode = str(raw or "").strip().lower()
    if mode in {"markdown", "md"}:
        return PROMPT_PROFILE_MARKDOWN
    return PROMPT_PROFILE_JSON


def get_prompt_profile() -> str:
    return normalize_prompt_profile(
        os.environ.get("RESOURCE_DEEP_PROMPT_PROFILE", PROMPT_PROFILE_JSON)
    )


def build_analysis_prompt(text: str, prompt_profile: str | None = None) -> str:
    profile = normalize_prompt_profile(
        prompt_profile
        if prompt_profile is not None
        else os.environ.get("RESOURCE_DEEP_PROMPT_PROFILE", PROMPT_PROFILE_JSON)
    )
    template = (
        ANALYSIS_PROMPT_MARKDOWN
        if profile == PROMPT_PROFILE_MARKDOWN
        else ANALYSIS_PROMPT_JSON
    )
    return template.format(text=text)
