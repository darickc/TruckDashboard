#!/usr/bin/env python3
"""Runs scripts in Autodesk Fusion through its local MCP server (ADR-0047).

Fusion serves MCP at http://127.0.0.1:27182/mcp while it runs (FUSION_MCP
overrides). Used by `make mech-fusion` and `make mech-stl`.

  fusion_mcp.py script FILE.py [--ro] [--params JSON_FILE] [--set NAME=VALUE]
  fusion_mcp.py read '{"queryType": "..."}'
  fusion_mcp.py call TOOL 'JSON'

`--params` prepends PARAMS = <the file's JSON>; `--set` prepends a string
variable (for example the export directory).
"""
import json
import os
import sys
import urllib.request

URL = os.environ.get("FUSION_MCP", "http://127.0.0.1:27182/mcp")
HDR = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}


def post(body, sid=None):
    h = dict(HDR)
    if sid:
        h["MCP-Session-Id"] = sid
    req = urllib.request.Request(URL, data=json.dumps(body).encode(), headers=h, method="POST")
    with urllib.request.urlopen(req, timeout=600) as r:
        raw = r.read().decode()
        sid = r.headers.get("MCP-Session-Id") or sid
    if raw.startswith("event:") or raw.startswith("data:"):
        raw = "\n".join(l[5:].strip() for l in raw.splitlines() if l.startswith("data:"))
    return (json.loads(raw) if raw.strip() else None), sid


def session():
    _, sid = post({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2025-06-18", "capabilities": {},
        "clientInfo": {"name": "claude-code", "version": "1"}}})
    post({"jsonrpc": "2.0", "method": "notifications/initialized"}, sid)
    return sid


def call(tool, args):
    sid = session()
    res, _ = post({"jsonrpc": "2.0", "id": 2, "method": "tools/call",
                   "params": {"name": tool, "arguments": args}}, sid)
    if "error" in res:
        return json.dumps(res["error"])
    out = []
    for c in res["result"].get("content", []):
        if c.get("type") == "text":
            out.append(c["text"])
        else:
            out.append(json.dumps({k: v for k, v in c.items() if k != "data"})[:500])
    if res["result"].get("isError"):
        out.insert(0, "TOOL ERROR:")
    return "\n".join(out)


def main():
    cmd = sys.argv[1]
    try:
        session()
    except OSError as e:
        sys.exit(f"fusion_mcp: no Fusion MCP server at {URL} ({e}). Start Fusion and turn its MCP server on")
    if cmd == "read":
        print(call("fusion_mcp_read", json.loads(sys.argv[2])))
    elif cmd == "script":
        src = open(sys.argv[2]).read()
        if "--params" in sys.argv:
            p = json.load(open(sys.argv[sys.argv.index("--params") + 1]))
            src = "PARAMS = " + json.dumps(p) + "\n" + src
        for i, a in enumerate(sys.argv):
            if a == "--set":
                name, value = sys.argv[i + 1].split("=", 1)
                src = f"{name} = {json.dumps(value)}\n" + src
        obj = {"script": src}
        if "--ro" in sys.argv:
            obj["readOnly"] = True
        out = call("fusion_mcp_execute", {"featureType": "script", "object": obj})
        print(out)
        if out.startswith("TOOL ERROR") or '"success": false' in out:
            sys.exit(1)
    elif cmd == "call":
        print(call(sys.argv[2], json.loads(sys.argv[3])))


if __name__ == "__main__":
    main()
