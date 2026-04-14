# 日语语法解析器 (JP Grammar Analyzer)

一个面向日语学习与精读场景的本地化语法分析工具。
支持分词、注音、JLPT 语法点识别，并可接入 Ollama 或 Claude 进行深度语法讲解。

---

## 项目亮点

- 双层分析能力：
  - 本地分析：分词、词性、注音、JLPT 语法匹配
  - 深度分析：核心语法、句子结构、易错点、近义对比、文化语境
- 两种前端形态：
  - 浏览器页面（`test.html`）
  - Flutter 桌面端（`frontend/`）
- 多种输入来源：
  - 手动输入
  - 剪贴板监听
  - LunaTranslator 插件推送
- 大模型可切换：
  - Ollama（推荐本地模型）
  - Claude API
  - 关闭 LLM（轻量模式）

---

## 技术架构

- 后端：FastAPI + WebSocket
- 分词：fugashi + MeCab + unidic-lite
- 语法库：内置 JLPT N1-N5 语法 JSON 数据
- 前端：HTML 页面 + Flutter Desktop

目录概览：

```text
jp_tool/
├─ backend/          # Python 后端与语法分析核心
├─ frontend/         # Flutter 桌面前端
├─ luna_plugin/      # LunaTranslator 桥接插件
├─ test.html         # 浏览器版前端
├─ 启动.bat           # 一键启动
├─ 停止.bat           # 一键停止
├─ 打包.bat           # 后端打包
└─ 教程.txt           # 完整详细教程（原 readme）
```

---

## 快速开始（Windows）

### 1) 环境准备

- 安装 Python 3.11 或 3.12（建议）
- 安装时勾选 `Add Python to PATH`
- 可选：安装并启动 Ollama（深度分析）

### 2) 启动项目

在项目根目录直接双击：

- `启动.bat`

首次运行会自动：

- 创建 `backend/.venv`
- 安装依赖
- 启动后端服务并打开浏览器

默认访问地址：

- HTTP: `http://localhost:8765`
- WebSocket: `ws://localhost:8765/ws`

### 3) 停止项目

- 在服务窗口按 `Ctrl + C`
- 或双击 `停止.bat`

---

## 运行模式

`启动.bat` 提供多模式：

- 完整模式：自动检测并启用 LLM（可用时）
- 轻量模式：仅本地分析，不走大模型
- 仅后端模式：用于 Flutter 桌面端连接
- 自定义模式：手动选择 Ollama / Claude / 关闭

---

## LLM 配置接口

切换 Ollama 模型：

```bash
curl -X POST http://localhost:8765/api/llm/configure \
  -H "Content-Type: application/json" \
  -d "{\"backend\":\"ollama\",\"ollama_model\":\"qwen2.5:7b\"}"
```

关闭 LLM：

```bash
curl -X POST http://localhost:8765/api/llm/configure \
  -H "Content-Type: application/json" \
  -d "{\"backend\":\"off\"}"
```

查看当前状态：

```bash
curl http://localhost:8765/api/llm/status
```

---

## 与 LunaTranslator 联动

将插件文件复制到 LunaTranslator 插件目录：

- `luna_plugin/jp_tool_sender.py`

建议使用流程：

1. 启动本项目后端
2. 启动 LunaTranslator 并启用插件
3. 游戏文本将自动推送到解析器

---

## 打包说明

- 后端打包：双击 `打包.bat`
- Flutter 打包：双击 `flutter打包.bat`

更多打包与排障说明请查看：

- `教程.txt`
- `Flutter桌面应用打包教程.txt`

---

## Git 提交建议

仓库已配置 `.gitignore`，默认不上传以下大体积内容：

- Python 虚拟环境（如 `.venv/`）
- Flutter 构建产物（如 `frontend/build/`、`frontend/windows/x64/`）
- 本地词典缓存目录（如 `backend/data/unidic_lite/`）

如果你在其他机器拉取过旧历史，请重新克隆或同步主分支历史。

---

## 许可证

根据实际需求补充（例如 MIT / Apache-2.0）。

## 日语语法解析器 - 完整使用教程


目录:
  1. Windows 环境准备
  2. 迁移项目到 Windows
  3. 首次启动
  4. 日常使用 (启动/停止)
  5. LLM 模式切换
  6. LunaTranslator 插件安装
  7. 打包成独立 EXE
  8. 常见问题


### 1. Windows 环境准备 (只需做一次)


你需要在 Windows 上安装 Python。bat 脚本依赖它。

(1) 下载 Python:
    https://www.python.org/downloads/
    建议版本: 3.11 或 3.12 (不要用 3.14，兼容性不够好)

