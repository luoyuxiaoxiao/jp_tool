本来是打算做一个在玩Galgame时能直接从lunatranslator拿到mecab切词好的原句（之前自己下载了轻量级unidic词典并使用mecab进行切词并显示到flutter，结果发现切词效果让我不满意，应该是词典太小了。后来一想我根本不需要这个功能且会极大增加体积，索性直接删掉了，结果假名注音也一起干掉了...），然后将句子交给本地Ollama或者远程llm api做深度语法解析并显示在flutter前端上，但是现在遇到一些问题：
1.还不了解如何优雅地从lunatranslator拿到切好词的原句，目前只有剪切板。
2.电脑1660ti实在一言难尽，Ollama本地模型不仅慢而且效果一般。api又感觉不太稳定且更慢了（nb的模型除外，用的免费的确实没话说）。


以下AI写的，之后如果有空整理重新写一份

# 日语语法解析器（JP Grammar Analyzer）

一个以 Windows 桌面为主的日语语法分析工具：

- 前端：Flutter Desktop
- 后端：Python FastAPI + WebSocket
- 能力：JLPT 语法匹配、等级高亮、可选 LLM 深度分析

---

## 当前架构（重点）

### 1. 前端托管后端进程

Flutter 前端通过静默派生方式异步拉起内置后端 EXE，并记录托管进程 PID/端口：

- 固定相对路径加载（发布目录内置），不再暴露后端路径输入
- 前端秒开，后端异步启动并自动重连
- 启动后可在设置页查看托管状态与端口

设置页支持：

- 自动启动后端开关
- 窗口材质效果切换（Transparent/Acrylic/Mica 等）
- 手动启动/停止后端
- 显示托管进程 PID 与实际端口
- 后端日志开关与日志面板（stdout/stderr）

### 2. 动态端口回退（已实现）

后端端口不再固定写死。前端启动托管后端时会按以下顺序尝试可用端口：

1. 当前本地 WebSocket 地址里的端口（如果是 localhost/127.0.0.1）
2. 默认端口：8765
3. 预设备用端口：18765、28675、38575、47865

策略说明：

- 某端口被占用则自动跳到下一个
- 找到可用端口后，把前端连接地址自动切到该端口
- 若全部不可用，前端会显示明确错误信息

### 3. 后端端口读取环境变量

后端启动时读取：

- JP_TOOL_PORT（默认 8765）
- JP_TOOL_HOST（默认 0.0.0.0）

这样前端在拉起后端进程时可为每次启动注入动态端口。

---

## 功能概览

- 本地分析：
  - 无词典分词依赖（已停用本地分词链路）
  - JLPT 语法匹配
- 深度分析（可选）：
  - Ollama / 通用 API
  - 核心语法、句子分解、常见错误等
- 字体与排版：
  - 中文主字体：LXGW WenKai Screen（霞鹜文楷屏幕阅读版）
  - 日文字体：Klee One（统一）
  - 多语言 Font Fallback 防止中日混排字形漂移/豆腐块
- 桌面视觉：
  - flutter_acrylic 原生窗口材质，默认 Transparent
- 运行时配置：
  - 剪贴板监听开关
  - 语法自动学习开关
  - 快捷键配置
  - 本地历史记录持久化

---

## 目录说明（当前）

```text
jp_tool/
├─ backend/                # Python 后端
├─ frontend/               # Flutter 前端
├─ web_frontend/           # 旧 HTML 前端（兼容保留）
├─ luna_plugin/            # LunaTranslator 插件
├─ 启动.bat                # 启动后端（脚本方式）
├─ 停止.bat                # 停止候选端口上的后端进程
├─ 启动开发.bat            # 开发辅助脚本（后端+Flutter Web）
└─ 停止开发.bat            # 停止开发脚本拉起的进程
```

---

## 运行方式

### A. 桌面端（推荐）

1. 打开 Flutter 桌面应用。
2. 开启“启动前端时自动拉起后端”。
3. 前端会静默异步拉起内置后端，并自动选择可用端口连接。
4. 如需排查，打开“启用后端日志”查看 stdout/stderr。

### B. 脚本启动后端（兼容）

直接双击：

- 启动.bat

默认优先使用 8765，若被占用会自动回退到备用端口并打开浏览器。

停止可用：

- 停止.bat

---

## 常见问题

### 1) 默认端口被占用怎么办？

桌面托管模式下会自动尝试备用端口，无需手动改配置。

### 2) 提示后端启动失败

请优先检查：

- 发布目录内置后端文件是否存在
- 杀软是否拦截
- 备用端口是否全部被占用

### 3) 为什么设置页显示的端口和 8765 不同？

这是正常行为，说明默认端口已占用，系统自动切换到了备用端口。

---

## 字体与开源引用

项目当前使用以下开源字体（已本地打包到 Flutter 资产）：

- LXGW WenKai Screen / 霞鹜文楷屏幕阅读版
  - 仓库：https://github.com/lxgw/LxgwWenKai-Screen
  - 许可证：SIL Open Font License 1.1
- Klee One
  - 来源：https://fonts.google.com/specimen/Klee+One
  - 许可证：SIL Open Font License 1.1

---

## CI/CD 自动发布

已提供 GitHub Actions 工作流：

- 文件：.github/workflows/release-windows.yml
- 触发：推送新 tag（v*）
- 动作：
  - Flutter build windows --release
  - Nuitka 打包 Python 后端（精简导入、禁用控制台窗口）
  - 不再包含分词词典目录（减小发布体积）
  - 组装完整发布目录并压缩为 zip
  - 自动上传到 GitHub Release

---

## 备注

README 已同步到当前桌面发布策略。后续如调整 Nuitka 参数或发布目录结构，请同步更新 workflow 与本节说明。
