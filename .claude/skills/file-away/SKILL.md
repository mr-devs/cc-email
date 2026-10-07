---
name: file-away
description: Propose destination labels for threads in the user's primary inboxes that are read and already addressed, each with a short rationale, and apply the filing only after explicit approval. Filing adds the destination label and removes the primary-inbox label. Use this whenever the user says "file these away", "clean up my inbox", "move it to X", "archive this to X", "what can I file?", or wants to get the inbox closer to zero.
argument-hint: "[optional: inbox name, thread, or 'move <thread> to <label>']"
---

# File away

Get the primary inboxes closer to empty by filing threads that are done, without ever filing something the user still needs to see. Gmail has labels, not folders. **Filing** a thread means adding its destination label and removing its primary-inbox label(s) (`INBOX` and/or the work label). Label names, IDs and definitions are in `CLAUDE.local.md`. Search by name; label and unlabel by ID (CLAUDE.md rule 4).

## Two entry points

- **Direct request** ("move the Zoom email to Admin"): find the thread, confirm the match, and go to *Approve*. Here the user is choosing a specific thread, so the fileable check is advisory. Still mention it if the thread is unread.
- **Sweep** (no specific thread): run the full process below.

## Sweep

1. **Gather.** Ask the `email-reader` agent to list every thread in each primary inbox, with:
   - thread ID
   - sender
   - subject
   - date
   - `label_ids`
   - read or unread
   - who sent the last message
   - whether a reply seems expected
   - a one-line gist
2. **Fileable check.** A thread is fileable only if **both** of these hold:
   - It's **read**: no `UNREAD` label on any message.
   - It's **addressed**: the user sent the last message, or the thread clearly needs no reply (notification, receipt, newsletter, FYI, automated alert, or a message where the user was only cc'd).
   - **Never** propose a thread from a Tier 1 sender in `contacts.md` unless the user has replied.
   - List non-fileable threads separately with the reason (e.g. "unread", "question from Jane awaiting your reply").
3. **Choose a destination.** Use the label definitions in `CLAUDE.local.md`. Pick the single best label and give a short rationale tied to the definition. If nothing fits, say so and suggest either the closest label or a new one; don't create a new label without approval.

## Output format

```
### Ready to file (N)
| # | From | Subject | → Label | Why |
|---|---|---|---|---|
| 1 | Zoom | Your invoice | Work/Receipts | Receipt for a work purchase |

### Not filing yet (M)
- **Sender**: Subject — unread
- ★ **Jane**: Grant draft — asks for your feedback; not answered
```

Then ask for approval: "File all N? Or tell me which numbers to change or skip."

## Approve and apply

Apply only what the user approved, including any edits they made. For each approved thread:

1. Call `mcp__claude_ai_Gmail__label_thread` with the destination label ID.
2. Call `mcp__claude_ai_Gmail__unlabel_thread` with the primary-inbox label IDs the thread actually has (`INBOX`, the work label, or both).

Add the destination label first, so a failure partway through never leaves a thread with no labels.
Don't mark threads read or change anything beyond these labels.

Finish with a short report: "Filed 5 threads (3 to Work/Admin, 2 to Personal/Finances). 1 failed: <reason>." If you came across a label that isn't in `CLAUDE.local.md`, update that file and tell the user.
