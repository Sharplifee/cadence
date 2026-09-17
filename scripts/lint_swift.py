#!/usr/bin/env python3
"""Cheap local checks for the mistakes that actually cost CI cycles here.

The Apple layer cannot be type-checked off a Mac, so these two classes of error
were only surfacing after a ten-minute build: a member declared twice inside the
same type, and a call to something that no longer exists. Both are findable with
brace tracking and a symbol sweep.
"""
import collections, pathlib, re, sys

DECL = re.compile(r'^\s*(?:@\w+(?:\([^)]*\))?\s+)*'
                  r'(?:public |private |fileprivate |internal |static |final |override |nonisolated |lazy |weak )*'
                  r'(?:var|let|func)\s+(\w+)(\([^)]*\))?')
TYPE = re.compile(r'^\s*(?:public |private |fileprivate |internal |final )*'
                  r'(?:class|struct|enum|extension|actor)\s+(\w+)')

def members_by_type(path: pathlib.Path):
    """Map each type body to the members declared directly inside it."""
    out = collections.defaultdict(list)
    stack, depth = [], 0
    for line in path.read_text().splitlines():
        t = TYPE.match(line)
        if t:
            stack.append((t.group(1), depth))
        d = DECL.match(line)
        # Only count declarations at the type's own level, not nested closures.
        if d and stack and depth == stack[-1][1] + 1:
            # Swift allows overloads, so identity is name + argument labels.
            labels = ""
            if d.group(2):
                labels = ",".join(a.strip().split(":")[0].split()[0]
                                  for a in d.group(2)[1:-1].split(",") if a.strip())
            out[stack[-1][0]].append((d.group(1), labels))
        depth += line.count("{") - line.count("}")
        while stack and depth <= stack[-1][1]:
            stack.pop()
    return out

def main() -> None:
    problems = []
    files = [p for d in sys.argv[1:] for p in pathlib.Path(d).rglob("*.swift")]
    declared = set()
    for f in files:
        for typename, names in members_by_type(f).items():
            for (name, labels), n in collections.Counter(names).items():
                if n > 1:
                    problems.append(f"{f}: {typename}.{name}({labels}) declared {n} times")
            declared.update(n for n, _ in names)

    for f in files:
        src = f.read_text()
        for call in set(re.findall(r'\bself\.(\w+)\(', src)) | set(re.findall(r'controller\.(\w+)\(', src)):
            if call not in declared and call not in {"init"}:
                problems.append(f"{f}: calls {call}() which is declared nowhere")

    for p in sorted(set(problems)):
        print("  -", p)
    if problems:
        print(f"\n{len(set(problems))} problem(s)")
        sys.exit(1)
    print(f"lint clean across {len(files)} files")

if __name__ == "__main__":
    main()
