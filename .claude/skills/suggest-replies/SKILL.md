---
name: suggest-replies
description: Pick 1–3 emails from the user's primary inboxes that are most worth replying to or handling right now, each with a short reason. Accepts a mode, 'urgent' (deadlines, VIPs, people waiting) or 'easy' (quick wins that can be answered or filed in a minute). Use this whenever the user asks "what should I respond to", "what needs my attention", "anything urgent?", "give me some easy ones", "what can I knock out quickly", or wants help choosing where to start on their email.
argument-hint: "[urgent|easy]"
---

# Suggest replies

Help the user decide what to work on next. A short, well-reasoned list beats a long one, so return **at most 3** threads. This skill is read-only.

## Mode

Take the mode from `$ARGUMENTS`:

- **urgent**: rank by how costly a delay would be.
  - Explicit deadlines or dates in the next few days
  - Tier 1 senders from `contacts.md`
  - Someone waiting on a direct question
  - Time-sensitive opportunities (reviews, talks, jobs)
- **easy**: rank by how little effort it takes.
  - Yes/no answers
  - Scheduling confirmations
  - Short acknowledgements
  - Threads that only need filing
- **no mode**: balance the two. Prefer one urgent item and one or two quick wins.

## Steps

1. Ask the `email-reader` agent to read the primary inboxes listed in `CLAUDE.local.md`. For each thread, it should report:
   - thread ID
   - sender
   - subject
   - date
   - read or unread
   - who sent the last message
   - any explicit ask or deadline
   - a one-line gist
2. Drop threads where the user sent the last message, unless they're waiting on something overdue. Drop pure notifications too, unless the mode is `easy` (those are candidates for filing).
3. Weight senders with `contacts.md`: Tier 1 > Tier 2 > unlisted > Tier 3.
4. Choose up to 3 threads and explain each in one sentence. The reason is what makes the list useful, so be specific, e.g. "Jane asked for feedback on the draft by Friday", not "seems important".

## Output format

```
1. ★ **Sender**: Subject (date)
   Why: <one specific sentence>
   Suggested action: reply (gist: "...") | file to <label> | decline politely | ...
2. ...
```

Then offer to start: "Want me to draft a reply to #1?" (hands off to `/draft-email`), or "Want me to file #3?" (needs approval; see `/file-away`). Never send or change anything from this skill.
