#!/usr/bin/env python3
"""Render the hosted Privacy Policy / Terms of Use pages from the repo's legal drafts.

Why this exists
---------------
`scripts/ci/release-checks.sh` blocks release while `Constants.privacyPolicyURLString` /
`Constants.termsOfUseURLString` still point at `.invalid` placeholders. Closing that blocker
needs two real, resolvable HTTPS URLs, which means the drafts in `docs/legal/` have to be
published somewhere stable. Firebase Hosting is already in this project's stack and is free,
so that is the default target.

The one rule this tool enforces: **it refuses to render a page that still contains an
unfilled placeholder.** Publishing a privacy policy that says "[SUPPORT EMAIL]" is worse than
publishing nothing — it is a legal document with a hole in it, served from your domain.

Usage
-----
    python3 scripts/release/legal_site.py init      # write docs/legal/site.config.json stub
    python3 scripts/release/legal_site.py render    # drafts + config -> public/*.html
    python3 scripts/release/legal_site.py --selftest

Deploying (operator, avoids touching the PROTECTED firebase.json):

    firebase deploy --only hosting --config firebase.hosting.json --project prod

which serves:
    https://<project>.web.app/privacy
    https://<project>.web.app/terms
"""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
LEGAL_DIR = REPO_ROOT / "docs" / "legal"
CONFIG_PATH = LEGAL_DIR / "site.config.json"
PUBLIC_DIR = REPO_ROOT / "public"
HOSTING_CONFIG = REPO_ROOT / "firebase.hosting.json"

# Any "[...]" span left in the source is an unfilled author placeholder.
PLACEHOLDER_RE = re.compile(r"\[([^\]]{2,80})\]")
# ...except markdown links, which are legitimately "[text](url)".
MARKDOWN_LINK_RE = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")

CONFIG_STUB = {
    "effective_date": "",
    "support_email": "",
    "legal_entity": "",
    "legal_address": "",
    "children_age": "13",
    "app_name": "Garage",
    "links": {
        "firebase": "https://firebase.google.com/terms",
        "revenuecat": "https://www.revenuecat.com/privacy",
        "anthropic": "https://www.anthropic.com/legal/privacy",
    },
}

PAGES = {
    "privacy": ("PRIVACY_POLICY_DRAFT.md", "Privacy Policy"),
    "terms": ("TERMS_OF_USE_DRAFT.md", "Terms of Use"),
}

STYLE = """
:root { color-scheme: light dark; }
* { box-sizing: border-box; }
body {
  margin: 0 auto; padding: 2.5rem 1.25rem 5rem; max-width: 44rem;
  font: 17px/1.65 -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
  color: #14181d; background: #fff;
}
@media (prefers-color-scheme: dark) { body { color: #e9eef3; background: #12161a; } }
h1 { font-size: 2rem; line-height: 1.2; margin: 0 0 .35rem; letter-spacing: -0.02em; }
h2 { font-size: 1.2rem; margin: 2.25rem 0 .6rem; letter-spacing: -0.01em; }
p, li { margin: .6rem 0; }
ul { padding-left: 1.25rem; }
a { color: #0b6bcb; }
@media (prefers-color-scheme: dark) { a { color: #6db3f2; } }
hr { border: 0; border-top: 1px solid currentColor; opacity: .15; margin: 2rem 0; }
.meta { opacity: .72; font-size: .95rem; margin: 0 0 1.5rem; }
footer { margin-top: 3rem; font-size: .9rem; opacity: .7; }
"""


class RenderError(RuntimeError):
    """Raised when the drafts or config are not publishable."""


@dataclass(frozen=True)
class Config:
    effective_date: str
    support_email: str
    legal_entity: str
    legal_address: str
    children_age: str
    app_name: str
    links: dict[str, str]

    @classmethod
    def load(cls, path: Path) -> "Config":
        if not path.exists():
            raise RenderError(
                f"missing {path}\n"
                f"Run:  python3 scripts/release/legal_site.py init\n"
                f"then fill in every field before rendering."
            )
        raw = json.loads(path.read_text())
        missing = [
            k
            for k in ("effective_date", "support_email", "legal_entity", "children_age")
            if not str(raw.get(k, "")).strip()
        ]
        if missing:
            raise RenderError(
                f"{path} has empty required field(s): {', '.join(missing)}\n"
                "These appear verbatim in a published legal document — they cannot be guessed."
            )
        return cls(
            effective_date=raw["effective_date"].strip(),
            support_email=raw["support_email"].strip(),
            legal_entity=raw["legal_entity"].strip(),
            legal_address=str(raw.get("legal_address", "")).strip(),
            children_age=str(raw["children_age"]).strip(),
            app_name=str(raw.get("app_name", "Garage")).strip() or "Garage",
            links={str(k): str(v) for k, v in (raw.get("links") or {}).items()},
        )

    def substitutions(self) -> dict[str, str]:
        entity = self.legal_entity
        if self.legal_address:
            entity = f"{entity}, {self.legal_address}"
        return {
            "DATE": self.effective_date,
            "SUPPORT EMAIL": self.support_email,
            "LEGAL ENTITY / ADDRESS": entity,
            "LEGAL ENTITY": self.legal_entity,
            "13/16": self.children_age,
            "LINK to Firebase/Google terms": self.links.get("firebase", ""),
        }


