#!/usr/bin/env python3
"""Probe LunaTranslator WebSocket and dump captured messages to local files.

Default target:
- ws://127.0.0.1:2333/api/ws/text/origin

Outputs (under --out-dir):
- luna_ws_capture_<timestamp>.jsonl
- luna_ws_capture_<timestamp>_summary.json
- luna_ws_capture_latest.jsonl
- luna_ws_capture_latest_summary.json
"""

from __future__ import annotations

import argparse
import asyncio
import json
import shutil
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def now_stamp() -> str:
    return datetime.now().strftime("%Y%m%d_%H%M%S")


@dataclass
class ProbeStats:
    url: str
    started_at: str
    ended_at: str = ""
    connected: bool = False
    message_count: int = 0
    parse_error_count: int = 0
    key_counts: dict[str, int] = field(default_factory=dict)
    samples: list[dict[str, Any]] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)


async def run_probe(args: argparse.Namespace) -> int:
    try:
        import websockets  # type: ignore
    except Exception as exc:
        print(f"[probe] missing dependency 'websockets': {exc}")
        print("[probe] install with: pip install websockets")
        return 3

    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    stamp = now_stamp()
    prefix = args.prefix
    jsonl_path = out_dir / f"{prefix}_{stamp}.jsonl"
    summary_path = out_dir / f"{prefix}_{stamp}_summary.json"
    latest_jsonl = out_dir / f"{prefix}_latest.jsonl"
    latest_summary = out_dir / f"{prefix}_latest_summary.json"

    stats = ProbeStats(url=args.url, started_at=utc_now_iso())

    print(f"[probe] connect url: {args.url}")
    print(f"[probe] output dir : {out_dir}")
    print(f"[probe] max msgs   : {args.max_messages}")
    print(f"[probe] duration s : {args.duration}")

    try:
        async with websockets.connect(
            args.url,
            ping_interval=20,
            ping_timeout=20,
            close_timeout=5,
            max_size=2 ** 22,
        ) as ws:
            stats.connected = True
            print("[probe] connected")

            loop = asyncio.get_running_loop()
            deadline = None
            if args.duration > 0:
                deadline = loop.time() + float(args.duration)

            with jsonl_path.open("w", encoding="utf-8") as fp:
                while True:
                    if args.max_messages > 0 and stats.message_count >= args.max_messages:
                        break

                    timeout = args.read_timeout
                    if deadline is not None:
                        remain = deadline - loop.time()
                        if remain <= 0:
                            break
                        timeout = min(timeout, remain)

                    try:
                        message = await asyncio.wait_for(ws.recv(), timeout=timeout)
                    except asyncio.TimeoutError:
                        if deadline is None:
                            stats.errors.append(
                                f"read timeout ({args.read_timeout}s) with no new message"
                            )
                        break

                    text = message.decode("utf-8", errors="replace") if isinstance(message, bytes) else str(message)

                    record: dict[str, Any] = {
                        "received_at": utc_now_iso(),
                        "raw_type": type(message).__name__,
                        "raw": text,
                    }

                    try:
                        parsed = json.loads(text)
                        record["json_type"] = type(parsed).__name__
                        if isinstance(parsed, dict):
                            keys = sorted(str(k) for k in parsed.keys())
                            record["top_level_keys"] = keys
                            for key in keys:
                                stats.key_counts[key] = stats.key_counts.get(key, 0) + 1
                        else:
                            record["top_level_keys"] = []
                    except Exception as exc:
                        stats.parse_error_count += 1
                        record["json_error"] = str(exc)
                        record["top_level_keys"] = []

                    fp.write(json.dumps(record, ensure_ascii=False) + "\n")
                    fp.flush()
                    stats.message_count += 1

                    if len(stats.samples) < args.sample_count:
                        sample = dict(record)
                        raw_text = sample.get("raw", "")
                        if isinstance(raw_text, str) and len(raw_text) > args.sample_trim:
                            sample["raw"] = raw_text[: args.sample_trim] + "...(trimmed)"
                        stats.samples.append(sample)

                    if args.verbose:
                        preview = text.replace("\n", " ")
                        if len(preview) > 180:
                            preview = preview[:180] + "..."
                        print(f"[probe] msg#{stats.message_count}: {preview}")

    except Exception as exc:
        stats.errors.append(f"connect/recv failed: {exc}")

    stats.ended_at = utc_now_iso()
    summary = {
        "url": stats.url,
        "started_at": stats.started_at,
        "ended_at": stats.ended_at,
        "connected": stats.connected,
        "message_count": stats.message_count,
        "parse_error_count": stats.parse_error_count,
        "top_level_key_frequency": stats.key_counts,
        "samples": stats.samples,
        "errors": stats.errors,
    }

    summary_path.write_text(
        json.dumps(summary, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    try:
        shutil.copyfile(jsonl_path, latest_jsonl)
        shutil.copyfile(summary_path, latest_summary)
    except Exception:
        # Keep run artifacts even if latest copy fails.
        pass

    print(f"[probe] jsonl  : {jsonl_path}")
    print(f"[probe] summary: {summary_path}")
    print(f"[probe] latest : {latest_summary}")

    if not stats.connected:
        print("[probe] not connected")
        return 2

    print(f"[probe] done, captured {stats.message_count} message(s)")
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Probe LunaTranslator WebSocket stream")
    p.add_argument(
        "--url",
        default="ws://127.0.0.1:2333/api/ws/text/origin",
        help="Luna websocket url",
    )
    p.add_argument(
        "--duration",
        type=float,
        default=30.0,
        help="capture duration in seconds (<=0 means read-timeout mode)",
    )
    p.add_argument(
        "--max-messages",
        type=int,
        default=50,
        help="stop after this many messages (<=0 means unlimited)",
    )
    p.add_argument(
        "--read-timeout",
        type=float,
        default=5.0,
        help="single recv timeout in seconds",
    )
    p.add_argument(
        "--sample-count",
        type=int,
        default=5,
        help="number of sample records to keep in summary",
    )
    p.add_argument(
        "--sample-trim",
        type=int,
        default=300,
        help="max raw length per sample in summary",
    )
    p.add_argument(
        "--out-dir",
        default="test",
        help="directory to write capture files",
    )
    p.add_argument(
        "--prefix",
        default="luna_ws_capture",
        help="output filename prefix",
    )
    p.add_argument(
        "--verbose",
        action="store_true",
        help="print each received message preview",
    )
    return p


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return asyncio.run(run_probe(args))


if __name__ == "__main__":
    raise SystemExit(main())
