---
name: draft-email
description: Write an email or reply and save it as a Gmail draft, based on the user's gist and preferred tone (casual, professional, formal), with optional length and sign-off. Works for new emails to a recipient and for replies to an existing thread. Use this whenever the user says "draft a reply", "write back to X saying...", "email X about...", "respond to that one", or hands off a thread from /suggest-replies. It saves a draft and never sends.
argument-hint: "<recipient or thread> | <gist> | tone: casual|professional|formal | length: short|medium"
---

# Draft email

Turn the user's intent into a ready-to-send draft that sounds like them. Saving a draft is safe and needs no approval. **Sending is a separate step that needs the user's explicit yes.**

## Inputs

Parse these from `$ARGUMENTS` and the conversation. Ask only for what's truly missing:

- **Target** (required): a new recipient address, or an existing thread. The thread can be a thread ID, a "reply to #2" from `/suggest-replies`, or a description like "the email from Jane about the grant". If it's described, find it with `search_threads`, and if more than one thread matches, confirm which one.
- **Gist** (required): what the email should say. A few words is enough.
- **Tone**: `casual` (a friend), `professional` (default for work contacts), or `formal` (first contact, senior people, institutions). If none is given, infer it from the thread and the relationship, and say which tone you chose.
- **Length**: `short` (default; 2–5 sentences) or `medium`.
- **Sign-off**: use the user's name from `CLAUDE.local.md`, or a casual variant for friends. Skip it if the user prefers none.

## Steps

1. **Context.** For a reply, get the thread with `get_thread` (`messageFormat: PLAIN_TEXT`), or have `email-reader` summarize it if it's long. Note who's on the thread, what was asked, and any dates. For a new email, check `contacts.md` for the relationship.
2. **Write.**
   - Match the requested tone and keep it as short as the content allows.
   - Answer every direct question in the thread.
   - Use concrete dates; convert "this Saturday" into "Saturday (10/10)" relative to today.
   - Don't invent facts, commitments or availability the user didn't give. Put `[brackets]` where something is needed and point them out.
3. **Show** the subject and body in chat.
4. **Save** with `mcp__claude_ai_Gmail__create_draft`:
   - For replies, pass `replyToMessageId` set to the **last message** in the thread. Keep the existing subject; the connector handles the `Re:`.
   - Use plain text in `body` with no Markdown.
5. **Report** the draft link (`viewUrl`) and ask: "Want any changes, or should I send it?"

## Revising and sending

- To revise, use `update_draft` on the same draft rather than creating a duplicate.
- Send only if the user explicitly says so ("send it", "go ahead"), using `send_message` with `draftId`.
- After sending a reply from a primary inbox, the thread is now addressed. Offer to file it (see `/file-away`), but don't file it without a yes.