def strip_draft_banner(markdown: str) -> str:
    """Drop the internal '> DRAFT for operator + legal review' blockquote and the title.

    The banner is instructions to us, not to the reader. The <h1> is rendered from the page
    title instead, so the draft's own '# ... (DRAFT)' heading goes too.
    """
    lines = markdown.splitlines()
    out: list[str] = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("# "):
            continue
        if stripped.startswith(">"):
            continue
        out.append(line)
    return "\n".join(out).strip()


def apply_substitutions(markdown: str, subs: dict[str, str]) -> str:
    def replace(match: re.Match[str]) -> str:
        key = match.group(1)
        if key in subs:
            value = subs[key]
            return value
        return match.group(0)

    # Protect real markdown links from placeholder substitution by rendering them first.
    placeholders: list[str] = []

    def stash(match: re.Match[str]) -> str:
        placeholders.append(match.group(0))
        return f"\x00LINK{len(placeholders) - 1}\x00"

    guarded = MARKDOWN_LINK_RE.sub(stash, markdown)
    substituted = PLACEHOLDER_RE.sub(replace, guarded)
    for index, original in enumerate(placeholders):
        substituted = substituted.replace(f"\x00LINK{index}\x00", original)
    return substituted


def assert_no_placeholders(text: str, source: str) -> None:
    guarded = MARKDOWN_LINK_RE.sub("", text)
    leftovers = sorted({m.group(0) for m in PLACEHOLDER_RE.finditer(guarded)})
    if leftovers:
        raise RenderError(
            f"{source} still contains unfilled placeholder(s): {', '.join(leftovers)}\n"
            "Refusing to publish a legal document with holes in it. Fill them in "
            f"{CONFIG_PATH.relative_to(REPO_ROOT)} or edit the draft directly."
        )


def inline_markdown(text: str) -> str:
    """Convert the inline subset the drafts actually use: links, bold, code."""
    escaped = html.escape(text, quote=False)
    escaped = re.sub(
        r"\[([^\]]+)\]\(([^)]+)\)",
        lambda m: f'<a href="{html.escape(m.group(2), quote=True)}" '
        f'rel="noopener">{m.group(1)}</a>',
        escaped,
    )
    escaped = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", escaped)
    escaped = re.sub(r"`([^`]+)`", r"<code>\1</code>", escaped)
    return escaped


def markdown_to_html(markdown: str) -> str:
    """Render the small markdown subset used by the drafts: h2, ul, p, hr."""
    blocks: list[str] = []
    list_items: list[str] = []
    paragraph: list[str] = []

    def flush_paragraph() -> None:
        if paragraph:
            blocks.append(f"<p>{inline_markdown(' '.join(paragraph))}</p>")
            paragraph.clear()

    def flush_list() -> None:
        if list_items:
            rendered = "".join(f"<li>{inline_markdown(i)}</li>" for i in list_items)
            blocks.append(f"<ul>{rendered}</ul>")
            list_items.clear()

    for raw_line in markdown.splitlines():
        line = raw_line.rstrip()
        stripped = line.strip()
        if not stripped:
            flush_paragraph()
            flush_list()
            continue
        if stripped.startswith("## "):
            flush_paragraph()
            flush_list()
            blocks.append(f"<h2>{inline_markdown(stripped[3:].strip())}</h2>")
            continue
        if stripped.startswith("---"):
            flush_paragraph()
            flush_list()
            blocks.append("<hr>")
            continue
        if stripped.startswith("- "):
            flush_paragraph()
            list_items.append(stripped[2:].strip())
            continue
        if list_items:
            # Continuation line of the previous bullet.
            list_items[-1] = f"{list_items[-1]} {stripped}"
            continue
        paragraph.append(stripped)

    flush_paragraph()
    flush_list()
    return "\n".join(blocks)


def page_html(title: str, app_name: str, body: str, effective_date: str, email: str) -> str:
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(app_name)} — {html.escape(title)}</title>
<style>{STYLE}</style>
</head>
<body>
<h1>{html.escape(app_name)} — {html.escape(title)}</h1>
<p class="meta">Effective {html.escape(effective_date)} · Contact
<a href="mailto:{html.escape(email, quote=True)}">{html.escape(email)}</a></p>
{body}
<footer><a href="/">{html.escape(app_name)}</a></footer>
</body>
</html>
"""


INDEX_HTML = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{app} — Legal</title>
<style>{style}</style>
</head>
<body>
<h1>{app}</h1>
<p>Service records for people who keep their cars.</p>
<ul>
<li><a href="/privacy">Privacy Policy</a></li>
<li><a href="/terms">Terms of Use</a></li>
</ul>
</body>
</html>
"""

