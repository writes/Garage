#!/usr/bin/env python3
"""secret_screen.py — shared fail-closed secret screening for ALL provider-bound text.

Single source of truth for the credential pattern set (previously private to
tri_review.py). Imported by tri_review (reviews), tri_agent_vote (Law-1 votes —
DS-5 fix 2026-07-12: the vote path previously wrote raw LLM output to the ledger
unscreened), and gemini_consult (agy prompts travel as an argv element, visible
in `ps` to any local process while agy runs — secrets must never reach argv).

We report pattern labels, not matching text, so a blocked run cannot echo a
secret into logs or terminal scrollback.
"""
from __future__ import annotations

import re
import sys
from typing import List, Tuple

SECRET_PATTERNS: Tuple[Tuple[str, "re.Pattern[str]"], ...] = (
    ("private key block", re.compile(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----", re.IGNORECASE)),
    ("AWS access key", re.compile(r"AKIA[0-9A-Z]{16}")),
    ("Google API key", re.compile(r"AIza[0-9A-Za-z_-]{35}")),
    ("JWT", re.compile(r"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.")),
    ("GitHub token", re.compile(r"gh[pousr]_[A-Za-z0-9]{20,}")),
    ("GitHub fine-grained PAT", re.compile(r"github_pat_[A-Za-z0-9_]{20,}")),
    # The lookbehind is load-bearing (RECONSTRUCTED 2026-08-11 after an agent reset --hard
    # destroyed the original uncommitted fix): without it, "sk-" matches INSIDE ordinary
    # hyphenated words — the assay slug "ask-garage-history-aware-ai-chat" blocked a Law-1
    # vote as a false-positive "OpenAI key" on 2026-08-07. A real key is never immediately
    # preceded by a letter or digit.
    ("OpenAI key", re.compile(r"(?<![A-Za-z0-9])sk-(?!ant-)[A-Za-z0-9_-]{20,}")),
    ("Anthropic key", re.compile(r"(?<![A-Za-z0-9])sk-ant-[A-Za-z0-9-]{20,}")),
    ("Stripe secret key", re.compile(r"[rs]k_(?:live|test)_[A-Za-z0-9]{16,}")),
    ("Slack token", re.compile(r"xox[baprs]-[A-Za-z0-9-]{10,}")),
    (
        "quoted JSON credential",
        re.compile(r'"(?:api_?key|secret|token|password)"\s*:\s*"[^"]{12,}"', re.IGNORECASE),
    ),
    (
        "dotenv credential",
        re.compile(
            r"(?m)^(?:\+)?(?:API_?KEY|SECRET|TOKEN|PASSWORD)\s*=\s*(?!['\"])\S{12,}\s*$",
            re.IGNORECASE,
        ),
    ),
    (
        "unquoted dotenv/YAML credential assignment",
        re.compile(
            r"(?im)^[A-Z0-9_]*(PASSWORD|SECRET|TOKEN|API_?KEY|PRIVATE_KEY)\s*[:=]\s*\S{8,}$"
        ),
    ),
    (
        "generic credential assignment",
        re.compile(
            r"(?:api[_-]?key|secret|token|password)\s*[:=]\s*['\"][^'\"]{12,}",
            re.IGNORECASE,
        ),
    ),
    (
        "Firebase token",
        re.compile(r"AAAA[0-9A-Za-z_-]{7,}:[0-9A-Za-z_-]{20,}"),
    ),
)
# ``SECRET_PATTERNS`` deliberately detects a PEM header even when a test fixture
# or truncated artifact lacks its footer. When redacting an actual artifact,
# consume the whole block (or the remaining excerpt) so its body cannot leak.
PRIVATE_KEY_REDACTION_RE = re.compile(
    r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?(?:-----END [A-Z0-9 ]*PRIVATE KEY-----|$)",
    re.IGNORECASE,
)


def secret_scan(diff_text: str) -> List[str]:
    """Return labels for secret-like patterns found in text, never values."""
    return [label for label, pattern in SECRET_PATTERNS if pattern.search(diff_text)]


def redact_secret_content(content: str) -> Tuple[str, List[str]]:
    """Replace secret-like matches while retaining only their safe pattern labels.

    Provider output is untrusted and can contain prompt-injected credentials.
    Redaction happens before an artifact is rendered or written, so the record
    keeps the fact of a hit without becoming an exfiltration channel itself.
    """
    redacted = content
    labels: List[str] = []
    for label, pattern in SECRET_PATTERNS:
        if pattern.search(redacted):
            labels.append(label)
            replacement_pattern = (
                PRIVATE_KEY_REDACTION_RE if label == "private key block" else pattern
            )
            redacted = replacement_pattern.sub(f"[REDACTED: {label}]", redacted)
    return redacted, labels


def _selftest() -> int:
    failures = []

    def check(name, cond):
        print(("  ok    " if cond else "  FAIL  ") + name)
        if not cond:
            failures.append(name)

    check("clean text passes", secret_scan("A: rules counter is best because atomic") == [])
    check("anthropic key detected", "Anthropic key" in secret_scan("x sk-ant-" + "a1b2c3d4e5" * 3))
    check("openai key not confused with anthropic",
          secret_scan("sk-ant-" + "a1" * 12) == ["Anthropic key"])
    check("openai key still detected standalone", "OpenAI key" in secret_scan("key sk-" + "b2" * 12))
    check("hyphenated words are not keys (ask-garage regression)",
          secret_scan("assay 2026-08-02_ask-garage-history-aware-ai-chat revisit") == [])
    redacted, labels = redact_secret_content("key: sk-ant-" + "a1b2c3d4e5" * 3 + " end")
    check("redaction removes value", "sk-ant-" not in redacted and "[REDACTED: Anthropic key]" in redacted)
    check("redaction reports label", labels == ["Anthropic key"])
    pem = "-----BEGIN RSA PRIVATE KEY-----\nMII...\n-----END RSA PRIVATE KEY-----"
    redacted, labels = redact_secret_content(pem)
    check("pem body consumed", "MII" not in redacted and "private key block" in labels)
    print("SELFTEST " + ("PASSED" if not failures else f"FAILED ({len(failures)})"))
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(_selftest() if len(sys.argv) > 1 and sys.argv[1] == "selftest" else _selftest())
