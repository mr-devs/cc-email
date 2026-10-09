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
4. **Fileable estimate.** Count threads that are read and addressed (the user sent the last message, or it's clearly FYI or automated). This goes in the chat report, not the file.
5. **Existing reminders.** Run `remindctl status` (see "Reminders" in `CLAUDE.md`); if it fails, skip reminder suggestions and say so once in chat. Otherwise run `remindctl search mail.google.com --json` once: reminders Claude created from email carry the thread's Gmail link, so any thread ID that appears in a result's notes (or, for older reminders, its URL) already has an open reminder. Don't suggest a second one for that thread. Also run `remindctl list` for the current list names and read `projects.md`. If a list exists in Reminders but not in `projects.md`, or the other way round, mention it once in chat.
6. **Suggestions.** Give every item one suggested action, based only on what's in the search results, plus a reminder where one is warranted (see "Reminders" above and "Action list" below).

If `$ARGUMENTS` names a focus (e.g. "work only"), limit steps 2–6 to it.

## The file: `inbox-summary.md`

The file always shows exactly what is in the primary inboxes (and Promotions/Forums) as of its `Updated` line: every thread this run's searches returned, and nothing else. Each email is one self-contained block, and every piece of it has a label, so the user can see at a glance what's the subject, the summary, the labels, Claude's suggestion and any reminder. The user reads it in a Markdown preview and edits the source; VS Code's preview is read-only, so ticks are typed (`[ ]` → `[x]`), not clicked.

```markdown
# Inbox summary

Updated Wed 10/7, 4:50 pm. For each email, change `[ ]` to `[x]` to accept a suggestion or reminder, or write after **Notes:**. Then tell Claude.

## Needs you

- **W2** · Editor: review due 10/15
- **I1** · ★ Sender: Tier 1 sender; the ask isn't in the preview

## Counts

| Label | Unread | Read |
|---|--:|--:|
| Inbox | 9 | 20 |
| Work | 3 | 15 |
| Promotions/Forums | 3 | 8 |
| Work-Google-Scholar | 250 | 650 |

N other labels: all read.

## Inbox (N threads, M unread)

### Unread

#### I1 · [Subject](https://mail.google.com/mail/u/<Gmail address>/#all/18f3a2b4c5d6e701)

**From:** ★ Sender · 10/7\
**Summary:** One-line gist; details not in preview.\
**Labels:** `Inbox`

- [ ] **Suggestion:** Read it — Tier 1 sender; the ask isn't in the preview.
- **Notes:** 

### Read

#### I2 · [Your statement is ready](https://mail.google.com/mail/u/<Gmail address>/#all/18f3a2b4c5d6e702)

**From:** Bank · 10/6\
**Summary:** Monthly statement is ready.\
**Labels:** `Inbox`

- [ ] **Suggestion:** File to Personal-Finances — statement notice, nothing to do.
- **Notes:** file to Work-Admin instead

## Work (N threads, M unread)

### Read

#### W1 · [Subject](https://mail.google.com/mail/u/<Gmail address>/#all/18f3a2b4c5d6e703)

**From:** Sender +3 · 10/5\
**Summary:** One-line gist. *(partial thread)*\
**Labels:** `Work` `Work-Projects` `Starred`

- [x] **Suggestion:** Remove Work (already in Work-Projects) — you replied last and nothing is pending.
- **Notes:** 

#### W2 · [Review assignment](https://mail.google.com/mail/u/<Gmail address>/#all/18f3a2b4c5d6e705)

**From:** Editor · 10/4\
**Summary:** You accepted; review due 10/15.\
**Labels:** `Work` `Work-Reviews`

- [ ] **Suggestion:** Remove Work (already in Work-Reviews) — accepted already; the deadline is the only thing left.
- [ ] **Reminder:** "Submit ICWSM review" on 10/13 in Reviews (due 10/15)
- **Notes:** 

## Promotions/Forums (N threads, M unread: P promotions, F forums)

### Unread

#### P1 · [Subject](https://mail.google.com/mail/u/<Gmail address>/#all/18f3a2b4c5d6e704)

**From:** Sender · 10/7\
**Summary:** One-line gist.\
**Labels:** `Inbox` `Promotions`

- [ ] **Suggestion:** Mark read and archive — marketing email, nothing to act on.
- **Notes:** 

## Done

- ✓ **I3** · Sender · [Subject](https://mail.google.com/mail/u/<Gmail address>/#all/18f3a2b4c5d6e706) — filed to Work-Admin, marked read (10/7)
```

- **Updated line:** day, date and time, then the one-sentence how-to shown above.
- **Needs you:** 3–5 lines for what needs the user personally: someone waiting on a reply, a deadline within ~3 weeks, a Tier 1 thread to read. Each line is `- **<tag>** · <sender>: <what's needed, with the date if any>`. Soonest deadline first, then Tier 1, then whoever has waited longest. Leave out items the user already said they'll handle (a ticked `Leave for now`, or "leave it" / "I'll handle it" in Notes). Omit the section when nothing qualifies.
- **Counts:** columns Unread and Read, numbers right-aligned with thousands separators. Rows: Inbox, the other primary inboxes and Promotions/Forums first, then other labels with unread threads, by unread count, descending. Drop any row that is 0 and 0, and collapse fully read labels into the one `N other labels: all read.` line.
- **Sections:** one `##` section per primary inbox, in the order of `CLAUDE.local.md`, then Promotions/Forums last, each headed with its thread and unread counts. List **every** thread in it. Omit the Promotions/Forums section if it's empty.
- **Unread and Read groups:** `### Unread` then `### Read` within each section; omit an empty group. Within each group, priority senders first, then newest first.
- **Tags:** every item has a short tag: the section's letter plus a number, `I` for Inbox, `W` for Work, `P` for Promotions/Forums (for other primary inboxes, the first letter of the label, or two letters if that's taken). Number once per section, continuing across both groups (Unread I1–I3, Read I4–I9). The user refers to items by tag ("W3: file to Personal").
- **Item heading:** `#### <tag> · [<subject>](<Gmail link>)`. The link is `https://mail.google.com/mail/u/<Gmail address from CLAUDE.local.md>/#all/<thread id>`; it opens the thread, and it's how items are matched to threads. Escape `[` and `]` in subjects. Headings also put every email in VS Code's Outline view.
- **Fields:** three lines below the heading, each a bold label, joined by a trailing `\` (a Markdown line break) except on the last:
  - `**From:** [★ |☆ ]<sender>[ +N] · M/D`. ★ for Tier 1, ☆ for Tier 2 (step 3). `+N` counts the thread's other visible participants besides the sender and the user; leave it out when there are none. The user's own messages show as `You`.
  - `**Summary:** <gist>`: one short sentence (aim for under ~100 characters), from the subject and preview only. Append `*(partial thread)*` when "last sender" comes from only some of the thread's messages.
  - ``**Labels:** `<label>` `<label>` ``: the thread's labels from this run's search results, each in code formatting, by name (CLAUDE.md rule 4): its primary inbox(es), any other user labels, and Starred. Leave out Unread (shown by the group), Important, Sent and Gmail categories, except in Promotions/Forums, where `Promotions` or `Forums` comes last. Never copy labels from an earlier file. They're current as of the `Updated` line, so still check live labels before changing anything.
- **Action list:** a bullet list after a blank line, in this order:
  - `- [ ] **Suggestion:** <Action> — <reason>.` One concrete action in one short sentence, based only on the search results, for example:
    - `File to <label>`: only for fileable threads (read and addressed); name an existing destination label from `CLAUDE.local.md`. If the thread already carries the destination, say `Remove Inbox` (or `Remove Work`) instead.
    - `Mark read and file to <label>` or `Mark read and archive`: for unread automated mail, promotions and newsletters that need nothing from the user. Archiving removes the inbox label without adding a destination.
    - `Reply` or `Draft a reply with /draft-email`: when someone is waiting on the user. Say what the reply is about if the preview shows it.
    - `Read it`: when the preview doesn't show enough to decide, e.g. "details not in preview".
    - `Leave for now`: when something is pending (a deadline, a reply the user promised, a Starred thread).
    Never suggest filing or archiving an unanswered thread from a Tier 1 sender. Never suggest trash, spam or unsubscribing unless the mail is clearly junk, and say why.
  - `- [ ] **Reminder:** "<title>" on <M/D> in <list>[ (due <M/D>)]` (or `in new list "<name>"`), optional, with the hard deadline in parentheses when there is one, when a reminder is warranted (see "Reminders" above). It's ticked separately from the suggestion, so the user can take one without the other. An item can have two reminder lines when two lists apply (e.g. a call for papers that goes on a deadline list and is also a deadline for one of the user's projects). Since the reminder holds the to-do, a read thread that otherwise looks addressed can be suggested for filing alongside it; a thread still waiting on the user's reply gets `Leave for now`. A thread that already has an open reminder (step 5) gets no reminder line; say `reminder already set` in the suggestion's reason instead.
  - `- **Notes:** ` for the user's own directions, empty until they write after it. Trailing spaces may be stripped (`- **Notes:**`); both mean "no directions".
  - `- ✗ <what failed>; ✓ <what worked> (<M/D>)`: only after a partly failed pass (see "Acting on the user's directions").
- **Writing about people:** never use he/him or she/her for anyone (senders, co-authors, students) unless the user has said which they use; a name doesn't tell you. Use the name, or rephrase around the person: "you said you'd look into it", not "you told him you'd look into it".
- **Never show a thread ID as text.** It appears only inside the Gmail link's URL. Never ask the user to type one.
- **No emoji** beyond ★, ☆, ✓ and ✗.
- **Done section:** once Claude has carried out an item, its whole block moves out of its section into `## Done` at the end of the file as one line: `- ✓ **<tag>** · <sender> · [<subject>](<Gmail link>) — <what was done> (<M/D>)`. The other items keep their tags until the next run, so tags the user is looking at stay valid. Omit the section when it's empty.

