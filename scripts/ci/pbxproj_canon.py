#!/usr/bin/env python3
"""Canonicalize a project.pbxproj on stdin -> stdout for the regenerate-equality gate.

xcodegen emits two *non-semantic* non-determinisms for the test target's link:false SwiftPM
product deps: random ``TEMP_<uuid>`` placeholder ids, and a random ORDER of the
``XCSwiftPackageProductDependency`` block definitions. We must absorb ONLY those while keeping
the rest of the file strictly order-preserved — a flat whole-file ``sort`` would let a line
PERMUTATION (e.g. moving ``ENABLE_TESTABILITY`` into Release, or swapping the Debug/Release
``CODE_SIGN_ENTITLEMENTS``) pass undetected, defeating the gate.

Canonical form: (1) replace every ``TEMP_<uuid>`` with ``TEMP_X``; (2) sort ONLY the block
records inside the ``XCSwiftPackageProductDependency`` section; (3) leave every other line in
place. Any real change anywhere else shows up in a line-for-line diff of the canonical output.
"""
import re
import sys

TEMP = re.compile(r"TEMP_[0-9A-Fa-f-]+")
BLOCK_END = re.compile(r"^\t\t\};\s*$")


def canonicalize(text: str) -> str:
    text = TEMP.sub("TEMP_X", text)
    lines = text.split("\n")
    out: list[str] = []
    i, n = 0, len(lines)
    while i < n:
        line = lines[i]
        if "Begin XCSwiftPackageProductDependency section" in line:
            out.append(line)
            i += 1
            block_lines: list[str] = []
            while i < n and "End XCSwiftPackageProductDependency section" not in lines[i]:
                block_lines.append(lines[i])
                i += 1
            # Group into records terminated by a "\t\t};" line, then sort the records.
            blocks: list[str] = []
            cur: list[str] = []
            for bl in block_lines:
                cur.append(bl)
                if BLOCK_END.match(bl):
                    blocks.append("\n".join(cur))
                    cur = []
            if any(s.strip() for s in cur):  # defensive: unterminated remainder
                blocks.append("\n".join(cur))
            blocks.sort()
            if blocks:
                out.extend("\n".join(blocks).split("\n"))
            # loop continues with lines[i] == the "End ... section" line (or EOF)
            continue
        out.append(line)
        i += 1
    return "\n".join(out)


if __name__ == "__main__":
    sys.stdout.write(canonicalize(sys.stdin.read()))
