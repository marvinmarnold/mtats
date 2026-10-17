# SPDX-License-Identifier: MIT
"""Minimal Markdown → HTML for Sparkle release notes: '# ' headings, '- ' bullets, paragraphs."""
import html
import sys


def convert(markdown: str) -> str:
    out, para, in_list = [], [], False

    def flush_para():
        if para:
            out.append(f"<p>{html.escape(' '.join(para))}</p>")
            para.clear()

    for line in markdown.splitlines():
        stripped = line.strip()
        if stripped.startswith("- "):
            flush_para()
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append(f"<li>{html.escape(stripped[2:])}</li>")
            continue
        if in_list:
            out.append("</ul>")
            in_list = False
        if stripped.startswith("#"):
            flush_para()
            out.append(f"<h2>{html.escape(stripped.lstrip('#').strip())}</h2>")
        elif stripped:
            para.append(stripped)
        else:
            flush_para()
    flush_para()
    if in_list:
        out.append("</ul>")
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    with open(sys.argv[1], encoding="utf-8") as f:
        result = convert(f.read())
    with open(sys.argv[2], "w", encoding="utf-8") as f:
        f.write(result)