## Writing and refreshing the file

Each `/summary` run regenerates the `Updated` line, Needs you, the counts and the sections from fresh data. If `inbox-summary.md` already exists, read it first and merge, matching items by the thread ID in their Gmail link:

- **Only threads in this run's search results appear.** A thread that has left every primary inbox and Promotions/Forums is dropped from the file, even if it carried directions. If it had directions that weren't carried out (a tick, or text in Notes that asks for something), list it in chat, e.g. "dropped W5 (review request): no longer in Work; your note was 'Leave it. I will handle.'", so nothing is lost silently.
- **The Done section is cleared.** If a thread listed there is still in a section, it comes back as a fresh item with new suggestions, unticked boxes and empty Notes.
- **Items with directions not yet carried out** (a ticked box or text in Notes) keep their Suggestion, Reminder, ticks and Notes exactly as written, even if the thread details changed, since the user's directions may refer to the suggestion. Refresh the heading and the From, Summary and Labels lines from this run's data. A `✗` line carries over too.
- **Items the user is handling** (a ticked `Leave for now`, or Notes like "leave it" or "I'll handle it") carry over the same way, so the decision isn't lost and they stay out of Needs you. Exception: if the thread has a newer message than when the user decided, rebuild it fresh and mention it in chat, since the situation changed.
- **Older files** use earlier formats: numbered items (`1. **Sender** · Subject`) with the thread ID in a `<!-- thread:<id> -->` comment, labels in italics, and a checkbox or `- Suggested: …` bullet followed by a plain bullet for the user (with a reminder joined by ` + `). Read the user's text in them as their Notes and the ticks as ticks, and rewrite those items in the current format, moving the user's text after **Notes:**. Items carrying a `✓` bullet and no `✗` count as done.
- **Everything else** is rebuilt from fresh data, with fresh suggestions. A thread whose category changed moves to the right section.
- Threads move between the Unread and Read groups as their read state changes; carried-over directions move with them.
- Re-tag every section from 1 on each run. Tags are labels for the current file, not stable IDs.

