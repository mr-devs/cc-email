---
name: summary
description: Summarize the state of the user's Gmail. Shows read and unread counts for every label (from label metadata, without opening email), what's sitting in each primary inbox, with promotions and forums split out of the Inbox, which threads come from important contacts, a suggested action for each thread (plus an Apple Reminder via remindctl when a thread has a deadline or follow-up), and how many look ready to file. Use this whenever the user asks "what's in my inbox", "inbox status", "how's my email looking", "summarize my inbox", "anything new?", "how many unread do I have", or starts an email session and wants an overview, even if they don't say "summary". Writes the summary to inbox-summary.md, a living checklist the user annotates with directions; also use this when the user says they've updated or responded in inbox-summary.md.
argument-hint: "[optional focus, e.g. 'work only']"
---

# Summary

Give the user a quick, accurate picture of their mailbox so they can decide what to do next.

The summary lives in **`inbox-summary.md`** in the repo root (gitignored). It's a single living checklist: each run updates it, Claude suggests an action for every item (plus an Apple Reminder where one would help), the user accepts or writes their own directions in their editor, and Claude carries them out. Building or refreshing the summary changes nothing in the mailbox or in Reminders.

**Never open an email in this skill.** Use only label counts and search results (sender, subject, date, labels, and Gmail's short preview). Don't call `get_thread` or `get_message`, and don't ask the reader to. A summary is an overview, and opening emails is slow and pulls message bodies into the conversation.

## Promotions and forums

Gmail sorts `INBOX` mail into categories (`CATEGORY_PROMOTIONS`, `CATEGORY_FORUMS`, `CATEGORY_UPDATES`, …). Inbox threads in **Promotions** or **Forums** are split out of the Inbox:

- They get their own section, **Promotions/Forums**, after the Work section, and their own row in the counts table.
- They are **not** counted in the Inbox row or the Inbox section heading. The Inbox counts cover only the remaining Inbox threads.
- A thread's category is the one on its latest message shown in the search results.
- This applies only to `INBOX`. Threads in other primary inboxes (e.g. `Work`) stay in their own section whatever their category.

Category labels don't appear in `list_labels`, so these counts come from the search results in step 2.

## Reminders

The user keeps to-dos in Apple Reminders, which Claude reads and writes with the `remindctl` CLI (see "Reminders" in `CLAUDE.md`). An email is for reading and replying; a reminder is for something the user must do or check **later**, on or before a date. Suggest one when the search results show:

- a deadline or due date: a review due, a form or registration closing, an RSVP-by date, a bill due;
- an event or meeting the user has to prepare for or act on before it happens (not just attend: calendar invites already live on the calendar);
- a follow-up: the user sent the last message and is waiting on an answer that matters, or the user promised something ("I'll send it next week");
- an email that fits a list described in `projects.md` as collecting something other than deadlines (e.g. ideas to write about, such as major breaking news in a newsletter preview, or deadlines to post somewhere). Follow that list's description and any section `projects.md` gives it, including what must stay out of it.

Don't suggest a reminder when the action is quick enough to do now (reply, file, pay), when a deadline's date isn't in the preview (suggest `read it` instead), or when the email is pure FYI. Most threads don't need one; a typical run suggests a handful at most.

A reminder suggestion names a title, a due date and a list:

- **Title:** a short imperative that makes sense without opening the email, with no dates in it, e.g. `Submit ICWSM review`. A hard deadline goes in the notes as `Due Date` (see "Reminders" in `CLAUDE.md`).
- **Due date:** required; never suggest a reminder without one. It's when the user should act, not the hard deadline: a couple of days before a deadline, the morning of a prep task, about a week out for a follow-up. Date only (`M/D`, meaning its next occurrence; see "Reminders" in `CLAUDE.md`), no time, unless the email gives one that matters.
- **List:** chosen by the rules in "Reminders" in `CLAUDE.md`, including `in new list "<name>"` for a project without a list and `(project unclear: <A> or <B>?)` when the project is ambiguous.

Never create, edit or complete a reminder while building or refreshing the summary.

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
5. **Existing reminders.** Run `remindctl status` (see "Reminders" in `CLAUDE.md`); if it fails, skip reminder suggestions and say so once in chat. Otherwise run `remindctl search mail.google.com --json` once: reminders Claude created from email carry the thread's Gmail link, so any thread ID that appears in a result's notes (or, for older reminders, its URL) already has an open reminder. Don't suggest a second one for that thread. Also run `remindctl list` for the current list names and read `projects.md`. If a list exists in Reminders but not in `projects.md`, or the other way round, mention it once in chat.
6. **Suggestions.** Give every item one suggested action, based only on what's in the search results, plus a reminder where one is warranted (see "Reminders" above and "Suggestion bullet" below).

If `$ARGUMENTS` names a focus (e.g. "work only"), limit steps 2–6 to it.

## The file: `inbox-summary.md`

```markdown
# Inbox summary

Updated 2026-10-07 16:50. Tick a box to accept that suggestion or reminder, or write your own directions in the empty bullet, then tell Claude. Items with no tick and an empty bullet are left alone.

## Needs you

- **Work 2** · Editor — review due 10/15
- **Inbox 1** · ★ Sender — Tier 1 sender; the ask isn't in the preview

## Counts by label

| Label | Unread | Read |
|---|---|---|
| Inbox | 9 | 20 |
| Work | 3 | 15 |
| Promotions/Forums | 3 | 8 |
| Work-Google-Scholar | 250 | 650 |

(N other labels: all read)

## Inbox (N threads, M unread)

### Unread (M)

1. ★ **Sender** · Subject · 10/07\
    One-line gist; details not in preview. *Inbox* <!-- thread:18f3a2b4c5d6e701 -->
    - [ ] Read it — Tier 1 sender; the ask isn't in the preview.
    - 

### Read (N − M)

2. **Sender** · Subject · 10/06\
    Monthly statement is ready. *Inbox* <!-- thread:18f3a2b4c5d6e702 -->
    - [ ] File to Personal-Finances — statement notice, nothing to do.
    - file to Work-Admin instead

## Work (N threads, M unread)

### Read (N − M)

1. **Sender** +3 · Subject · 10/05\
    One-line gist. *Work, Work-Projects, Starred · partial thread* <!-- thread:18f3a2b4c5d6e703 -->
    - [x] Remove Work (already in Work-Projects) — you replied last and nothing is pending.
    - 
2. **Editor** · Review assignment · 10/04\
    You accepted; review due 10/15. *Work, Work-Reviews* <!-- thread:18f3a2b4c5d6e705 -->
    - [ ] Remove Work (already in Work-Reviews) — accepted already; the deadline is the only thing left.
    - [ ] ⏰ Remind "Submit ICWSM review" on 10/13 in Reviews (due 10/15)
    - 

## Promotions/Forums (N threads, M unread: P promotions, F forums)

### Unread (M)

1. **Sender** · Subject · 10/07\
    One-line gist. *Inbox, Promotions* <!-- thread:18f3a2b4c5d6e704 -->
    - [ ] Mark read and archive — marketing email, nothing to act on.
    - 

**K threads look fileable.**

## Done

- ✓ Inbox 3 · **Sender** · Subject — filed to Work-Admin, marked read (10/07) <!-- thread:18f3a2b4c5d6e706 -->
```

- **Needs you:** 3–5 lines at the top for what needs the user personally: someone waiting on a reply, a deadline within ~3 weeks, a Tier 1 thread to read. Each line is `- **<Section> <number>** · <sender> — <what's needed, with the date if any>`, pointing at the item below. Soonest deadline first, then Tier 1, then whoever has waited longest. Leave out items the user already said they'll handle (a ticked `Leave for now`, or "I'll handle it" in the response bullet), and omit the section when nothing qualifies.
- **Counts table:** columns Unread and Read (no Total). Rows: Inbox, the other primary inboxes and Promotions/Forums first, then other labels with unread threads, by unread count, descending. Drop any row that is 0 and 0, and collapse fully read labels into the one `(N other labels: all read)` line.
- **Sections:** one per primary inbox, in the order of `CLAUDE.local.md`, then Promotions/Forums last. List **every** thread (it's a file, so there's no need to hide any). Omit the Promotions/Forums section if it's empty.
- **Read and unread groups:** within each section, put unread threads under `### Unread (M)` and read threads under `### Read (N − M)`, in that order, with the actual numbers. Omit an empty group. Within each group, priority senders first, then newest first. Number the items once per section, starting at 1 and continuing across both groups (Unread 1–3, Read 4–9), so "Inbox 4" names exactly one item.
- **Item, line 1:** `<n>. [★|☆ ]**Sender**[ +N] · Subject · M/D\`. `+N` counts the thread's other visible participants besides the sender and the user; leave it out when there are none. The trailing `\` is a Markdown line break, so the preview keeps line 2 on its own line.
- **Item, line 2** (indented 4 spaces): the gist, one short sentence (aim for under ~100 characters), then the labels and any caveat in italics, then the thread ID: `Gist. *Inbox, Work-Projects · partial thread* <!-- thread:<id> -->`.
  - Labels are the thread's current labels by name (CLAUDE.md rule 4): its primary inbox(es), any other user labels, and Starred. Leave out Unread (shown by the group), Important, Sent and Gmail categories, except in the Promotions/Forums section, where the category (`Promotions` or `Forums`) is listed last. They show what a thread already has and let Claude plan edits (e.g. a thread already in Work-Projects only needs its inbox label removed). It's a snapshot from the last run, so still check live labels before changing anything.
  - Caveats go after the labels, separated by ` · `: `partial thread` when "last sender" comes from only some of the thread's messages.
- **Suggestion line:** the first indented bullet, an unticked checkbox: `- [ ] <Action> — <reason>.` in one short sentence. Ticking it (`[x]`) accepts it as written. Base it only on the search results, and pick one concrete action, for example:
  - `File to <label>`: only for fileable threads (read and addressed); name an existing destination label from `CLAUDE.local.md`. If the thread already carries the destination, say `Remove Inbox` (or `Remove Work`) instead.
  - `Mark read and file to <label>` or `Mark read and archive`: for unread automated mail, promotions and newsletters that need nothing from the user. Archiving removes the inbox label without adding a destination.
  - `Reply` or `Draft a reply with /draft-email`: when someone is waiting on the user. Say what the reply is about if the preview shows it.
  - `Read it`: when the preview doesn't show enough to decide, e.g. "details not in preview".
  - `Leave for now`: when something is pending (a deadline, a reply the user promised, a Starred thread).
  Never suggest filing or archiving an unanswered thread from a Tier 1 sender. Never suggest trash, spam or unsubscribing unless the mail is clearly junk, and say why.
- **Reminder line** (optional): a second checkbox, `- [ ] ⏰ Remind "<title>" on <M/D> in <list>[ (due <M/D>)]` (or `in new list "<name>"`), with the hard deadline in parentheses when there is one, when a reminder is warranted (see "Reminders" above). It's ticked separately from the suggestion, so the user can take one without the other. An item can have two reminder lines when two lists apply (e.g. a call for papers that goes on a deadline list and is also a deadline for one of the user's projects); each gets its own checkbox. Since the reminder holds the to-do, a read thread that otherwise looks addressed can be suggested for filing alongside it; a thread still waiting on the user's reply gets `Leave for now`. A thread that already has an open reminder (step 5) gets no reminder line; say `reminder already set` in the suggestion's reason instead.
- **Response bullet:** the first plain bullet after the checkbox lines (not a checkbox, not starting with `✓` or `✗`), for the user's own directions, empty until they write in it. An empty bullet may appear as `    - ` or `    -` (editors strip trailing spaces); both mean "no directions".
- **Writing about people:** never use he/him or she/her for anyone (senders, co-authors, students) unless the user has said which they use; a name doesn't tell you. Use the name, or rephrase around the person: "you said you'd look into it", not "you told him you'd look into it".
- **Thread ID:** `<!-- thread:<id> -->` at the end of line 2. It's invisible in a Markdown preview and is how items are matched to threads. Never show or ask the user to type it.
- **Done section:** once Claude has carried out an item, the item moves out of its section into `## Done` at the end of the file as a single line: `- ✓ <Section> <number> · **Sender** · Subject — <what was done> (<M/D>) <!-- thread:<id> -->`. The other items keep their numbers until the next run, so numbers the user is looking at stay valid. Omit the section when it's empty.

## Writing and refreshing the file

Each `/summary` run regenerates Needs you, the counts, the `Updated` line, and the section lists from fresh data. If `inbox-summary.md` already exists, read it first and merge, matching items by thread ID:

- **The Done section is cleared.** If a thread listed there is still in a primary inbox or Promotions/Forums, it comes back as a fresh item with new suggestions, unticked boxes and an empty response bullet.
- **Items with directions not yet carried out** (a ticked box or text in the response bullet) keep their suggestion, reminder line, ticks and response exactly as written, even if the thread details changed, since the user's directions may refer to the suggestion. Refresh line 1 and line 2 only. A `✗` bullet carries over too. If such a thread is no longer in any section (e.g. filed in Gmail directly), keep it at the end of its section's Read group with the gist `No longer in this inbox.` so the directions aren't silently lost, and mention it in chat.
- **Items the user is handling** (a ticked `Leave for now`, or a response like "leave it" or "I'll handle it") carry over the same way, so the decision isn't lost and they stay out of Needs you. Exception: if the thread has a newer message than when the user decided, rebuild it fresh and mention it in chat, since the situation changed.
- **Older files** use earlier formats: a `- Suggested: …` bullet followed by the user's bullet (with a reminder joined by ` + `), or a single bullet. Read the user's text in them as directions, and rewrite those items in the current format on the next run, moving the user's text into the response bullet. Items carrying a `✓` bullet and no `✗` count as done.
- **Everything else** is rebuilt from fresh data, with fresh suggestions; threads no longer in a section disappear. A thread whose category changed moves to the right section.
- Threads move between the Unread and Read groups as their read state changes; carried-over directions move with them.
- Renumber every section from 1 on each run. Numbers are labels for the current file, not stable IDs.

## Reporting in chat

Don't repeat the thread lists in chat. Reply with:

1. The file path.
2. The counts table, as a Markdown table with the same rows and columns as the file, bolding the primary-inbox and Promotions/Forums rows, followed by the "N other labels: all read" line.
3. A few short bullets: the Needs you items (briefly), the fileable count, and how many reminders are suggested (section and number, e.g. "reminders suggested: Work 2, Inbox 5").
4. At most one next-step suggestion (e.g. `/suggest-replies urgent`, or "tick the suggestions you agree with in the file").

## Acting on the user's directions

When the user says they've written in the file ("I updated inbox-summary.md", "done, take a look"):

1. **Read the file.** Collect every item outside the Done section that has a ticked box (`[x]` or `[X]`) or text in its response bullet. Ignore every other item: no labels, no read-state changes, no drafts, no reminders.
   - An item with a `✗` bullet was partly done on an earlier pass. Retry only what the `✗` names, and never redo what its `✓` part lists, even though the boxes are still ticked. The `✗` bullet is Claude's note, not the user's directions.
2. **Resolve each item** to concrete actions on its thread ID.
   - A ticked suggestion means: carry it out as written. A ticked reminder line means: create that reminder.
   - Response text is the user's own direction. Read it together with the suggestion ("file to Work-Admin instead", "yes and mark read"). Text that just accepts ("ok", "yes", "do it", "👍") accepts the suggestion line, not the reminder line, unless the text mentions the reminder.
   - The user may ask for a reminder in their own words ("remind me Friday"). Turn it into a title, a due date (resolved against today) and a list as in "Reminders" above. If they gave no date ("remind me about this"), pick one by the rules above and show it in the approval table; never create a reminder without a due date.
   - If a direction is ambiguous, or the text contradicts a tick, ask about that item in chat instead of guessing. If the direction asks for no action now ("leave it", "I'll handle it", a ticked `Leave for now`), do nothing and leave the item where it is.
3. **Drafts** can be created right away (CLAUDE.md rule 2), following `/draft-email`.
4. **Mailbox and reminder changes need approval** (CLAUDE.md rules 1 and 7). A tick or a direction in the file is not approval. Before applying, check each thread still carries the expected inbox label ID, then show one compact table in chat (section and number, sender and subject, exact change, with labels named by name, never by ID; see CLAUDE.md rule 4) and wait for a yes. List each reminder in the same table as `reminder: "<title>" on <M/D> in <list>`, and each new list as its own row, `create list "<name>" and add the project to projects.md`. Apply exactly that, creating new lists before the reminders that go in them.
   - Create new lists as described in "Reminders" in `CLAUDE.md`.
   - Create each reminder with the command and notes format in "Reminders" in `CLAUDE.md`. Always include the `Email` line with the item's thread link: it's how "Existing reminders" (step 5 of the steps above) spots the reminder on later runs.
5. **Move each completed item to Done** as one `✓` line saying what was done and the date (e.g. `filed to Work-Admin, marked read (10/07)`, `draft saved: drafts/<file>.md (10/07)` or `removed Work; reminder "Submit ICWSM review" on 10/13 in Reviews (10/08)`). Don't renumber the remaining items. If any part failed, leave the item in its section and add a bullet below the response bullet, `- ✗ <what failed>; ✓ <what worked> (<M/D>)` (replacing an earlier `✗` bullet if this was a retry), and report it in chat. When a retry succeeds, the item moves to Done with everything that was done across both passes. Touch nothing else in the file.

The user may also give directions in chat by section and number ("Inbox 3: file to Personal", "Promotions/Forums 2: ok"). Treat those the same way, using the numbers in the current file.
