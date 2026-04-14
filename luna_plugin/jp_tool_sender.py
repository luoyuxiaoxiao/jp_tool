"""
LunaTranslator → 日语语法解析器 桥接插件

功能：将 LunaTranslator 捕获的游戏文本自动发送到语法解析器后端

安装方法：
  1. 找到 LunaTranslator 的插件目录
     通常在: LunaTranslator/userconfig/copytranslator/
     或者:   LunaTranslator/plugins/
  2. 将此文件复制到该目录
  3. 在 LunaTranslator 设置中启用此插件
  4. 确保语法解析器后端已启动 (http://localhost:8765)

配置：
  修改下方 JP_TOOL_URL 如果后端不在默认地址
"""

import json
import urllib.request
import threading

# ═══════════════════════════════════════════
#  配置 - 根据需要修改
# ═══════════════════════════════════════════

JP_TOOL_URL = "http://127.0.0.1:8765/api/text"
TIMEOUT = 2  # 超时秒数，避免卡住游戏

# ═══════════════════════════════════════════
#  核心功能
# ═══════════════════════════════════════════


def _send(text: str):
    """在后台线程中发送文本，避免阻塞游戏。"""
    try:
        data = json.dumps({"text": text}).encode("utf-8")
        req = urllib.request.Request(
            JP_TOOL_URL,
            data=data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            pass  # 不需要处理响应
    except Exception:
        pass  # 静默失败，不影响游戏


def send_to_analyzer(text: str):
    """非阻塞发送文本到语法解析器。"""
    if text and text.strip():
        t = threading.Thread(target=_send, args=(text.strip(),), daemon=True)
        t.start()


# ═══════════════════════════════════════════
#  LunaTranslator 插件接口
# ═══════════════════════════════════════════

# 方式1: 作为自定义翻译输出插件
def output(text: str, *args, **kwargs):
    """LunaTranslator 输出插件接口 — 每次新文本时调用。"""
    send_to_analyzer(text)


# 方式2: 作为 copytranslator 插件
def copytranslator(text: str, *args, **kwargs):
    """LunaTranslator copytranslator 接口。"""
    send_to_analyzer(text)