(2) 安装时务必勾选:
    [✓] Add Python to PATH    ← 非常重要！
    [✓] Install pip

(3) 验证安装 (打开 CMD):
    python --version     → 应显示 Python 3.11.x 或 3.12.x
    pip --version        → 应显示 pip 版本号

(4) Ollama (可选，用于深度语法分析):
    你已经装好了，位置在 F:\LLM\Ollama
    确保 Ollama 后台运行，模型已拉取:
    ollama pull qwen2.5:7b


### 2. 迁移项目到 Windows 


迁移后的目录结构:
    F:\jp_tool\
    ├── 启动.bat              ← 双击启动
    ├── 停止.bat              ← 双击停止
    ├── 打包.bat              ← 打包成 exe
    ├── flutter打包.bat       ← Flutter 桌面应用打包
    ├── test.html             ← 浏览器前端页面
    ├── backend\              ← Python 后端
    ├── frontend\             ← Flutter 前端源码
    └── luna_plugin\          ← LunaTranslator 插件


启动.bat 会自动重新创建 Windows 版的虚拟环境。


### 3. 首次启动


(1) 双击 启动.bat
(2) 首次运行会自动:
    - 创建 Python 虚拟环境
    - 安装所有依赖 (需要联网，约1-2分钟)
(3) 选择模式 [1] 完整模式
(4) 浏览器自动打开 http://localhost:8765
(5) 输入日文，点「解析」


### 4. 日常使用


启动:
    双击「启动.bat」→ 选模式 → 自动打开浏览器

停止:
    方法1: 在后端窗口按 Ctrl+C
    方法2: 双击「停止.bat」
    方法3: 直接关闭后端的 CMD 窗口

查看状态:
    浏览器右上角有两个指示灯:
    - 绿色圆点 = WebSocket 已连接
    - 绿色 LLM: qwen2.5:7b = 大模型可用
    - 灰色 LLM: 未启用 = 仅本地分析


### 5. LLM 模式切换


启动时选择:
    [1] 完整模式   → 自动检测 Ollama，有就用
    [2] 轻量模式   → 不用大模型，只有分词+注音+语法匹配
    [3] 仅后端     → 给 Flutter 桌面应用连接
    [4] 自定义     → 手选模型

自定义模式下:
    [1] Ollama 默认 (qwen2.5:7b)
    [2] Ollama 自定义模型 → 输入名称如 qwen3:8b
    [3] Claude API → 输入你的 Anthropic API Key
    [4] 不使用大模型

运行中切换 (不需要重启):
    用浏览器或 curl 发送 POST 请求:

    切换到其他 Ollama 模型:
    curl -X POST http://localhost:8765/api/llm/configure -H "Content-Type: application/json" -d "{\"backend\":\"ollama\",\"ollama_model\":\"qwen3:8b\"}"

    关闭大模型:
    curl -X POST http://localhost:8765/api/llm/configure -H "Content-Type: application/json" -d "{\"backend\":\"off\"}"

    查看当前状态:
    浏览器打开 http://localhost:8765/api/llm/status


### 6. LunaTranslator 插件安装（暂无）

    - 确认后端已启动 (http://localhost:8765)
    - 确认插件文件在正确目录
    - 检查 LunaTranslator 是否启用了该插件
    - 也可以用剪贴板模式: LunaTranslator 设置「自动复制到剪贴板」（可以用）
      后端会自动监听剪贴板中的日文


### 7. 打包成独立 EXE (不需要安装 Python)


(1) 双击 打包.bat
(2) 等待打包完成 (约1-2分钟)
(3) 输出在 jp_tool\backend\dist\jp_grammar\
(4) 把整个 jp_grammar 文件夹复制到任意电脑
(5) 双击里面的「启动.bat」即可运行 (无需 Python)


### 8. 常见问题


Q: 启动.bat 报错「python 不是内部命令」
A: Python 没加入 PATH。重新安装 Python，勾选 Add to PATH。
   或者手动添加: 系统设置 → 环境变量 → Path → 添加 Python 路径

Q: 浏览器显示「未连接」
A: 后端没启动。检查 CMD 窗口是否有报错。

Q: LLM 状态显示「未启用」但我装了 Ollama
A: 确认 Ollama 后台在运行 (系统托盘图标)。
   确认模型已下载: 打开 CMD 输入 ollama list

Q: 深度分析很慢
A: 正常。
   如果超过 30 秒，可能显存不足，换小模型。

Q: 端口 8765 被占用
A: 双击「停止.bat」关闭之前的进程，再重新启动。
