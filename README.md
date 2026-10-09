# cc-email

A [Claude Code](https://code.claude.com) workspace for triaging Gmail. It gives you a read-only reader agent, a handful of skills (summarize, suggest replies, draft, file, digest Google Scholar alerts, manage priority contacts), and guardrails that make Claude ask before it changes anything in your mailbox.

It's a **template repository**. Click **Use this template** on GitHub, or clone it, then fill in the private config files described below.

## Prerequisites

- Claude Code, signed in with a claude.ai account.
- The **Gmail connector** enabled on claude.ai (Settings → Connectors). Claude Code exposes its tools as `mcp__claude_ai_Gmail__*`. Run `/mcp` inside Claude Code to check that they're available.

## Setup

```bash
git clone <your copy of this repo> cc-email && cd cc-email
cp CLAUDE.local.example.md CLAUDE.local.md
cp contacts.example.md contacts.md
cp research-interests.example.md research-interests.md   # only if you use Google Scholar alerts
cp .claude/skills/draft-email/references/signatures.example.md .claude/skills/draft-email/references/signatures.md   # then paste in your own signatures
claude
```

Then ask Claude to *"fill in CLAUDE.local.md from my Gmail labels"*. It will call `list_labels`, write your label tree with label IDs, and propose a one-line definition for each label for you to edit. Tell it which labels are your **primary inboxes**, the ones you want to keep empty (e.g. `INBOX` plus a label that collects forwarded mail from a work account). Finally, run `/contacts suggest` to seed your priority list from your Sent mail.

## How it works

### Public vs. private files

| File | Committed | Purpose |
|---|---|---|
| `CLAUDE.md` | ✅ | Workflow rules and vocabulary, shared by everyone |
| `CLAUDE.local.md` | ❌ gitignored | Your addresses, primary inboxes, label tree (IDs and definitions), open items. Claude Code loads it automatically. |
| `contacts.md` | ❌ gitignored | Your tiered list of important senders |
| `projects.md` | ❌ gitignored | Your research projects with the Apple Reminders list for each, plus your other reminder lists |
| `research-interests.md` | ❌ gitignored | Your research profile, plus what `/scholar-digest` learns from your feedback |
| `.claude/skills/draft-email/references/signatures.md` | ❌ gitignored | Your email signatures and which one `/draft-email` uses for new emails vs. replies |
| `inbox-summary.md` | ❌ gitignored | The living inbox checklist written by `/summary` |
| `drafts/` | ❌ gitignored (except its README) | Temporary, editable copies of email drafts in progress; each file is deleted once its email is sent |
| `*.example.md` | ✅ | Blank templates for the private files |

### Concepts

- **Primary inbox**: a label you want kept empty, e.g. `INBOX`.
- **Filing** a thread means adding a destination label and removing the primary-inbox label. Gmail uses labels, not folders, so "move it to X" and "file this away" both mean filing.
- **Fileable** means the thread is read **and** addressed: you replied, or it needs no reply.

### Safety model

1. **`email-reader` agent** (`.claude/agents/email-reader.md`). Its `tools:` allowlist contains only read tools (`search_threads`, `get_thread`, `get_message`, `list_labels`, `list_drafts`, `get_draft`) plus local file reads, so it can't change anything. Skills hand bulk reading to it.
2. **Permission rules** (`.claude/settings.json`):
   - Read tools, draft creation, thread labeling and unlabeling, and label creation, renaming and deletion are allowed without prompts. The approval rule below still applies to them: Claude proposes the change and waits for your yes.
   - Sending, replying, forwarding, deleting drafts, message-level label changes, trashing and spam are set to `ask`, so Claude Code also prompts you before each one.
3. **Approval rule** (`CLAUDE.md`): Claude proposes every mailbox change and waits for an explicit yes. Drafts are the only exception, since nothing leaves your account.

### Skills

| Command | What it does |
|---|---|
| `/summary` | Writes `inbox-summary.md` (gitignored): a short "Needs you" list, counts by label, then every thread currently in each primary inbox (with promotions and forums split into their own section). Each thread is one block: its subject (linked to Gmail), sender, a one-line summary and its labels, then Claude's suggested action as a checkbox, an optional Apple Reminder checkbox (via `remindctl`) for deadlines and follow-ups, and a Notes line for your own directions. Tick what you agree with or write directions ("file to Work-Admin", "draft a reply saying…"), tell Claude, and it carries them out (asking before any mailbox or reminder change) and moves finished items to a Done section. Re-running `/summary` refreshes the file and clears Done. |
| `/suggest-replies [urgent\|easy]` | Picks 1–3 threads to handle now and explains each choice. `urgent` favors deadlines and VIPs; `easy` favors quick wins. |
| `/draft-email` | Drafts a new email or reply from a gist, a tone (casual/professional/formal) and a length. Saves it as a Gmail draft and as a Markdown file in `drafts/` that you can edit; tell Claude when you've edited it and it syncs the changes to Gmail. Never sends without your yes. |
| `/file-away` | Proposes a destination label and a rationale for each fileable thread, then applies only what you approve |
| `/scholar-digest [N]` | Reads the newest N (default 25) unread Google Scholar alerts and surfaces relevant papers (title, authors, blurb, link). Asks for your feedback and records it in `research-interests.md`, then offers to mark the batch read. |
| `/contacts [add\|remove\|list\|suggest]` | Maintains three priority tiers (1 VIP, 2 Important, 3 Known) that the other skills use for ranking |

You can also just talk normally ("what's urgent?", "file the Zoom receipt away", "anything good in my Scholar alerts?"), and Claude picks the right skill.

## Mac app (optional)

`app/` contains **CC Email**, a small native macOS app on top of this workspace. It has three views:

- **Summary** shows `inbox-summary.md` as a checklist. You tick suggestions and reminders and write notes there, then click **Apply Notes**.
- **Drafts** lets you browse and edit the files in `drafts/`, then sync them to Gmail.
- **Chat** runs the skills, shows Claude's approval tables, and has a **Yes** button. Its footer has a model picker (default Opus 5.5 with the 1M context) and a status-line-style readout of context, session and weekly usage. Claude Code reports these itself with `get_usage` and `get_context_usage`, which make no model call; the app never reads your credentials.

The app never talks to Gmail itself. Everything goes through `claude -p` run in this folder, so the skills, `CLAUDE.md` and the permission rules apply exactly as they do in the terminal. A permission prompt (for example `remindctl add` or a send) opens as a dialog that shows exactly what will run. AskUserQuestion opens as a native question sheet.

**It only uses your Claude Code login.** It removes `ANTHROPIC_API_KEY` and other provider settings from `claude`'s environment, runs `claude auth status` before every session, and refuses to start unless that reports your claude.ai login. It also stops any session whose init event reports other credentials. It makes no other network calls.

Requirements: macOS 14+, Claude Code signed in with `claude auth login`, and the Swift toolchain (Xcode or just `xcode-select --install`).

```sh
app/scripts/bundle.sh            # builds app/build/CC Email.app
app/scripts/bundle.sh --install  # …and copies it to ~/Applications
app/scripts/dev.sh test          # unit tests
app/scripts/dev.sh run           # run without bundling
```

- **Finding this folder:** the app looks for it by walking up from where the app lives. If you install the app elsewhere, choose the folder on first launch or in Settings.
- **Bundle ID:** set `BUNDLE_ID` to use your own instead of `com.example.ccemail`.
- **Where data goes:** conversation transcripts can include email content. They're saved in `~/Library/Application Support/CC Email/`, never in this repo.
- **SDK selection:** with only the Command Line Tools installed, the scripts build against the newest SDK whose SwiftUI works without Xcode's macro plugin (`app/scripts/sdk.sh`).
- **Stale builds:** if a build fails with "plugin for module … not found", delete `app/.build` and try again.
- **UI work without using Claude Code:** `app/scripts/fake-claude.py` replays a scripted turn and makes no network calls. To use it, point the debug build at it with `defaults write CCEmail claudePath "$PWD/app/scripts/fake-claude.py"`, then use the `CCEMAIL_*` variables in `app/Sources/CCEmail/DevHooks.swift`. They can send a message automatically, resize the window, take snapshots and keep the test data separate.

## Customizing

- **A different connector name.** If your Gmail tools aren't named `mcp__claude_ai_Gmail__*` (check with `/mcp`), update the tool names in `.claude/agents/email-reader.md` and `.claude/settings.json`.
- **More primary inboxes.** List them in `CLAUDE.local.md`; the skills read them from there.
- **Not an academic?** Delete `.claude/skills/scholar-digest/` and `research-interests.example.md`.
- **Your own skills.** Add a folder under `.claude/skills/<name>/SKILL.md`.
