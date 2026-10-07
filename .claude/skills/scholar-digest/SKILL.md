---
name: scholar-digest
description: Go through unread Google Scholar alert emails and pull out the papers most relevant to the user's research, with title, authors, a truncated blurb, link, and why each one matters. Then learn from the user's feedback by updating research-interests.md, and offer to mark the batch read. Use this whenever the user mentions Google Scholar alerts, their Scholar backlog, new papers, "anything good in my scholar emails", "what should I read", or wants to triage research alerts, even if they don't name the skill.
argument-hint: "[N threads, default 25 | 'last 7d' | 'after:YYYY/MM/DD']"
---

# Scholar digest

Google Scholar alerts pile up by the hundreds. Separate the signal from the noise, and get better at it each time by recording what the user does and doesn't care about.

## Setup

- Read `research-interests.md` in full, especially **Core topics**, **Signals** and both **Learned** sections. The Learned entries matter most because they record the user's actual judgments. If the file is missing, copy `research-interests.example.md` and ask the user for a short research bio first.
- Find the Scholar label's name in `CLAUDE.local.md`. If there isn't one, search `from:scholaralerts-noreply@google.com`.

## Batch

Work out the batch from `$ARGUMENTS`:

- a number N: the newest N unread threads (default **25**)
- a window such as `last 7d`: add `newer_than:7d`
- an explicit `after:YYYY/MM/DD`

The base query is `label:<scholar-label-name> is:unread`. Search by name, since the operator ignores IDs (see CLAUDE.md rule 4). Record the exact thread IDs in the batch; they're needed for marking read at the end.

## Steps

1. **Extract.** Ask the `email-reader` agent to open each thread (`get_thread`, `messageFormat: PLAIN_TEXT`) and list every paper in it with:
   - title
   - authors (truncate after 3 with "et al.")
   - venue or source if shown
   - the snippet text (first ~200 chars)
   - the paper link
   - the alert it came from: the subject line, e.g. "new citations to X", "new articles in Y"
   Ask it to return the full list of thread IDs it processed. One alert usually contains several papers.
2. **Deduplicate** by normalized title. The same paper often appears in several alerts; keep one entry and note the alerts it appeared in, since that's a mild relevance signal.
3. **Score** each paper against `research-interests.md`:
   - High: matches a Strong signal or something in Learned: interesting.
   - Medium: touches a core topic indirectly.
   - Low: matches Weaker signals or Learned: not interesting, or isn't related.
   Base scores on meaning, not keyword overlap. A paper on "LLM sycophancy in health advice" is relevant to someone who studies AI and health information even if no keywords match.
4. **Present** the High papers and the best Medium ones, usually 3–10, ranked:

```
### Relevant papers (K of P papers from T alerts)

1. **Title**
   Authors · Venue
   > Truncated blurb…
   Why: <one sentence tying it to a specific interest>
   Link: <url>
```

   Then give one line saying how many were judged Low and the main reasons (e.g. "18 low: mostly ML methods, materials science citing an old paper").

## Learn from feedback

Feedback is how `research-interests.md` improves, so always ask. Use `AskUserQuestion`:

- **Question 1** (multiSelect): "Which of these are actually interesting to you?" List the presented papers as options, with short titles as labels and the Why line as each description. Up to 4 options per question; split across questions if there are more.
- **Question 2:** ask why for one or two contested items, e.g. a High-scored paper the user didn't select ("not my area", "too technical", "already read", "wrong domain"), or invite a free-text note through Other.

Then edit `research-interests.md`:

- Add `- YYYY-MM-DD | Title | reason` lines under **Learned: interesting** and **Learned: not interesting**, using today's date. Generalize the reason so it helps with future papers ("survey-only papers without new data" rather than just "boring").
- If a pattern repeats (the same kind of reason 3 or more times), suggest adding it to **Signals**, and make that edit only if the user agrees.

Briefly report what changed in the file.

## Mark the batch read

Ask: "Mark these T alerts as read?"

- Do it only on an explicit yes, by calling `mcp__claude_ai_Gmail__unlabel_thread` with `["UNREAD"]` for each thread ID in the batch.
- Mark only the threads that were actually processed, never the whole label.
- Leave the Scholar label on them. Scholar alerts aren't in a primary inbox, so there's nothing to file.
- Report the count, and how many unread Scholar threads remain (from `list_labels`).
