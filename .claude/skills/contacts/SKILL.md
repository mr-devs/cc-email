---
name: contacts
description: Maintain contacts.md, the user's tiered list of important email senders (Tier 1 VIP, Tier 2 Important, Tier 3 Known), which the other email skills use for prioritization. Supports add, remove, list, and suggest (find frequent correspondents in Sent mail and ask which tier each belongs in). Use this whenever the user says something like "X is important", "treat emails from Y as VIP", "add my advisor to my contacts", "who are my important contacts", "stop prioritizing Z", or wants to tune what counts as high priority.
argument-hint: "add <email|@domain> <tier> [name] [note] | remove <email> | list | suggest"
---

# Contacts

`contacts.md` tells the other skills whose email matters most. Keep it accurate and small; the tiers only help if they stay meaningful.

| Tier | Meaning | Expected response | How the skills use it |
|---|---|---|---|
| 1 VIP | Always surface | Same day | ★ in summaries; first in `/suggest-replies urgent`; never filed unanswered |
| 2 Important | Prioritize | Within a few days | ☆ in summaries; ranked above unknown senders |
| 3 Known | Routine | Whenever | Recognized, but no boost (useful for domains like `@university.edu`) |

Each tier heading has a Markdown table with the columns `Address | Name | Note`, one row per entry: `| address-or-@domain | name | note |`. Keep the table's header and `|---|---|---|` separator rows even when the tier is empty, and never write bare pipe-separated lines (they don't render as a table). A specific address takes precedence over a `@domain` entry. If `contacts.md` is missing, create it from `contacts.example.md`, keeping the headings and table headers and removing the example rows.

## Subcommands

Parse the subcommand from `$ARGUMENTS`. If there isn't one, infer it from the conversation (e.g. "Jane is important" means add).

- **list**: print the tiers compactly. If the file is empty, suggest running `suggest`.
- **add**: add the entry under the right tier. This edits the file directly, since the user asked for it.
  - If the address already exists, move it to the new tier instead of duplicating it.
  - If the tier isn't specified, ask; don't guess.
  - If only a name is given, find the address with `search_threads` (`from:<name>`) and confirm it.
- **remove**: delete the entry and confirm what was removed.
- **suggest**: seed or refresh the list from real behavior.
  1. Ask the `email-reader` agent to scan recent Sent mail (`in:sent newer_than:6m`, a few pages) and count the people the user writes to most. It should report each address, the name, the number of threads, and the most recent date. Skip the user's own addresses (`CLAUDE.local.md`), no-reply addresses and mailing lists.
  2. Drop anyone already listed. Take the top ~12 candidates.
  3. Use `AskUserQuestion` to sort them: one question per candidate (up to 4 per call), with options Tier 1 / Tier 2 / Tier 3 / Skip. Put the count and a hint about the relationship in the question text, e.g. "jane@x.edu — 14 threads, last 9/30".
  4. Write only the answered entries, then show the updated list.

Keep the file tidy: sort entries alphabetically within each tier, and keep notes short (role or relationship).
