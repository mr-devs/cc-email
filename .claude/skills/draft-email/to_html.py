"""Convert a drafts/*.md file's plain-text body into the HTML used for the Gmail draft.

Usage: python3 -I to_html.py <draft-file.md>

Prints the HTML body to stdout. Sending HTML ourselves, instead of letting the
connector convert plain text, keeps links readable: the connector's own
conversion turned a bare "example.com" into a visible google.com/url?q=...
redirect.

- Paragraphs (separated by blank lines) become <div>s, with line breaks kept.
- http(s) URLs anywhere become links whose text is the URL as written.
- Everything from a line that is exactly "--" (or "-- ") onward is the
  signature: it's rendered small, like a Gmail signature, and bare domains
  such as "example.com" become links too.
"""

import html
import re
import sys

URL = re.compile(r"https?://[^\s<>\"]+[^\s<>\".,;:!?)\]]")
BARE_DOMAIN = re.compile(r"\b(?:[a-z0-9-]+\.)+[a-z]{2,}(?:/[^\s<>\"]*)?", re.I)


def read_body(path):
    text = open(path, encoding="utf-8").read()
    if text.startswith("---\n"):
        end = text.find("\n---\n", 4)
        if end == -1:
            sys.exit("front matter is not closed with ---")
        text = text[end + len("\n---\n") :]
    return text.strip("\n")


def link(match, href=None):
    shown = match.group(0)
    return f'<a href="{html.escape(href or shown)}">{html.escape(shown)}</a>'


def linkify(line, bare_domains):
    out, pos = [], 0
    pattern = BARE_DOMAIN if bare_domains else URL
    for m in pattern.finditer(line):
        out.append(html.escape(line[pos : m.start()]))
        shown = m.group(0)
        if shown.lower().startswith(("http://", "https://")):
            out.append(link(m))
        elif "@" in line[max(0, m.start() - 1) : m.start()]:
            out.append(html.escape(shown))  # part of an email address
        else:
            out.append(link(m, "https://" + shown))
        pos = m.end()
    out.append(html.escape(line[pos:]))
    return "".join(out)


def paragraphs_to_html(lines, bare_domains=False):
    blocks, current = [], []
    for line in lines + [""]:
        if line.strip():
            current.append(linkify(line, bare_domains))
        elif current:
            blocks.append("<div>" + "<br>".join(current) + "</div>")
            current = []
    return "<div><br></div>".join(blocks)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    lines = read_body(sys.argv[1]).split("\n")
    sig_at = next((i for i, l in enumerate(lines) if l.rstrip() == "--"), None)
    body, sig = (lines, []) if sig_at is None else (lines[:sig_at], lines[sig_at:])

    parts = [paragraphs_to_html(body)]
    if sig:
        sig_html = "<br>".join(linkify(l, bare_domains=True) for l in sig)
        parts.append(
            f'<div><br></div><div class="gmail_signature"><font size="1">{sig_html}</font></div>'
        )
    print('<div dir="ltr">' + "".join(parts) + "</div>")


if __name__ == "__main__":
    main()
