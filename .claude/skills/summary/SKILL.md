---
name: summary
description: Summarize the state of the user's Gmail. Shows unread counts by label, what's sitting in each primary inbox, which threads come from important contacts, and how many look ready to file. Use this whenever the user asks "what's in my inbox", "inbox status", "how's my email looking", "summarize my inbox", "anything new?", "how many unread do I have", or starts an email session and wants an overview, even if they don't say "summary".
argument-hint: "[optional focus, e.g. 'work only']"
---

# Summary

Give the user a quick, accurate picture of their mailbox so they can decide what to do next. This is read-only. Change nothing.

## Steps

1. **Counts.** Call `mcp__claude_ai_Gmail__list_labels` once. Each label already includes `threadsUnread`/`threadsTotal`, so there's no need to search label by label. Use thread counts rather than message counts, because a thread is how Gmail shows conversations.
   - If any user label is missing from `CLAUDE.local.md`, note it so you can add it (see CLAUDE.md rule 5).
2. **Primary-inbox contents.** Read the primary inboxes listed in `CLAUDE.local.md` (e.g. `INBOX` and a work label). Delegate to the `email-reader` agent, asking for each thread in each primary inbox:
   - thread ID
   - sender
   - subject
   - date
   - read or unread
   - who sent the last message (the user or someone else)
   - a one-line gist
   Use `search_threads` with `in:inbox` for INBOX and `label:<ID>` for other labels, `pageSize` 50, paginating if needed.
3. **Priority.** Match senders against `contacts.md`. A specific address beats a `@domain` match. Mark Tier 1 senders with ★ and Tier 2 senders with ☆.
4. **Fileable estimate.** Count threads that are read and addressed (the user sent the last message, or it's clearly FYI or automated). Don't propose labels here; that's `/file-away`'s job.

If `$ARGUMENTS` names a focus (e.g. "work only"), limit steps 2–4 to it.

## Output format

```
## Unread by label
| Label | Unread | Total |
|---|---|---|
| Inbox | 12 | 40 |      ← primary inboxes first
| Work | 3 | 18 |
| Work/Google Scholar | 250 | 900 |
...                       ← then other labels by unread count, descending; hide labels with 0 unread

## Inbox (N threads, M unread)
- ★ **Sender**: Subject (date) — one-line gist [unread]
...

## Work (N threads, M unread)
...

**K threads look fileable.** Run `/file-away` to review them.
```

Keep each gist to one line. If an inbox has more than ~20 threads, show the top 15 (priority senders and unread first) and say how many are hidden. End with at most one suggestion for the next step, e.g. `/suggest-replies urgent` if there are Tier 1 threads waiting.
