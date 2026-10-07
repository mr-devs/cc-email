---
name: summary
description: Summarize the state of the user's Gmail. Shows read and unread counts for every label (from label metadata, without opening email), what's sitting in each primary inbox, which threads come from important contacts, and how many look ready to file. Use this whenever the user asks "what's in my inbox", "inbox status", "how's my email looking", "summarize my inbox", "anything new?", "how many unread do I have", or starts an email session and wants an overview, even if they don't say "summary".
argument-hint: "[optional focus, e.g. 'work only']"
---

# Summary

Give the user a quick, accurate picture of their mailbox so they can decide what to do next. This is read-only. Change nothing.

**Never open an email in this skill.** Use only label counts and search results (sender, subject, date, labels, and Gmail's short preview). Don't call `get_thread` or `get_message`, and don't ask the reader to. A summary is an overview, and opening emails is slow and pulls message bodies into the conversation.

## Steps

1. **Counts for every label.** Call `mcp__claude_ai_Gmail__list_labels` once.
   - Each label includes `threadsUnread` and `threadsTotal`; read = total − unread.
   - Use thread counts rather than message counts, because a thread is how Gmail shows conversations.
   - For every label that isn't a primary inbox, these counts are the whole summary. Don't search those labels or look inside them. They hold mail that's already filed, so the numbers tell the user what they need (e.g. a large unread Google Scholar pile is a job for `/scholar-digest`).
   - If any user label is missing from `CLAUDE.local.md`, note it so you can add it (see CLAUDE.md rule 5).
2. **Primary-inbox contents (search results only).** List the threads in each primary inbox in `CLAUDE.local.md` (e.g. `INBOX` and a work label). Delegate to the `email-reader` agent and tell it **not to open any email**: it should use `search_threads` results only. Ask for each thread:
   - thread ID
   - sender
   - subject
   - date
   - read or unread
   - who sent the last message (the user or someone else)
   - a one-line gist taken from the subject and preview
   If an ask or deadline isn't visible in the preview, the gist should say "details not in preview" rather than the email being opened. The search results may also show only some messages of a long thread; in that case "last sender" is based on the last message shown, and should be flagged as such.
   Use `search_threads` with `in:inbox` for INBOX and `label:<name>` for other labels (search by name, not ID; see CLAUDE.md rule 4), with `pageSize` 50, paginating if needed.

   **Split the reading across up to five `email-reader` agents running in parallel.** One agent paging through everything is slow, so give each agent one slice:
   - Start with one slice per primary inbox and read state, e.g. `in:inbox is:unread`, `in:inbox -is:unread`, `label:work is:unread`, `label:work -is:unread`. Use the counts from step 1 to skip empty slices (read = total − unread).
   - If that leaves fewer than five slices and one of them has more than ~50 threads, split it by date with `newer_than:7d` and `older_than:7d`. Never launch more than five agents.
   - Launch every agent in a single message so they run at the same time, and give each one the same instructions and fields as above, plus its exact query.
   - Gmail search matches messages, not threads, so slices can overlap (a thread with both read and unread messages, or with messages on both sides of the date split, matches both). When merging, dedupe by thread ID: the thread is unread if any copy says so, and "last sender" comes from the copy with the latest date. A thread in two primary inboxes is listed under both, as before.
3. **Priority.** Match senders against `contacts.md`. A specific address beats a `@domain` match. Mark Tier 1 senders with ★ and Tier 2 senders with ☆.
4. **Fileable estimate.** Count threads that are read and addressed (the user sent the last message, or it's clearly FYI or automated). Don't propose labels here; that's `/file-away`'s job.

If `$ARGUMENTS` names a focus (e.g. "work only"), limit steps 2–4 to it.

## Output format

```
## Counts by label
| Label | Unread | Read | Total |
|---|---|---|---|
| Inbox | 12 | 28 | 40 |      ← primary inboxes first
| Work | 3 | 15 | 18 |
| Google Scholar | 250 | 650 | 900 |
...                              ← then other labels by unread count, descending
(N other labels: all read)       ← collapse fully read labels into one line

## Inbox (N threads, M unread)
1. ★ **Sender**: Subject (date) — one-line gist [unread]
2. **Sender**: Subject (date) — one-line gist
...

## Work (N threads, M unread)
1. **Sender**: Subject (date) — one-line gist
...

**K threads look fileable.** Run `/file-away` to review them.
```

Keep each gist to one line. If an inbox has more than ~20 threads, show the top 15 (priority senders and unread first) and say how many are hidden. End with at most one suggestion for the next step, e.g. `/suggest-replies urgent` if there are Tier 1 threads waiting.

**Number every thread.** Each primary-inbox section is a numbered list that starts at 1, so the user can refer to a thread as "Inbox 3" or "Work 3". Hidden threads get no number; if the user asks to see them, show them as a continuation of the same list (16, 17, …) without renumbering. Keep each number's thread ID from the reader results, so a number can be mapped back to its thread later.

## Acting on numbered directions

The user may reply with directions keyed to those numbers, grouped by inbox:

```
Inbox:
1. file to Work-Admin
3. draft a reply saying I'll be there
7. mark as read
```

- Act **only** on the numbers listed. Anything not listed (here Inbox 2, 4–6 and everything in Work) is left untouched: no labels, no read-state changes, no drafts.
- Numbers refer to the most recent summary list in the conversation. If a direction is ambiguous, or a number doesn't exist, ask about that item instead of guessing.
- Drafts can be created right away (CLAUDE.md rule 2), using `/draft-email`'s approach.
- Every mailbox change still needs approval (CLAUDE.md rule 1). Before applying, show one compact table of what each direction resolves to (number, sender and subject, exact change with label IDs), then wait for a yes and apply exactly that.