HOSTING_JSON = {
    "hosting": {
        "public": "public",
        "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
        "cleanUrls": True,
        "rewrites": [],
    }
}


def cmd_init() -> int:
    if CONFIG_PATH.exists():
        print(f"{CONFIG_PATH} already exists — leaving it alone.")
        return 0
    LEGAL_DIR.mkdir(parents=True, exist_ok=True)
    CONFIG_PATH.write_text(json.dumps(CONFIG_STUB, indent=2) + "\n")
    print(f"Wrote {CONFIG_PATH}")
    print("Fill in: effective_date, support_email, legal_entity, legal_address, children_age.")
    return 0


def cmd_render(check_only: bool = False) -> int:
    config = Config.load(CONFIG_PATH)
    subs = config.substitutions()
    rendered: dict[str, str] = {}

    for slug, (filename, title) in PAGES.items():
        source = LEGAL_DIR / filename
        if not source.exists():
            raise RenderError(f"missing draft {source}")
        markdown = strip_draft_banner(source.read_text())
        markdown = apply_substitutions(markdown, subs)
        assert_no_placeholders(markdown, str(source.relative_to(REPO_ROOT)))
        body = markdown_to_html(markdown)
        rendered[slug] = page_html(
            title, config.app_name, body, config.effective_date, config.support_email
        )

    if check_only:
        print("OK — drafts and config are publishable (nothing written).")
        return 0

    PUBLIC_DIR.mkdir(parents=True, exist_ok=True)
    for slug, document in rendered.items():
        target = PUBLIC_DIR / f"{slug}.html"
        target.write_text(document)
        print(f"wrote {target.relative_to(REPO_ROOT)}")

    index = PUBLIC_DIR / "index.html"
    index.write_text(INDEX_HTML.format(app=html.escape(config.app_name), style=STYLE))
    print(f"wrote {index.relative_to(REPO_ROOT)}")

    if not HOSTING_CONFIG.exists():
        HOSTING_CONFIG.write_text(json.dumps(HOSTING_JSON, indent=2) + "\n")
        print(f"wrote {HOSTING_CONFIG.relative_to(REPO_ROOT)} (separate from the PROTECTED firebase.json)")

    print()
    print("Next (operator):")
    print("  firebase deploy --only hosting --config firebase.hosting.json --project prod")
    print("  -> https://<project>.web.app/privacy and /terms")
    print("  then set both URLs in Garage/Core/Utilities/Constants.swift")
    return 0


def selftest() -> int:
    failures: list[str] = []

    def check(name: str, condition: bool) -> None:
        print(f"{'PASS' if condition else 'FAIL'}  {name}")
        if not condition:
            failures.append(name)

    subs = {"DATE": "2026-07-24", "SUPPORT EMAIL": "a@b.com", "13/16": "13"}
    filled = apply_substitutions("Effective [DATE], write [SUPPORT EMAIL].", subs)
    check("placeholders substituted", filled == "Effective 2026-07-24, write a@b.com.")

    link_md = "See [the terms](https://example.com/x) please."
    check("markdown links survive substitution", apply_substitutions(link_md, subs) == link_md)

    try:
        assert_no_placeholders("Contact [SUPPORT EMAIL] now.", "t.md")
        check("unfilled placeholder rejected", False)
    except RenderError:
        check("unfilled placeholder rejected", True)

    try:
        assert_no_placeholders(link_md, "t.md")
        check("markdown link not mistaken for placeholder", True)
    except RenderError:
        check("markdown link not mistaken for placeholder", False)

    rendered = markdown_to_html("## Head\n\n- one\n- two\n\nA **bold** para.")
    check("h2 rendered", "<h2>Head</h2>" in rendered)
    check("list rendered", "<ul><li>one</li><li>two</li></ul>" in rendered)
    check("bold rendered", "<strong>bold</strong>" in rendered)

    escaped = markdown_to_html("5 < 6 & 7 > 2")
    check("html escaped", "&lt;" in escaped and "&amp;" in escaped)

    banner = strip_draft_banner("# Title (DRAFT)\n\n> warning\n\n## Real\n\ntext")
    check("draft banner stripped", "warning" not in banner and "## Real" in banner)

    drafts_present = all((LEGAL_DIR / f).exists() for f, _ in PAGES.values())
    check("both legal drafts present in repo", drafts_present)

    print()
    print(f"{len(failures)} failure(s)")
    return 1 if failures else 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--selftest", action="store_true", help="run offline unit checks")
    sub = parser.add_subparsers(dest="command")
    sub.add_parser("init", help="write the config stub")
    render = sub.add_parser("render", help="render drafts to public/*.html")
    render.add_argument("--check", action="store_true", help="validate without writing")

    args = parser.parse_args(argv)
    if args.selftest:
        return selftest()
    try:
        if args.command == "init":
            return cmd_init()
        if args.command == "render":
            return cmd_render(check_only=args.check)
    except RenderError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    parser.print_help()
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
