Luna WebSocket probe

Files:
- luna_ws_probe.py: connect to Luna WebSocket and capture raw messages.
- run_luna_ws_probe.bat: helper launcher (uses backend/.venv Python if present).

Quick start:
1. Enable Luna network service and keep its WebSocket endpoint available.
2. Run:
   test\\run_luna_ws_probe.bat

Optional custom URL:
- test\\run_luna_ws_probe.bat --url ws://127.0.0.1:2333/api/ws/text/origin

Outputs written to this folder:
- luna_ws_capture_<timestamp>.jsonl
- luna_ws_capture_<timestamp>_summary.json
- luna_ws_capture_latest.jsonl
- luna_ws_capture_latest_summary.json

How to inspect data shape:
- Open the latest summary JSON and check:
  - top_level_key_frequency
  - samples
