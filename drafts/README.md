# drafts/

A temporary staging area for email drafts written by `/draft-email`.

Each draft exists in two places: as a Gmail draft, and as a Markdown file here that you can open and edit in your own editor. When you've made changes, tell Claude (e.g. "I edited the CITR draft") and it pushes the file's contents to the Gmail draft. The file is the source of truth, so edits made directly in Gmail are overwritten on the next sync.

Files only live here while a draft is in progress. Once the email is sent, Claude deletes its file; the sent message is in Gmail.

Everything in this folder except this README is gitignored, because drafts contain your email content.

## File format

Files are named `<recipient>--<subject>.md`, e.g. `jane-doe-uni-edu--grant-timeline.md`.

```markdown
---
to: [jane.doe@uni.edu]
cc: []
bcc: []
from: you@gmail.com
subject: "Re: Grant timeline"
reply_to_message_id: 18f3a2b4c5d6e7f8
thread_id: 18f3a2b4c5d6e7a1
draft_id: r-1234567890123456789
gmail_url: https://mail.google.com/...
---

Hi Jane,

Thanks for the update...

Best,
Sam
```

- **You can edit:** `to`, `cc`, `bcc`, `subject`, and the body.
- **Informational:** `from`. Mail always goes out from the signed-in Gmail account.
- **Managed by Claude:** `reply_to_message_id` and `thread_id` keep a reply in its thread; leave them alone. `draft_id` and `gmail_url` change on every sync, because Claude replaces the Gmail draft rather than editing it in place.
- **The signature** from `.claude/skills/draft-email/references/signatures.md` is already in the body, below the sign-off. Edit or delete it per email as you like.
- **The body is plain text** and is sent exactly as written. Markdown formatting such as `**bold**` or `# headings` shows up as literal characters.

Nothing is ever sent until you explicitly tell Claude to send it.
