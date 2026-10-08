---
name: summary
description: Summarize the state of the user's Gmail. Shows read and unread counts for every label (from label metadata, without opening email), what's sitting in each primary inbox, which threads come from important contacts, and how many look ready to file. Use this whenever the user asks "what's in my inbox", "inbox status", "how's my email looking", "summarize my inbox", "anything new?", "how many unread do I have", or starts an email session and wants an overview, even if they don't say "summary". Writes the summary to inbox-summary.md, a living checklist the user annotates with directions; also use this when the user says they've updated or responded in inbox-summary.md.
argument-hint: "[optional focus, e.g. 'work only']"
---

# Summary

Give the user a quick, accurate picture of their mailbox so they can decide what to do next.

The summary lives in **`inbox-summary.md`** in the repo root (gitignored). It's a single living checklist: each run updates it, the user writes directions under items in their own editor, and Claude carries them out. Building or refreshing the summary changes nothing in the mailbox.

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
   - its labels, by name: the union across the messages shown, mapped from IDs with `CLAUDE.local.md`
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

## The file: `inbox-summary.md`

```markdown
# Inbox summary

Updated 2026-10-07 16:50. Write directions in the empty bullet under any item, then tell Claude. Items without directions are left alone.

## Counts by label

| Label | Unread | Read | Total |
|---|---|---|---|
| Inbox | 12 | 28 | 40 |
| Work | 3 | 15 | 18 |
| Google Scholar | 250 | 650 | 900 |

(N other labels: all read)

## Inbox (N threads, M unread)

1. ★ **Sender**: Subject (10/07) — one-line gist [unread] · labels: Inbox <!-- thread:18f3a2b4c5d6e701 -->
    - 
2. **Sender**: Subject (10/06) — one-line gist · labels: Inbox, Personal-Finances <!-- thread:18f3a2b4c5d6e702 -->
    - file to Work-Admin
    - ✓ filed to Work-Admin (10/07)

## Work (N threads, M unread)

1. **Sender**: Subject (10/05) — one-line gist · labels: Work, Work-Projects, Starred <!-- thread:18f3a2b4c5d6e703 -->
    - 

**K threads look fileable.**
```

- **Counts table:** primary inboxes first, then other labels by unread count, descending. Collapse fully read labels into one line.
- **Inbox sections:** one per primary inbox, each a numbered list starting at 1. List **every** thread (it's a file, so there's no need to hide any), priority senders and unread first, then newest first. Keep each gist to one line.
- **Labels:** each item ends with ` · labels: ` and the thread's current labels by name (CLAUDE.md rule 4): its primary inbox(es), any other user labels, and Starred. Leave out Unread (shown as `[unread]`), Important, Sent and Gmail categories. This shows the user what a thread already has and lets Claude plan edits (e.g. a thread already in Work-Projects only needs its inbox label removed). It's a snapshot from the last run, so still check live labels before changing anything.
- **Response bullet:** every item gets an indented (4 spaces) bullet underneath, empty until the user writes in it. An empty bullet may appear as `    - ` or `    -` (editors strip trailing spaces); both mean "no directions".
- **Thread ID:** each item ends with `<!-- thread:<id> -->`. It's invisible in a Markdown preview and is how items are matched to threads. Never show or ask the user to type it.
- **Done marker:** once Claude has carried out an item's directions, it adds a second bullet below the user's, `    - ✓ <what was done> (<M/D>)`. The user's bullet is never edited.

## Writing and refreshing the file

Each `/summary` run regenerates the counts, the `Updated` line, and the inbox lists from fresh data. If `inbox-summary.md` already exists, read it first and merge, matching items by thread ID:

- **Completed items are dropped** (any item with a `✓` bullet). If that thread is still in a primary inbox, it comes back as a fresh item with an empty response bullet.
- **Items with directions not yet carried out** keep the user's bullet text exactly as written, even if the thread details changed. If such a thread is no longer in any primary inbox (e.g. filed in Gmail directly), keep it at the end of its section with the gist `— no longer in this inbox` so the directions aren't silently lost, and mention it in chat.
- **Everything else** is rebuilt from fresh data; threads no longer in a primary inbox disappear.
- Renumber every section from 1 on each run. Numbers are labels for the current file, not stable IDs.

In chat, don't repeat the lists. Reply with the file path, the unread counts for the primary inboxes, anything urgent from a Tier 1 sender, the fileable count, and at most one next-step suggestion (e.g. `/suggest-replies urgent`).

## Acting on the user's directions

When the user says they've written in the file ("I updated inbox-summary.md", "done, take a look"):

1. **Read the file.** Collect every item whose response bullet has text and that has no `✓` bullet yet. Ignore every other item: no labels, no read-state changes, no drafts.
2. **Resolve each direction** to concrete actions on that item's thread ID. If a direction is ambiguous, ask about that item in chat instead of guessing. If a direction asks for no action now ("leave it", "review later"), do nothing and leave the item as is, so the note carries over to the next run.
3. **Drafts** can be created right away (CLAUDE.md rule 2), following `/draft-email`.
4. **Mailbox changes need approval** (CLAUDE.md rule 1). Before applying, check each thread still carries the expected inbox label ID, then show one compact table in chat (section and number, sender and subject, exact change, with labels named by name, never by ID; see CLAUDE.md rule 4) and wait for a yes. Apply exactly that.
5. **Mark each completed item** with a `✓` bullet saying what was done and the date (e.g. `✓ filed to Work-Admin, marked read (10/07)` or `✓ draft saved: drafts/<file>.md (10/07)`). If something failed, add `✗ <what failed>` instead and report it in chat. Touch nothing else in the file.

The user may also give directions in chat by section and number ("Inbox 3: file to Personal"). Treat those the same way, using the numbers in the current file.
