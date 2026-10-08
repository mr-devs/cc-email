# Projects

Copy this file to `projects.md` (gitignored) and fill it in.
Claude uses it to put reminders in the right Apple Reminders list (via `remindctl`) and to recognize which project an email belongs to.
Each project gets its own reminder list. When an email belongs to a project that has no list yet, or to a project not listed here, Claude's reminder suggestion includes creating the list and adding the project to this file.

Columns:

- **Project**: a short name.
- **Reminder list**: the exact Apple Reminders list name.
- **Status**: `early`, `ongoing`, `stale` or `complete`. Every status still matches; `stale` and `complete` are a hint that the email may be about something new.
- **About**: one line on what the project is, to help match emails that don't name it.
- **People**: collaborators whose email is usually about this project (names or addresses).
- **Keywords**: words in subjects or previews that point to this project (paper titles, venues, repo names, grant names).

## Projects

| Project | Reminder list | Status | About | People | Keywords |
|---|---|---|---|---|---|
| Example study | `Example Study` | ongoing | Survey experiment on X | Sam Roe, @partner.org | example study, pilot survey |

## Other reminder lists

Lists that aren't projects, used when an email doesn't belong to a project; the default comes last. If a list has special rules (e.g. it feeds something public, or collects writing ideas with a high bar), give it its own section below and Claude will follow it.

| List | Use for |
|---|---|
| `Reviews` | Peer-review deadlines |
| `Reminders` | **Default.** Anything that fits no project or topic list |
