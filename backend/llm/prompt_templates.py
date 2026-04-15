"""Prompt templates for LLM-based deep grammar analysis."""

ANALYSIS_PROMPT = """\
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

输出 JSON 结构（字段名必须完全一致）：
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


def build_analysis_prompt(text: str) -> str:
    return ANALYSIS_PROMPT.format(text=text)
