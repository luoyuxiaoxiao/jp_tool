"""Prompt templates for LLM-based deep grammar analysis."""

ANALYSIS_PROMPT = """\
あなたは日本語文法の専門家です。以下の日本語文を詳細に分析し、JSON形式で結果を返してください。

## 分析対象
「{text}」

## 出力要件（必ずJSONで返答）

```json
{{
  "core_grammar": [
    {{
      "grammar": "語法名称",
      "structure": "接续结构",
      "function": "功能说明（中文）",
      "comparison": "与相似语法的对比（中文）",
      "level": "N1-N5"
    }}
  ],
  "sentence_breakdown": [
    {{
      "fragment": "原文片段",
      "role": "语法功能（如：程度限定、主语、条件接续等）",
      "reading": "读音"
    }}
  ],
  "grammar_tree": [
    {{
      "label": "层级名称（如：轻微条件）",
      "note": "说明",
      "children": [
        {{
          "label": "子节点",
          "note": "说明",
          "children": []
        }}
      ]
    }}
  ],
  "comparisons": [
    {{
      "category": "对比类别（如：条件表达差异）",
      "items": [
        {{
          "expression": "表达形式",
          "example": "例句",
          "score": "特征评分或程度描述",
          "note": "补充说明"
        }}
      ]
    }}
  ],
  "common_mistakes": [
    {{
      "wrong": "错误表达",
      "problem": "问题点",
      "correct": "正确形式"
    }}
  ],
  "cultural_context": "文化语境说明（中文，可选）",
  "applications": ["应用场景1: 例句", "应用场景2: 例句"],
  "level_annotations": [
    {{
      "start": 0,
      "end": 3,
      "level": "N4",
      "grammar": "对应的语法点"
    }}
  ]
}}
```

## 分析要求
1. **核心语法解析**: 找出句中所有语法点，标注 N1-N5 等级，给出结构、功能、对比
2. **句子结构分解**: 将句子拆分为功能组件，标注每个片段的语法角色
3. **语法层级关系**: 用树形结构展示语法之间的层级和依赖关系
4. **近义表达对比**: 至少列出两组近义表达对比，含例句和特征评分
5. **常见错误**: 列出学习者对这些语法点的常见误用
6. **文化语境**: 说明该表达的使用场景和文化含义
7. **应用拓展**: 给出2-3个不同场景下的改编例句
8. **语法等级标注**: 对原文中每个语法点标注字符位置(start/end)和JLPT等级

只返回JSON，不要额外解释。"""


def build_analysis_prompt(text: str) -> str:
    return ANALYSIS_PROMPT.format(text=text)