## Reporting in chat

Don't repeat the thread lists in chat. Reply with:

1. The file path.
2. The counts table, as a Markdown table with the same rows and columns as the file, bolding the primary-inbox and Promotions/Forums rows, followed by the "N other labels: all read." line.
3. A few short bullets: the Needs you items (briefly), the fileable count (step 4), how many reminders are suggested (by tag, e.g. "reminders suggested: W2, I5"), and any threads dropped with unfinished directions.
4. At most one next-step suggestion (e.g. `/suggest-replies urgent`, or "tick the suggestions you agree with in the file").

## Acting on the user's directions

When the user says they've written in the file ("I updated inbox-summary.md", "done, take a look"):

1. **Read the file.** Collect every item outside the Done section that has a ticked box (`[x]` or `[X]`) or text after **Notes:**. Ignore every other item: no labels, no read-state changes, no drafts, no reminders.
   - An item with a `✗` line was partly done on an earlier pass. Retry only what the `✗` names, and never redo what its `✓` part lists, even though the boxes are still ticked. The `✗` line is Claude's note, not the user's directions.
2. **Resolve each item** to concrete actions on its thread ID (from the heading's Gmail link).
   - A ticked Suggestion means: carry it out as written. A ticked Reminder means: create that reminder.
   - Notes are the user's own direction. Read them together with the suggestion ("file to Work-Admin instead", "yes and mark read"). Notes that just accept ("ok", "yes", "do it", "👍") accept the Suggestion, not the Reminder, unless they mention the reminder.
   - The user may ask for a reminder in their own words ("remind me Friday"). Turn it into a title, a due date (resolved against today) and a list as in "Reminders" above. If they gave no date ("remind me about this"), pick one by the rules above and show it in the approval table; never create a reminder without a due date.
   - If a direction is ambiguous, or the Notes contradict a tick, ask about that item in chat instead of guessing. If the direction asks for no action now ("leave it", "I'll handle it", a ticked `Leave for now`), do nothing and leave the item where it is.
3. **Drafts** can be created right away (CLAUDE.md rule 2), following `/draft-email`.
4. **Mailbox and reminder changes need approval** (CLAUDE.md rules 1 and 7). A tick or a direction in the file is not approval. Before applying, check each thread still carries the expected inbox label ID, then show one compact table in chat (tag, sender and subject, exact change, with labels named by name, never by ID; see CLAUDE.md rule 4) and wait for a yes. List each reminder in the same table as `reminder: "<title>" on <M/D> in <list>`, and each new list as its own row, `create list "<name>" and add the project to projects.md`. Apply exactly that, creating new lists before the reminders that go in them.
   - Create new lists as described in "Reminders" in `CLAUDE.md`.
   - Create each reminder with the command and notes format in "Reminders" in `CLAUDE.md`. Always include the `Email` line with the item's thread link: it's how "Existing reminders" (step 5 of the steps above) spots the reminder on later runs.
5. **Move each completed item to Done** as one `✓` line saying what was done and the date (e.g. `filed to Work-Admin, marked read (10/7)`, `draft saved: drafts/<file>.md (10/7)` or `removed Work; reminder "Submit ICWSM review" on 10/13 in Reviews (10/8)`). Don't re-tag the remaining items. If any part failed, leave the item in its section and add a line after **Notes:**, `- ✗ <what failed>; ✓ <what worked> (<M/D>)` (replacing an earlier `✗` line if this was a retry), and report it in chat. When a retry succeeds, the item moves to Done with everything that was done across both passes. Touch nothing else in the file.

The user may also give directions in chat by tag ("I3: file to Personal", "P2: ok"). Treat those the same way, using the tags in the current file.
