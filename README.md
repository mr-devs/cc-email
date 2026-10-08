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
   - Read tools and draft creation are allowed without prompts.
   - Sending, replying, forwarding, labeling, unlabeling, trashing, spam, and label creation or deletion are all set to `ask`, so Claude Code prompts you before each one.
3. **Approval rule** (`CLAUDE.md`): Claude proposes every mailbox change and waits for an explicit yes. Drafts are the only exception, since nothing leaves your account.

### Skills

| Command | What it does |
|---|---|
| `/summary` | Writes `inbox-summary.md` (gitignored): a short "Needs you" list, counts by label, then every thread in each primary inbox (with promotions and forums split into their own section). Each thread gets Claude's suggested action as a checkbox, an optional Apple Reminder checkbox (via `remindctl`) for deadlines and follow-ups, and an empty bullet for your own directions. Tick what you agree with or write directions ("file to Work-Admin", "draft a reply saying…"), tell Claude, and it carries them out (asking before any mailbox or reminder change) and moves finished items to a Done section. Re-running `/summary` refreshes the file and clears Done. |
| `/suggest-replies [urgent\|easy]` | Picks 1–3 threads to handle now and explains each choice. `urgent` favors deadlines and VIPs; `easy` favors quick wins. |
| `/draft-email` | Drafts a new email or reply from a gist, a tone (casual/professional/formal) and a length. Saves it as a Gmail draft and as a Markdown file in `drafts/` that you can edit; tell Claude when you've edited it and it syncs the changes to Gmail. Never sends without your yes. |
| `/file-away` | Proposes a destination label and a rationale for each fileable thread, then applies only what you approve |
| `/scholar-digest [N]` | Reads the newest N (default 25) unread Google Scholar alerts and surfaces relevant papers (title, authors, blurb, link). Asks for your feedback and records it in `research-interests.md`, then offers to mark the batch read. |
| `/contacts [add\|remove\|list\|suggest]` | Maintains three priority tiers (1 VIP, 2 Important, 3 Known) that the other skills use for ranking |

You can also just talk normally ("what's urgent?", "file the Zoom receipt away", "anything good in my Scholar alerts?"), and Claude picks the right skill.

## Customizing

- **A different connector name.** If your Gmail tools aren't named `mcp__claude_ai_Gmail__*` (check with `/mcp`), update the tool names in `.claude/agents/email-reader.md` and `.claude/settings.json`.
- **More primary inboxes.** List them in `CLAUDE.local.md`; the skills read them from there.
- **Not an academic?** Delete `.claude/skills/scholar-digest/` and `research-interests.example.md`.
- **Your own skills.** Add a folder under `.claude/skills/<name>/SKILL.md`.
