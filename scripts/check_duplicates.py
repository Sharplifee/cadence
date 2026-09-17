#!/usr/bin/env python3
"""Catch duplicate declarations before they cost a ten-minute macOS round trip.

`swiftc -parse` on Linux is syntax-only — it happily accepts a file that
declares the same property twice, which then fails type-checking on the runner
with "invalid redeclaration". Since the Apple layer cannot be type-checked off a
Mac, this is the cheapest way to catch the most common class of breakage.

Naive brace-depth counting produces almost nothing but false positives: two
different structs both declaring `id`, or two functions each with a local `let
t`, are at the same depth but in different scopes. So this tracks the full scope
PATH and only reports a collision when both declarations share it.
"""
import pathlib, re, sys
from collections import defaultdict

SCOPE = re.compile(
    r'^\s*(?:@\w+(?:\([^)]*\))?\s+)*'
    r'(?:public|internal|private|fileprivate|open)?\s*'
    r'(?:final\s+|static\s+|indirect\s+)*'
    r'(struct|class|enum|extension|protocol|actor|func|init|var)\s+([A-Za-z_]\w*)?'
)
MEMBER = re.compile(
    r'^\s*(?:@\w+(?:\([^)]*\))?\s+)*'
    r'(?:public|internal|private|fileprivate|open)?\s*'
    r'(?:static\s+|class\s+|nonisolated\s+)*'
    r'(func|var|let)\s+([A-Za-z_]\w*)\s*(\([^)]*\))?'
)

def signature(kind: str, name: str, params: str | None) -> str:
    """Swift allows overloads, so a func's identity includes its argument
    labels. Matching on name alone flags every legitimate overload —
    start() vs start(coaching:), or the four WCSessionDelegate methods."""
    if kind != "func" or not params:
        return name
    labels = []
    for part in params[1:-1].split(","):
        part = part.strip()
        if not part:
            continue
        labels.append(part.split(":")[0].split()[0])
    return f"{name}({','.join(labels)})"

def main() -> None:
    problems = []
    for path in sorted(pathlib.Path('.').rglob('*.swift')):
        if '.build' in path.parts:
            continue
        stack, seen = [], defaultdict(list)
        for n, raw in enumerate(path.read_text().splitlines(), 1):
            line = raw.split('//')[0]
            m = MEMBER.match(raw)
            # Only type members matter — locals inside a function body are
            # scoped to that body and legitimately repeat.
            if m and stack and stack[-1][0] in ('struct','class','enum','extension','protocol','actor'):
                key = signature(m.group(1), m.group(2), m.group(3))
                seen[(tuple(s[1] for s in stack), key)].append(n)

            s = SCOPE.match(raw)
            opens = line.count('{') - line.count('}')
            if s and '{' in line:
                stack.append((s.group(1), s.group(2) or f"anon{n}"))
                opens -= 1
            for _ in range(max(0, -opens)):
                if stack: stack.pop()
            for _ in range(max(0, opens)):
                stack.append(("block", f"b{n}"))

        for (scope, name), lines in seen.items():
            if len(lines) > 1:
                where = ".".join(scope) or "<file>"
                problems.append(f"{path}:{lines[0]} '{name}' declared "
                                f"{len(lines)}x in {where} (lines {', '.join(map(str, lines))})")
    if problems:
        print("DUPLICATE DECLARATIONS:")
        for p in problems:
            print("  -", p)
        sys.exit(1)
    print("No duplicate declarations.")

if __name__ == "__main__":
    main()
