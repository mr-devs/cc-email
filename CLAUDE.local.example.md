# Personal email setup

Copy this file to `CLAUDE.local.md` (gitignored) and fill it in. Claude Code loads it automatically next to `CLAUDE.md`.
Run `list_labels` to get label IDs, or ask Claude to "fill in my labels from Gmail".

## Me

- Name: <your name>
- Gmail address: <you@gmail.com>
- Other addresses forwarded into this Gmail: <you@work.edu>
- Website: <https://example.com>

## Primary inboxes (keep these empty)

| Inbox | Label ID | What lands here |
|---|---|---|
| Inbox | `INBOX` | Mail sent directly to <you@gmail.com> |
| <Work> | `Label_...` | Mail sent to <you@work.edu>, auto-forwarded and labeled by a filter |

## Label tree

Format: `Name` (`label ID`): one-line definition. Mark primary inboxes as **not a filing destination**.
The name is used for searching (`label:<name>`) and the ID for adding or removing labels.

- `Personal` (`Label_...`): <definition>
- `Work` (`Label_...`): **Primary inbox, not a filing destination.** <definition>
- `Work/Projects` (`Label_...`): <definition>

## System views

Sidebar entries that aren't user labels (Gmail categories, Starred, Snoozed, and so on). Don't use these as filing destinations.

## Notes and quirks

- <e.g. "My Gmail filter also labels my own sent mail to my work address, so the Work inbox can contain my sent messages.">

## Open items

- [ ] <things to test or revisit>
