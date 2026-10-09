#!/usr/bin/env python3
"""A stand-in for `claude` that replays a scripted stream-json turn. Makes no network calls.

For UI development without using any Claude Code usage. Point the debug build at it:

    defaults write CCEmail claudePath "$PWD/app/scripts/fake-claude.py"
    CCEMAIL_AUTORUN=/summary app/.build/debug/CCEmail

It answers `--version` and `auth status`, and in `-p` mode replies to every user message with
the same turn: a few tool calls with long inputs, a subagent, streamed text with a wide table,
then a permission request (for the `I updated` message) and a result. FAKE_CLAUDE_DELAY scales the pauses.
"""

import json
import sys
import time
import uuid

DELAY = float(__import__("os").environ.get("FAKE_CLAUDE_DELAY", "1"))
args = sys.argv[1:]

if "--version" in args:
    print("2.1.295 (Claude Code)")
    sys.exit(0)
if args[:2] == ["auth", "status"]:
    print(
        json.dumps(
            {"loggedIn": True, "authMethod": "claude.ai", "subscriptionType": "max"}
        )
    )
    sys.exit(0)

session = (
    args[args.index("--session-id") + 1]
    if "--session-id" in args
    else (args[args.index("--resume") + 1] if "--resume" in args else str(uuid.uuid4()))
)


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def pause(seconds):
    time.sleep(seconds * DELAY)


def tool(name, tool_input, parent=None, result="ok"):
    tid = "toolu_" + uuid.uuid4().hex[:12]
    emit(
        {
            "type": "assistant",
            "parent_tool_use_id": parent,
            "session_id": session,
            "message": {
                "id": "msg_" + tid,
                "content": [
                    {"type": "tool_use", "id": tid, "name": name, "input": tool_input}
                ],
            },
        }
    )
    return tid, result


def finish_tool(tid, result, parent=None):
    emit(
        {
            "type": "user",
            "parent_tool_use_id": parent,
            "session_id": session,
            "message": {
                "role": "user",
                "content": [
                    {"type": "tool_result", "tool_use_id": tid, "content": result}
                ],
            },
        }
    )


def stream_text(text):
    for i in range(0, len(text), 24):
        emit(
            {
                "type": "stream_event",
                "parent_tool_use_id": None,
                "session_id": session,
                "event": {
                    "type": "content_block_delta",
                    "index": 0,
                    "delta": {"type": "text_delta", "text": text[i : i + 24]},
                },
            }
        )
        pause(0.03)
    emit(
        {
            "type": "assistant",
            "parent_tool_use_id": None,
            "session_id": session,
            "message": {
                "id": "msg_" + uuid.uuid4().hex[:8],
                "content": [{"type": "text", "text": text}],
            },
        }
    )


REPORT = """I've updated `inbox-summary.md`. Your Inbox is empty and Work has 4 threads, 1 of them unread.

| Label | Unread | Read |
|---|--:|--:|
| **Work** | 1 | 3 |
| Work-Google-Scholar | 1,670 | 1,115 |

- **Needs you:** W1. A collaborator asked through Google Drive for access to your "Research Lab Schedule" spreadsheet, which arrived this afternoon and is waiting on you.
- **Reminders:** none suggested.

Your file asks for one change:

| Tag | Thread | Change |
|---|---|---|
| W1 | Google Drive · Share request for "2026 Research Lab Schedule" spreadsheet | Add Work-Admin, remove Work, mark read |

Should I apply it?"""

for line in sys.stdin:
    try:
        msg = json.loads(line)
    except json.JSONDecodeError:
        continue
    if msg.get("type") == "control_request":
        subtype = msg["request"].get("subtype")
        body = {}
        if subtype == "get_usage":
            body = {
                "subscription_type": "max",
                "rate_limits_available": True,
                "rate_limits": {
                    "five_hour": {
                        "utilization": 34,
                        "resets_at": "2099-01-01T00:00:00+00:00",
                    },
                    "seven_day": {
                        "utilization": 91,
                        "resets_at": "2099-01-05T13:00:00+00:00",
                    },
                },
            }
        elif subtype == "get_context_usage":
            body = {
                "totalTokens": 340000,
                "maxTokens": 1000000,
                "percentage": 34,
                "model": "claude-opus-5-5[1m]",
            }
        elif subtype == "list_models":
            body = {
                "models": [
                    {"value": "default", "displayName": "Default (recommended)"},
                    {"value": "opus", "displayName": "Opus 5.5"},
                    {"value": "sonnet", "displayName": "Sonnet 5.5"},
                    {"value": "haiku", "displayName": "Haiku 5.5"},
                ]
            }
        emit(
            {
                "type": "control_response",
                "response": {
                    "subtype": "success",
                    "request_id": msg["request_id"],
                    "response": body,
                },
            }
        )
        continue
    if msg.get("type") == "control_response":
        continue
    if msg.get("type") != "user":
        continue
    text = msg["message"]["content"]

    emit(
        {
            "type": "system",
            "subtype": "init",
            "session_id": session,
            "model": "fake",
            "cwd": ".",
            "claude_code_version": "2.1.295",
            "permissionMode": "default",
            "apiKeySource": "none",
            "tools": [],
            "slash_commands": ["summary"],
            "mcp_servers": [{"name": "claude.ai Gmail", "status": "connected"}],
        }
    )
    pause(0.5)
    for name, tool_input in [
        (
            "ToolSearch",
            {
                "query": "select:mcp__claude_ai_Gmail__get_thread,mcp__claude_ai_Gmail__label_thread,mcp__claude_ai_Gmail__unlabel_thread,mcp__claude_ai_Gmail__list_labels"
            },
        ),
        (
            "Bash",
            {
                "command": "ls",
                "description": "List workspace files and check Reminders access with a fairly long description that keeps going",
            },
        ),
        (
            "Read",
            {
                "file_path": "/Users/someone/Documents/Projects/cc-email/a/very/deeply/nested/path/to/inbox-summary.md"
            },
        ),
    ]:
        tid, _ = tool(name, tool_input)
        pause(0.6)
        finish_tool(tid, "ok")
    agent, _ = tool(
        "Agent", {"description": "List unread Work threads", "prompt": "..."}
    )
    for _ in range(3):
        sub, _ = tool(
            "mcp__claude_ai_Gmail__search_threads",
            {"query": "label:work is:unread"},
            parent=agent,
        )
        pause(0.5)
        finish_tool(sub, "ok", parent=agent)
    finish_tool(agent, "done")
    pause(0.5)

    if text.startswith("I updated"):
        emit(
            {
                "type": "control_request",
                "request_id": "req-" + uuid.uuid4().hex[:6],
                "request": {
                    "subtype": "can_use_tool",
                    "tool_name": "Bash",
                    "tool_use_id": "toolu_perm",
                    "input": {
                        "command": 'remindctl add --title "Submit review" --list Reviews --due 2026-10-13 "--notes=- Due Date: 10/15" --no-input --json'
                    },
                    "description": "Create a reminder",
                },
            }
        )
        # Wait for the answer before continuing.
        for answer in sys.stdin:
            if json.loads(answer).get("type") == "control_response":
                break

    stream_text(REPORT)
    emit(
        {
            "type": "result",
            "subtype": "success",
            "is_error": False,
            "session_id": session,
            "result": REPORT,
            "duration_ms": 9000,
            "num_turns": 4,
            "total_cost_usd": 0.0,
            "permission_denials": [],
        }
    )
