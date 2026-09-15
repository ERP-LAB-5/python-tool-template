# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 D-LAB-5
"""Talk to a generated tool's MCP server over stdio and exercise it.

    python mcp_probe.py <cwd> <command> [args...]

Lists the tools, saves and reads a note back through the web server (which the
MCP server has to start itself), checks validation, and stops the server.
Exits non-zero on anything unexpected. Run it with the generated tool's venv,
which has the mcp package.
"""

import asyncio
import json
import os
import sys
import time
import urllib.request

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

EXPECTED = {"delete_note", "list_notes", "read_note", "save_note", "server_url",
            "stop_server", "summarise_note", "validate_note"}


def text(result) -> str:
    if getattr(result, "isError", False):
        raise SystemExit(f"tool error: {result.content}")
    return result.content[0].text


async def main() -> None:
    cwd, command, *args = sys.argv[1:]
    # the client passes a minimal environment by default; the launcher needs ours
    params = StdioServerParameters(command=command, args=args, cwd=cwd, env=dict(os.environ))
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            names = {t.name for t in (await session.list_tools()).tools}
            missing = EXPECTED - names
            if missing:
                raise SystemExit(f"missing tools: {sorted(missing)}")
            saved = json.loads(text(await session.call_tool(
                "save_note", {"name": "from-agent", "note": {"title": "agent", "body": "x y"}})))
            got = json.loads(text(await session.call_tool("read_note", {"name": "from-agent"})))
            assert got["version"] == saved["version"] and got["data"]["title"] == "agent", got
            bad = await session.call_tool("validate_note", {"note": {"body": 1}})
            assert "title is required" in json.dumps([c.text for c in bad.content]), bad
            print("  mcp: tools listed, note saved and read back, validation ok")
            # the About box: the heartbeat must turn the MCP row green while
            # this server runs, without an agent having to call anything
            base = text(await session.call_tool("server_url", {})).strip().rstrip("/")
            state = None
            for _ in range(40):
                with urllib.request.urlopen(f"{base}/api/services", timeout=3) as res:
                    rows = {r["id"]: r for r in json.loads(res.read())["services"]}
                state = rows["mcp"]["state"]
                if state == "up":
                    break
                time.sleep(0.25)
            assert state == "up", rows["mcp"]
            print("  mcp: About shows the MCP server up —", rows["mcp"]["detail"])
            print("  mcp:", text(await session.call_tool("stop_server", {})))


asyncio.run(main())
