#!/usr/bin/env python3
"""Two files in HQ's front-end cannot declare the same name.

`hq/static/*.js` are plain scripts, not modules, so they share one global scope.
A `const WORK_STATE` in `pillars.js` and another in `app.js` is a SyntaxError that
takes down every page at once — and each file passes `node --check` on its own,
which is exactly why it got shipped: the tool that would have caught it does not
look at more than one file.

    python3 tools/check_frontend.py
    python3 tools/check_frontend.py --self-test

The failure is loud (a blank dashboard) but silent to every check we run, which
is the worst combination a defect can have.
"""
import argparse
import os
import re
import sys
from collections import defaultdict

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATIC = os.path.join(REPO, "hq", "static")
# Top-level only: an indented declaration is inside a function and is scoped to it.
TOP_LEVEL = re.compile(r"^(?:const|let|var|function|class)\s+([A-Za-z_$][\w$]*)", re.M)


def declarations(path):
    with open(path, encoding="utf-8") as f:
        src = f.read()
    # Comments can hold example code; stripping them keeps a doc comment from
    # being read as a declaration.
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    src = re.sub(r"^\s*//.*$", "", src, flags=re.M)
    return set(TOP_LEVEL.findall(src))


def scan(static=STATIC):
    owners = defaultdict(list)
    for name in sorted(os.listdir(static)):
        if not name.endswith(".js") or name == "vendor":
            continue
        path = os.path.join(static, name)
        if not os.path.isfile(path):
            continue
        for decl in declarations(path):
            owners[decl].append(name)
    return {d: files for d, files in owners.items() if len(files) > 1}


def self_test():
    import tempfile
    ok = True
    with tempfile.TemporaryDirectory() as tmp:
        open(os.path.join(tmp, "a.js"), "w").write("const SHARED = 1;\nfunction go() { const local = 2; }\n")
        open(os.path.join(tmp, "b.js"), "w").write("const SHARED = 3;\nfunction go2() { const local = 4; }\n")
        clash = scan(tmp)
        if list(clash) == ["SHARED"]:
            print("  caught  the same top-level name declared in two files")
        else:
            print(f"  MISSED  expected SHARED to clash, got {clash}")
            ok = False
        if "local" in clash:
            print("  MISSED  a name inside a function was treated as global")
            ok = False
        else:
            print("  caught  a name inside a function is left alone")
    return ok


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args(argv)
    if args.self_test:
        print("Planting a clash and checking it is caught:")
        good = self_test()
        print("SELF-TEST PASSED" if good else "SELF-TEST FAILED")
        return 0 if good else 1

    clashes = scan()
    if not clashes:
        print("No name is declared twice across HQ's front-end files.")
        return 0
    for decl, files in sorted(clashes.items()):
        print(f"  {decl} is declared in {', '.join(files)}")
    print(f"\n{len(clashes)} name(s) declared in more than one file. These share one "
          "scope, so this is a SyntaxError that blanks every page.")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
