---
name: summary
description: Summarize the state of the user's Gmail. Shows read and unread counts for every label (from label metadata, without opening email), what's sitting in each primary inbox, with promotions and forums split out of the Inbox, which threads come from important contacts, a suggested action for each thread, and how many look ready to file. Use this whenever the user asks "what's in my inbox", "inbox status", "how's my email looking", "summarize my inbox", "anything new?", "how many unread do I have", or starts an email session and wants an overview, even if they don't say "summary". Writes the summary to inbox-summary.md, a living checklist the user annotates with directions; also use this when the user says they've updated or responded in inbox-summary.md.
argument-hint: "[optional focus, e.g. 'work only']"
---

# Summary

Give the user a quick, accurate picture of their mailbox so they can decide what to do next.

The summary lives in **`inbox-summary.md`** in the repo root (gitignored). It's a single living checklist: each run updates it, Claude suggests an action for every item, the user accepts or writes their own directions in their editor, and Claude carries them out. Building or refreshing the summary changes nothing in the mailbox.

**Never open an email in this skill.** Use only label counts and search results (sender, subject, date, labels, and Gmail's short preview). Don't call `get_thread` or `get_message`, and don't ask the reader to. A summary is an overview, and opening emails is slow and pulls message bodies into the conversation.

## Promotions and forums

Gmail sorts `INBOX` mail into categories (`CATEGORY_PROMOTIONS`, `CATEGORY_FORUMS`, `CATEGORY_UPDATES`, …). Inbox threads in **Promotions** or **Forums** are split out of the Inbox:

- They get their own section, **Promotions/Forums**, after the Work section, and their own row in the counts table.
- They are **not** counted in the Inbox row or the Inbox section heading. The Inbox counts cover only the remaining Inbox threads.
- A thread's category is the one on its latest message shown in the search results.
- This applies only to `INBOX`. Threads in other primary inboxes (e.g. `Work`) stay in their own section whatever their category.

Category labels don't appear in `list_labels`, so these counts come from the search results in step 2.

## Steps

1. **Counts for every label.** Call `mcp__claude_ai_Gmail__list_labels` once.
   - Each label includes `threadsUnread` and `threadsTotal`; read = total − unread.
   - Use thread counts rather than message counts, because a thread is how Gmail shows conversations.
   - For every label that isn't a primary inbox, these counts are the whole summary. Don't search those labels or look inside them. They hold mail that's already filed, so the numbers tell the user what they need (e.g. a large unread Google Scholar pile is a job for `/scholar-digest`).
   - The `INBOX` counts here include promotions and forums. Keep them only as a check on step 2; the Inbox and Promotions/Forums rows are computed from the merged search results.
   - If any user label is missing from `CLAUDE.local.md`, note it so you can add it (see CLAUDE.md rule 5).
2. **Primary-inbox contents (search results only).** List the threads in each primary inbox in `CLAUDE.local.md` (e.g. `INBOX` and a work label). Delegate to the `email-reader` agent and tell it **not to open any email**: it should use `search_threads` results only. Ask for each thread:
   - thread ID
   - sender
   - subject
   - date
   - read or unread
   - who sent the last message (the user or someone else)
   - its labels, by name: the union across the messages shown, mapped from IDs with `CLAUDE.local.md`
   - its Gmail category (Primary, Promotions, Forums, Updates, Social), from the `CATEGORY_*` label on the latest message shown
   - a one-line gist taken from the subject and preview
   If an ask or deadline isn't visible in the preview, the gist should say "details not in preview" rather than the email being opened. The search results may also show only some messages of a long thread; in that case "last sender" is based on the last message shown, and should be flagged as such.
   Use `search_threads` with `in:inbox` for INBOX and `label:<name>` for other labels (search by name, not ID; see CLAUDE.md rule 4), with `pageSize` 50, paginating if needed.

   **Split the reading across up to five `email-reader` agents running in parallel.** One agent paging through everything is slow, so give each agent one slice:
   - Start with these slices: `in:inbox -category:promotions -category:forums is:unread`, `in:inbox -category:promotions -category:forums -is:unread`, `in:inbox (category:promotions OR category:forums)`, and one per read state for each other primary inbox (e.g. `label:work is:unread`, `label:work -is:unread`). Use the counts from step 1 to skip empty slices (read = total − unread).
   - If that leaves fewer than five slices and one of them has more than ~50 threads, split it by date with `newer_than:7d` and `older_than:7d`. Never launch more than five agents.
   - Launch every agent in a single message so they run at the same time, and give each one the same instructions and fields as above, plus its exact query.
   - Gmail search matches messages, not threads, so slices can overlap (a thread with both read and unread messages, messages in more than one category, or messages on both sides of the date split, matches more than one). When merging, dedupe by thread ID: the thread is unread if any copy says so, and "last sender" and category come from the copy with the latest date. A thread in two primary inboxes is listed under both, as before.
   - Compute the Inbox and Promotions/Forums counts from the merged threads. If their sum doesn't match the `INBOX` counts from step 1, mention the gap in chat.
3. **Priority.** Match senders against `contacts.md`. A specific address beats a `@domain` match. Mark Tier 1 senders with ★ and Tier 2 senders with ☆.
4. **Fileable estimate.** Count threads that are read and addressed (the user sent the last message, or it's clearly FYI or automated).
5. **Suggestions.** Give every item one suggested action, based only on what's in the search results (see "Suggestion bullet" below).

If `$ARGUMENTS` names a focus (e.g. "work only"), limit steps 2–5 to it.

## The file: `inbox-summary.md`

```markdown
# Inbox summary

Updated 2026-10-07 16:50. Each item has Claude's suggestion, then a bullet for your directions. Write "ok" to accept the suggestion, or write your own directions, then tell Claude. Items with an empty second bullet are left alone.

## Counts by label

| Label | Unread | Read | Total |
|---|---|---|---|
| Inbox | 9 | 20 | 29 |
| Work | 3 | 15 | 18 |
| Promotions/Forums | 3 | 8 | 11 |
| Google Scholar | 250 | 650 | 900 |

(N other labels: all read)

## Inbox (N threads, M unread)

### Unread (M)

1. ★ **Sender**: Subject (10/07) — one-line gist · labels: Inbox <!-- thread:18f3a2b4c5d6e701 -->
    - Suggested: read it — Tier 1 sender; the ask isn't in the preview.
    - 

### Read (N − M)

2. **Sender**: Subject (10/06) — one-line gist · labels: Inbox, Personal-Finances <!-- thread:18f3a2b4c5d6e702 -->
    - Suggested: file to Personal-Finances — statement notice, nothing to do.
    - ok, but file to Work-Admin instead
    - ✓ filed to Work-Admin (10/07)

## Work (N threads, M unread)

### Read (N − M)

1. **Sender**: Subject (10/05) — one-line gist · labels: Work, Work-Projects, Starred <!-- thread:18f3a2b4c5d6e703 -->
    - Suggested: remove Work (already in Work-Projects) — you replied last and nothing is pending.
    - 

## Promotions/Forums (N threads, M unread: P promotions, F forums)

### Unread (M)

1. **Sender**: Subject (10/07) — one-line gist · labels: Inbox, Promotions <!-- thread:18f3a2b4c5d6e704 -->
    - Suggested: mark read and archive — marketing email, nothing to act on.
    - 

**K threads look fileable.**
```

- **Counts table:** Inbox, the other primary inboxes, and Promotions/Forums first, then other labels by unread count, descending. Collapse fully read labels into one line.
- **Sections:** one per primary inbox, in the order of `CLAUDE.local.md`, then Promotions/Forums last. List **every** thread (it's a file, so there's no need to hide any).
- **Read and unread groups:** within each section, put unread threads under `### Unread (M)` and read threads under `### Read (N − M)`, in that order, with the actual numbers. Omit an empty group. Within each group, priority senders first, then newest first. Number the items once per section, starting at 1 and continuing across both groups (Unread 1–3, Read 4–9), so "Inbox 4" names exactly one item. Keep each gist to one line. Omit the Promotions/Forums section if it's empty.
- **Labels:** each item ends with ` · labels: ` and the thread's current labels by name (CLAUDE.md rule 4): its primary inbox(es), any other user labels, and Starred. Leave out Unread (shown by the group), Important, Sent and Gmail categories, except in the Promotions/Forums section, where the category (`Promotions` or `Forums`) is listed last. This shows the user what a thread already has and lets Claude plan edits (e.g. a thread already in Work-Projects only needs its inbox label removed). It's a snapshot from the last run, so still check live labels before changing anything.
- **Suggestion bullet:** the first indented (4 spaces) bullet is Claude's suggestion, written as `Suggested: <action> — <reason>.` in one short sentence. Base it only on the search results, and pick one concrete action, for example:
  - `file to <label>`: only for fileable threads (read and addressed); name an existing destination label from `CLAUDE.local.md`. If the thread already carries the destination, say `remove Inbox` (or `remove Work`) instead.
  - `mark read and file to <label>` or `mark read and archive`: for unread automated mail, promotions and newsletters that need nothing from the user. Archiving removes the inbox label without adding a destination.
  - `reply` or `draft a reply with /draft-email`: when someone is waiting on the user. Say what the reply is about if the preview shows it.
  - `read it`: when the preview doesn't show enough to decide, e.g. "details not in preview".
  - `leave for now`: when something is pending (a deadline, a reply the user promised, a Starred thread).
  Never suggest filing or archiving an unanswered thread from a Tier 1 sender. Never suggest trash, spam or unsubscribing unless the mail is clearly junk, and say why.
- **Response bullet:** the second indented bullet is for the user, empty until they write in it. An empty bullet may appear as `    - ` or `    -` (editors strip trailing spaces); both mean "no directions".
- **Thread ID:** each item ends with `<!-- thread:<id> -->`. It's invisible in a Markdown preview and is how items are matched to threads. Never show or ask the user to type it.
- **Done marker:** once Claude has carried out an item's directions, it adds a third bullet below the user's, `    - ✓ <what was done> (<M/D>)`. The suggestion and the user's bullet are never edited.

## Writing and refreshing the file

Each `/summary` run regenerates the counts, the `Updated` line, and the section lists from fresh data. If `inbox-summary.md` already exists, read it first and merge, matching items by thread ID:

- **Completed items are dropped** (any item with a `✓` bullet). If that thread is still in a primary inbox or Promotions/Forums, it comes back as a fresh item with a new suggestion and an empty response bullet.
- **Items with directions not yet carried out** keep both the suggestion and the user's bullet exactly as written, even if the thread details changed, since the user's directions may refer to the suggestion. If such a thread is no longer in any section (e.g. filed in Gmail directly), keep it at the end of its section's Read group with the gist `— no longer in this inbox` so the directions aren't silently lost, and mention it in chat.
- **Older files** may have a single bullet per item with no `Suggested:` line. Treat a non-empty single bullet as the user's directions.
- **Everything else** is rebuilt from fresh data, with a fresh suggestion; threads no longer in a section disappear. A thread whose category changed moves to the right section.
- Threads move between the Unread and Read groups as their read state changes; carried-over directions move with them.
- Renumber every section from 1 on each run. Numbers are labels for the current file, not stable IDs.

## Reporting in chat

Don't repeat the thread lists in chat. Reply with:

1. The file path.
2. The counts table, as a Markdown table with the same rows as the file (Inbox, other primary inboxes, Promotions/Forums, then other labels by unread count), bolding the primary-inbox and Promotions/Forums rows, followed by the "N other labels: all read" line.
3. A few short bullets: anything urgent from a Tier 1 sender, the threads most worth the user's attention, and the fileable count.
4. At most one next-step suggestion (e.g. `/suggest-replies urgent`, or "accept the suggestions you agree with in the file").

## Acting on the user's directions

When the user says they've written in the file ("I updated inbox-summary.md", "done, take a look"):

1. **Read the file.** Collect every item whose response bullet (the one after `Suggested:`) has text and that has no `✓` bullet yet. Ignore every other item, even if it has a suggestion: no labels, no read-state changes, no drafts.
2. **Resolve each direction** to concrete actions on that item's thread ID.
   - An acceptance ("ok", "yes", "do it", "sounds good", "👍") means: carry out the suggestion as written.
   - Anything else is the user's own direction. It may build on the suggestion ("ok, but file to Personal instead", "yes and mark read"); read it together with the suggestion.
   - If a direction is ambiguous, ask about that item in chat instead of guessing. If a direction asks for no action now ("leave it", "review later"), do nothing and leave the item as is, so the note carries over to the next run.
3. **Drafts** can be created right away (CLAUDE.md rule 2), following `/draft-email`.
4. **Mailbox changes need approval** (CLAUDE.md rule 1). Accepting a suggestion in the file counts as a direction, not as approval. Before applying, check each thread still carries the expected inbox label ID, then show one compact table in chat (section and number, sender and subject, exact change, with labels named by name, never by ID; see CLAUDE.md rule 4) and wait for a yes. Apply exactly that.
5. **Mark each completed item** with a `✓` bullet saying what was done and the date (e.g. `✓ filed to Work-Admin, marked read (10/07)` or `✓ draft saved: drafts/<file>.md (10/07)`). If something failed, add `✗ <what failed>` instead and report it in chat. Touch nothing else in the file.

The user may also give directions in chat by section and number ("Inbox 3: file to Personal", "Promotions/Forums 2: ok"). Treat those the same way, using the numbers in the current file.
