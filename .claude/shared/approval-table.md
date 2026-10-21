# Approval table

The format every skill uses to propose mailbox and reminder changes before applying them (CLAUDE.md rules 1 and 7). Read this file before presenting the table, and use the format exactly. The user approves the table as a whole or by tag, so it has to show every change, grouped so identical actions read as one block.

## Format

```markdown
| Change | Tag | Sender | Subject | Reminder |
|---|---|---|---|---|
| **Move to Trash** | P1 | Clothing Store | Fall sale: 40% off everything | |
| | P2 | Movie Theater | Tickets on sale now | |
| **Mark read, file to Work-Conferences** | I2 | ACL Portal | [CFP] Workshop on Computational Social… | |
| | P6 | Lab mailing list | Fall speaker series *(my pick)* | |
| **File to Work-Reviews** | W4 | ★ Editor | Review assignment | "Submit ICWSM review" on 10/13 in Reviews |
| **No mailbox change** | I9 | Colleague | Re: Your talk | "Send Colleague the preprint" on 11/4 in new list "Health Audit" |

Drafts saved (not part of this approval): I9, I10.
Not changing: I8, W1, W3.
```

## Rows

- **One row per thread.** A thread appears in exactly one row.
- **Grouped by change.** The Change cell is filled in, in bold, only on the first row of each group; the rows below it leave it blank. Within a group, keep the order of the tags.
- **Change names** come from this list, so identical actions always group together:
  - `Move to Trash`
  - `Archive`: remove the primary-inbox label only.
  - `File to <label>`: add the destination label and remove the primary-inbox label(s).
  - `Remove <inbox>` (e.g. `Remove Work`): the thread already carries its destination label.
  - `No mailbox change`: for a thread whose only change is a reminder.
  - Prefix `Mark read, ` when the change also removes `UNREAD`, e.g. `Mark read, archive`. It's a separate group from the same change without it.
  - Any other change (spam, a label added without filing, …) gets a short name in the same style.
- **Group order, hardest to undo first:** Move to Trash, Archive, File to (alphabetical by label), Remove inbox, any other change, No mailbox change. A `Mark read, ` group goes right after its plain counterpart.

## Columns

- **Tag:** the item's tag in `inbox-summary.md` (`I2`, `W5`, `P1`). Skills without tags number the threads `1`, `2`, `3` and use the number.
- **Sender:** display name, with ★ for Tier 1 and ☆ for Tier 2 (`contacts.md`). The user's own messages show as `You`.
- **Subject:** plain text, not a link. Drop a leading list prefix already shown by the sender (`[ACL Portal]`), and cut to about 40 characters, ending with `…` when cut.
- **Reminder:** filled in only on the row of the thread it belongs to: `"<title>" on <M/D> in <list>`, or `in new list "<name>"` when the list doesn't exist yet (approving it also means creating the list and adding the project to `projects.md`). A thread with two reminders puts both in the cell, separated by `<br>`. Leave out the whole column when no row has a reminder.
- **(my pick):** add *(my pick)* to the Subject cell when Claude chose the label or list because the user's direction didn't name one ("file away", "remind me"). Not needed in a sweep where Claude proposes every destination.
- Name labels by their text name, never by ID (CLAUDE.md rule 4). Never show thread IDs.

## Under the table

- `Drafts saved (not part of this approval): <tags>`, when drafts were created or updated (CLAUDE.md rule 2).
- `Not changing: <tags>`, for items the user said to leave or didn't mark. A skill may give its own list here instead, with reasons (e.g. `/file-away`'s "Not filing yet").
- Then ask for a yes, or for the tags to change or skip.

Apply exactly the approved rows, nothing else.
