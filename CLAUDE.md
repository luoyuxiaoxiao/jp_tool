# JP Grammar Analyzer - 日语语法解析器

## 项目状态：所有代码已完成，待迁移到 Windows

## 已完成的工作

### Python 后端 (全部完成)
- `backend/main.py` — FastAPI 入口，WebSocket 服务，两阶段分析管道，HTML 页面托管
- `backend/analyzer/models.py` — 11 个 Pydantic 数据模型
- `backend/analyzer/tokenizer.py` — fugashi/MeCab 分词引擎 (使用 unidic-lite 轻量词典)
- `backend/analyzer/grammar_db.py` — JLPT 语法匹配 + 自动学习机制 (LLM 结果自动回填)
- `backend/data/jlpt_grammar.json` — 66 条 N1-N5 语法数据库
- `backend/capture/clipboard.py` — 剪贴板监听 (自动检测日文)
- `backend/capture/http_receiver.py` — HTTP 接收端 (LunaTranslator 插件推送)
- `backend/llm/__init__.py` — LLM 自动检测 (Ollama/Claude/关闭)，运行时切换
- `backend/llm/base.py` — LLM 抽象基类，增强 JSON 容错解析
- `backend/llm/ollama_provider.py` — Ollama 支持 (模型检测/超时重试/日志)
- `backend/llm/claude_provider.py` — Claude API 支持
- `backend/llm/prompt_templates.py` — 8 维度语法分析 prompt 模板

### HTML 前端 (全部完成)
- `test.html` — 完整浏览器界面，包含:
  - 原文 + 汉字注音(ruby) + N1-N5 彩色下划线
  - 分词卡片 (词性中文显示)
  - 语法匹配列表
  - 深度分析: 核心语法/句子分解/语法树/近义对比表/常见错误/文化语境/应用拓展
  - LLM 状态指示器 + 深度分析加载动画
  - 所有 UI 文本为中文

### Flutter 前端 (全部完成，待在 Windows 编译)
- `frontend/lib/main.dart` — 应用入口
- `frontend/lib/models/analysis_result.dart` — Dart 数据模型
- `frontend/lib/services/websocket_service.dart` — WebSocket 连接管理
- `frontend/lib/screens/analysis_screen.dart` — 主界面 (中文)
- `frontend/lib/screens/settings_screen.dart` — 设置页面
- 7 个 widgets: grammar_highlight, word_card, core_grammar_view, sentence_breakdown, grammar_tree, comparison_table, common_mistakes_view

### 脚本和文档
- `启动.bat` — 4 种模式启动 (完整/轻量/仅后端/自定义LLM)
- `停止.bat` — 关闭后端进程
- `打包.bat` — PyInstaller 打包成独立 exe
- `flutter打包.bat` — Flutter 桌面应用编译
- `使用教程.txt` — 完整使用指南
- `Flutter桌面应用打包教程.txt` — Flutter 打包详细步骤
- `luna_plugin/jp_tool_sender.py` — LunaTranslator 桥接插件

## 已验证
- MeCab 分词正常 (WSL 环境)
- JLPT 语法匹配正常 (5 个语法点命中测试句)
- WebSocket 通信正常
- HTML 前端渲染正常 (注音 + 彩色下划线 + 分词卡片)
- Python 全部文件语法检查通过

## 待完成 (用户自行操作)
1. 迁移到 Windows: xcopy \\wsl$\Ubuntu\home\luoyu\jp_tool F:\jp_tool\ /E /I
2. 删除 WSL 虚拟环境: rmdir /S /Q F:\jp_tool\backend\.venv
3. Windows 需安装 Python 3.11/3.12 (勾选 Add to PATH)
4. 双击 启动.bat 首次运行自动安装依赖
5. 验证 Ollama 深度分析 (qwen2.5:7b, 1660Ti 6GB 够用)
6. (可选) Flutter 桌面应用编译 — 需要 Flutter SDK + Visual Studio C++
7. (可选) PyInstaller 打包成独立 exe — 双击 打包.bat

## 环境信息
- Ollama 位置: F:\LLM\Ollama
- 推荐模型: qwen2.5:7b (约 5GB 显存, 1660Ti 可用)
- 后端端口: 8765
- 浏览器访问: http://localhost:8765
- WebSocket: ws://localhost:8765/ws
