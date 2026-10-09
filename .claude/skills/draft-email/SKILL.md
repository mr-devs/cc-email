---
name: draft-email
description: Write an email or reply and save it both as a Gmail draft and as a local Markdown file in drafts/ that the user can edit, based on the user's gist and preferred tone (casual, professional, formal), with optional length and sign-off. Works for new emails to a recipient and for replies to an existing thread. When the user says they edited a draft file, sync the edits to the Gmail draft. Use this whenever the user says "draft a reply", "write back to X saying...", "email X about...", "respond to that one", "I edited the draft", "update the draft from the file", or hands off a thread from /suggest-replies. It saves drafts and never sends without an explicit yes.
argument-hint: "<recipient or thread> | <gist> | tone: casual|professional|formal | length: short|medium"
---

# Draft email

Turn the user's intent into a ready-to-send draft that sounds like them. Every draft lives in two places:

- a **Gmail draft**, ready to send, and
- a **local file** in `drafts/`, which the user edits in their own editor.

`drafts/` is only a temporary staging area. A file exists while its draft is in progress and is deleted once the email is sent. Never touch `drafts/README.md`.

The local file is the source of truth. When the user says they've edited it, push the file's contents to Gmail.

Saving or syncing a draft is safe and needs no approval. **Sending is a separate step that needs the user's explicit yes.**

## Inputs

Parse these from `$ARGUMENTS` and the conversation. Ask only for what's truly missing:

- **Target** (required): a new recipient address, or an existing thread. The thread can be a thread ID, a "reply to #2" from `/suggest-replies`, an item tag from `inbox-summary.md` (e.g. `W3`), or a description like "the email from Jane about the grant". If it's described, find it with `search_threads`, and if more than one thread matches, confirm which one.
- **Gist** (required): what the email should say. A few words is enough.
- **Tone**: `casual` (a friend), `professional` (default for work contacts), or `formal` (first contact, senior people, institutions). If none is given, infer it from the thread and the relationship, and say which tone you chose.
- **Length**: `short` (default; 2–5 sentences) or `medium`.
- **Sign-off**: use the user's name from `CLAUDE.local.md`, or a casual variant for friends. Skip it if the user prefers none.
- **Signature**: Gmail doesn't add the user's signature to drafts made through the connector, so add it yourself from `references/signatures.md` (in this skill's folder). That file says which signature goes on a new email and which on a reply. Put it below the sign-off, separated by a blank line, exactly as written. Use a different signature, or none, if the user asks. If it's missing, skip the signature and offer to set it up from `references/signatures.example.md`.

## The draft file

Save each draft to `drafts/<recipient>--<subject>.md`:

- `<recipient>` is the first `to` address, lowercased, with every character that isn't a letter or digit replaced by `-` (`jane.doe@uni.edu` → `jane-doe-uni-edu`).
- `<subject>` is the subject slugged the same way and cut to about 60 characters, without a leading `re-`.
- If that name is already taken by a different draft, add `-2`, `-3`, ….

The file starts with YAML front matter and has the email body below it:

```markdown
---
to: [jane.doe@uni.edu]
cc: [sam@uni.edu]
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

- `to`, `cc`, `bcc` and `subject` are the fields the user may edit, along with the body.
- `from` is informational. The connector always sends from the signed-in account.
- `reply_to_message_id` and `thread_id` are empty for a new email. For a reply, they keep the draft in the thread.
- `draft_id` and `gmail_url` are managed by Claude. They change every time the draft is synced (see below).
- The body is **plain text**. It's sent as written, so Markdown formatting (`**bold**`, `# headings`, bullets with `*`) shows up as literal characters. Plain line breaks and `-` lists are fine.

## Steps: new draft

1. **Context.** For a reply, get the thread with `get_thread` (`messageFormat: PLAIN_TEXT`), or have `email-reader` summarize it if it's long. Note who's on the thread, what was asked, and any dates. For a new email, check `contacts.md` for the relationship.
2. **Write.**
   - Match the requested tone and keep it as short as the content allows.
   - Answer every direct question in the thread.
   - End with the sign-off, then the signature from `references/signatures.md` (reply or new-email version).
   - Use concrete dates; convert "this Saturday" into "Saturday (10/10)" relative to today.
   - Don't invent facts, commitments or availability the user didn't give. Put `[brackets]` where something is needed and point them out.
3. **Save the file** in `drafts/` as described above, leaving `draft_id` and `gmail_url` empty for now.
4. **Save to Gmail** with `mcp__claude_ai_Gmail__create_draft` (see "Creating the Gmail draft" below), then write the returned `id` and `viewUrl` into the file.
5. **Report** the file path, the Gmail draft link, and the subject and body in chat. Point out any `[brackets]`. Ask: "Edit the file and tell me when you're done, or want me to send it?"

## Steps: syncing the user's edits

When the user says they've edited a draft file (or asks to update a draft):

1. **Read the file** and parse the front matter and body. If the front matter doesn't parse, or `to` is empty, say what's wrong and stop.
2. **Check the Gmail draft still exists** with `get_draft` on `draft_id`, using `messageFormat: MINIMAL`. Never fetch a draft with `PLAIN_TEXT` or `FULL_CONTENT`: a reply draft carries the whole quoted thread and floods the conversation. If the draft is gone (sent or deleted in Gmail), tell the user and ask whether to recreate it from the file or delete the file.
3. **Recreate the draft** instead of editing it in place:
   1. `create_draft` from the file (see "Creating the Gmail draft" below).
   2. Only after that succeeds, `delete_draft` on the old `draft_id`.
   3. Write the new `draft_id` and `gmail_url` back into the file. Change nothing else in the file.

   Why not `update_draft`: a reply draft's quoted history and threading come from `replyToMessageId`, and `update_draft` can't set it. Updating the body with plain text clears the HTML part, and the quoted thread goes with it. Recreating rebuilds both. Creating before deleting means a failure never loses the draft.
4. **Report** the new Gmail link and a one-line summary of what changed (e.g. "body updated, added cc"). The file wins over any edits made directly in Gmail since the last sync, so mention that if the user seems to have edited in Gmail too.

Deleting the superseded copy during a sync is part of updating the draft (CLAUDE.md rule 2). Never delete any other draft without a yes.

## Creating the Gmail draft

Every `create_draft` call, for a new draft or a sync, is built from the file:

- `to`, `cc`, `bcc` and `subject` from the front matter, plus `replyToMessageId` from `reply_to_message_id` if set. For replies, that's the **last message** in the thread, and the draft replies to everyone on the thread unless the user says otherwise.
- `body`: the file's body as plain text, exactly as written.
- `htmlBody`: the output of `python3 -I .claude/skills/draft-email/to_html.py <file>`. **Always pass it.** If only `body` is given, the connector converts it to HTML itself, and it turns a bare domain like `example.com` into a visible `google.com/url?q=…` redirect. The script makes explicit links and styles the signature (everything from the `--` line down) like a Gmail signature.

## Sending

- Send only if the user explicitly says so ("send it", "go ahead").
- If the file has changed since the last sync, sync first so what's sent matches the file.
- Send with `send_message` using the `draft_id` from the file.
- After a successful send, delete the local file. Don't keep or archive it; the sent email is in Gmail.
- After sending a reply from a primary inbox, the thread is now addressed. Offer to file it (see `/file-away`), but don't file it without a yes.
