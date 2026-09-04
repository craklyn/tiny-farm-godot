#!/usr/bin/env python3
"""check_gateway.py — proves the one-gateway rule over the presentation layer.

Every change to the farm's world state goes through `SimWorld.apply_action`
(decision S-3, `docs/ARCHITECTURE.md`). That is what makes a recorded session
replay to the same end state, and those recordings are the training data phase 4
runs on. Nothing enforced it: a renderer that wrote `sim.tiles[y][x].state` or
called `sim.set_tile_state()` compiled cleanly, passed the unit suite, passed the
integration suite, and corrupted every replay written afterwards. The break would
have surfaced when bot training failed on the corpus, which is the worst possible
place to find it.

This is the missing enforcement. It reads the simulation's own source to learn
what world state is and which functions change it, then reads the presentation
layer looking for either being touched outside the gateway.

Two things are flagged:

  * **A write into simulation state.** Anything assigned through a chain that
    reaches one of `SimWorld`'s member variables — `sim.tiles[y][x].state = ...`,
    `farm.objects[y][x] = "acorn"`, `sim.actors[id]["pos"] = ...`. The facade
    views on `world/farm.gd` hand out the sim's own arrays, so a write through
    them is a write into the sim and is caught the same way.
  * **A call to a simulation function that changes the world.** `apply_action`
    is the gateway; `set_tile_state`, `water_tile`, `spawn_actor`,
    `set_actor_pos` and their kind are not, and a renderer calling one has gone
    around the gateway even though it never touched a field.

Neither list is written down here. Both are derived from
`systems/sim/sim_world.gd` on every run, so a field or a mutator added to the
simulation tomorrow is covered without anyone remembering to update this file.

**Exemptions are written at the site, never here.** A line that has to break the
rule carries `# gateway-ok: <why>` on itself or in the comment block directly
above it, and every exemption in force is printed on a passing run — an exemption
nobody can see is how a rule stops being a rule.

Usage:
    python3 tools/check_gateway.py          # check, exit 1 on any violation
    python3 tools/check_gateway.py --self-test
                                            # prove the check catches a planted break
"""

import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The simulation source the rules are read out of, and the layers the rules are
# enforced against: everything that draws the world, walks in it, or reacts to
# it. These are the files that hold a reference to a live `SimWorld` and have no
# business changing one.
SIM_SOURCE = os.path.join("systems", "sim", "sim_world.gd")
WATCHED_DIRS = [os.path.join("world"), os.path.join("entities"), os.path.join("player")]

# The gateway itself, and the readers named like writers. `apply_action` is the
# sanctioned door. `_record`-style names are not in play here; this list exists
# so the derivation below can be blunt.
GATEWAY = "apply_action"

# A function whose name starts one of these changes the world by convention, and
# is treated as a mutator even where the body only writes through a local alias
# (`set_actor_pos` writes `e["pos"]`, having taken `e` from the registry — no
# amount of name matching on the body would see that as a write to `actors`).
#
# Every entry is a whole imperative verb. Stems that also begin the name of a
# question — `teach` is the front of `teachable_at`, which only reads — are
# deliberately absent: a reader wrongly called a mutator makes a renderer that
# asks it fail the check, and the fix for that is a waiver, which is how a rule
# gets watered down.
MUTATING_PREFIXES = ("set_", "spawn_", "despawn_", "advance_", "apply_", "generate",
                     "place_", "water_", "start_", "reset", "clear_", "spend_")

WAIVER = re.compile(r"#\s*gateway-ok:\s*(\S.*)$")

# An assignment, as opposed to a comparison or a default argument: `=` that is
# not `==`, `!=`, `<=`, `>=`, and the compound forms.
ASSIGN = re.compile(r"(?<![=!<>+\-*/%])=(?!=)|[+\-*/%]=")


def _lines(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read().splitlines()


def _strip_comment(line):
    """The code half of a line, with `#` inside a string left alone."""
    out, quote = [], None
    i = 0
    while i < len(line):
        c = line[i]
        if quote:
            if c == "\\":
                out.append(line[i:i + 2])
                i += 2
                continue
            if c == quote:
                quote = None
        elif c in "\"'":
            quote = c
        elif c == "#":
            break
        out.append(c)
        i += 1
    return "".join(out)


def read_sim_surface(repo=REPO):
    """What world state is, and which simulation functions change it.

    Returns (state fields, mutating function names). The fields are the member
    variables of `SimWorld`; the mutators are every function that writes one,
    calls something that writes one, or is named like it does.
    """
    src = _lines(os.path.join(repo, SIM_SOURCE))

    fields = set()
    for raw in src:
        m = re.match(r"(?:static\s+)?var\s+([A-Za-z_]\w*)", raw)
        if m:
            fields.add(m.group(1))

    # Function bodies, by indentation.
    bodies, current = {}, None
    for raw in src:
        m = re.match(r"(?:static\s+)?func\s+([A-Za-z_]\w*)\s*\(", raw)
        if m:
            current = m.group(1)
            bodies[current] = []
            continue
        if current is not None:
            if raw.strip() and not raw[:1].isspace():
                current = None          # back at column zero: the function ended
            else:
                bodies[current].append(_strip_comment(raw))

    writes_field = re.compile(
        r"(?:^|[^.\w])(?:self\.)?(" + "|".join(sorted(map(re.escape, fields))) + r")\s*(?:\[|\.|\s*=)")

    mutators = set()
    for name, body in bodies.items():
        if name == GATEWAY:
            continue
        if name.startswith(MUTATING_PREFIXES):
            mutators.add(name)
            continue
        for line in body:
            if not ASSIGN.search(line):
                continue
            lhs = ASSIGN.split(line, 1)[0]
            if writes_field.search(lhs):
                mutators.add(name)
                break

    # Whatever a mutator is called from is a mutator too, until the set settles.
    changed = True
    while changed:
        changed = False
        for name, body in bodies.items():
            if name in mutators or name == GATEWAY:
                continue
            for line in body:
                for called in re.findall(r"(?:^|[^.\w])([A-Za-z_]\w*)\s*\(", line):
                    if called in mutators:
                        mutators.add(name)
                        changed = True
                        break
                else:
                    continue
                break

    # A private helper cannot be reached from outside the class anyway, and a
    # name starting with `_` in the presentation layer is that file's own.
    mutators = {m for m in mutators if not m.startswith("_")}
    return fields, mutators


def _excuse(lines, i):
    """The reason line `i` is allowed past the rule, or None.

    Read from the line itself, or from the comment block sitting directly on top
    of it — the whole block rather than only the line above, because the reason a
    line is exempt is usually a paragraph, and burying the marker in the middle
    of one is how it stops being found. A reason that runs over several lines
    comes back as one sentence.
    """
    here = WAIVER.search(lines[i - 1])
    if here:
        return here.group(1).strip()
    j = i - 2
    while j >= 0 and lines[j].strip().startswith("#"):
        found = WAIVER.search(lines[j])
        if found:
            rest = [lines[k].strip().lstrip("#").strip() for k in range(j + 1, i - 1)]
            return " ".join([found.group(1).strip()] + [r for r in rest if r])
        j -= 1
    return None


def scan(repo=REPO, dirs=None, fields=None, mutators=None):
    """Every ungated touch of simulation state under `dirs`.

    Returns (violations, waivers). Each is a dict of file, line, text and why.
    """
    if fields is None or mutators is None:
        fields, mutators = read_sim_surface(repo)
    dirs = dirs or WATCHED_DIRS

    field_write = re.compile(
        r"(?:^|[^.\w])(?:self\.)?(?:[A-Za-z_]\w*\s*\.\s*)*(" +
        "|".join(sorted(map(re.escape, fields))) + r")\s*(?:\[|\.)")
    # The bluntest break of all is replacing a whole field — `sim.tiles = []` —
    # and the pattern above cannot see it, because it insists on an index or a
    # member after the name. That suffix is there to stop a local variable that
    # happens to share a field's name from being read as a write, so the
    # whole-field case gets its own pattern, which instead insists the field be
    # reached through something: `x.tiles`, never a bare `tiles`.
    field_replace = re.compile(
        r"(?:^|[^.\w])(?:[A-Za-z_]\w*\s*\.\s*)+(" +
        "|".join(sorted(map(re.escape, fields))) + r")\s*$")
    mutator_call = re.compile(
        r"\.\s*(" + "|".join(sorted(map(re.escape, mutators))) + r")\s*\(")

    violations, waivers = [], []
    for d in dirs:
        full = os.path.join(repo, d)
        for root, _sub, files in os.walk(full):
            for name in sorted(files):
                if not name.endswith(".gd"):
                    continue
                path = os.path.join(root, name)
                rel = os.path.relpath(path, repo)
                raw_lines = _lines(path)
                for i, raw in enumerate(raw_lines, 1):
                    code = _strip_comment(raw)
                    if not code.strip():
                        continue
                    why = None
                    if re.match(r"\s*(?:static\s+)?func\s", code):
                        pass                      # a declaration is not a call
                    elif ASSIGN.search(code):
                        lhs = ASSIGN.split(code, 1)[0]
                        hit = field_write.search(lhs) or field_replace.search(lhs.rstrip())
                        if hit:
                            why = ("writes simulation state (`%s`) instead of going "
                                   "through %s" % (hit.group(1), GATEWAY))
                        else:
                            m = mutator_call.search(code)
                            if m:
                                why = ("calls the simulation's `%s`, which changes the world "
                                       "outside %s" % (m.group(1), GATEWAY))
                    else:
                        m = mutator_call.search(code)
                        if m:
                            why = "calls the simulation's `%s`, which changes the world outside %s" % (
                                m.group(1), GATEWAY)
                    if not why:
                        continue
                    excuse = _excuse(raw_lines, i)
                    row = {"file": rel, "line": i, "text": raw.strip(), "why": why}
                    if excuse:
                        row["waiver"] = excuse
                        waivers.append(row)
                    else:
                        violations.append(row)
    return violations, waivers


def _self_test(repo=REPO):
    """Plant each shape of the break and prove the check sees it.

    Runs in CI beside the real check, because a checker nobody has watched fail
    is only a claim that the rule holds.
    """
    import shutil
    import tempfile

    planted = [
        ("sim.tiles[3][4].state = \"ready\"", "a write straight into the grid"),
        ("farm.objects[2][2] = \"acorn\"", "a write through the renderer's facade view"),
        ("sim.actors[\"crow\"][\"pos\"] = Vector2i(1, 1)", "a write into the actor registry"),
        ("sim.set_tile_state(1, 1, \"tilled\")", "a call to a simulation mutator"),
        ("world.sim.spawn_actor(\"crow\", \"crow\", Vector2i(1, 1))", "a spawn from the presentation layer"),
        ("main.farm.sim.water_tile(4, 4)", "a mutator reached through a chain of nodes"),
        ("sim.tiles = []", "a whole simulation field replaced outright"),
        ("sim.actors = {}", "the actor registry replaced outright"),
    ]
    ok = True
    # The derivation is the check's one load-bearing assumption: everything below
    # is only as strong as the list of functions it learned to look for. These are
    # the ones the simulation has today, named here so that a refactor which
    # quietly drops one out of the derived set fails loudly instead of thinning
    # the rule.
    _fields, mutators = read_sim_surface(repo)
    for name in ("set_tile_state", "water_tile", "set_object", "spawn_actor",
                 "despawn_actor", "set_actor_pos", "advance_day", "advance_ticks",
                 "generate"):
        if name not in mutators:
            print("  MISSED  `%s` changes the world and was not derived as a mutator" % name)
            ok = False
    if GATEWAY in mutators:
        print("  MISSED  the gateway itself was derived as a mutator to forbid")
        ok = False

    tmp = tempfile.mkdtemp(prefix="gateway-selftest-")
    try:
        os.makedirs(os.path.join(tmp, "systems", "sim"))
        shutil.copy(os.path.join(repo, SIM_SOURCE), os.path.join(tmp, SIM_SOURCE))
        os.makedirs(os.path.join(tmp, "world"))
        body = ["extends Node2D", "", "var sim: SimWorld", "", "func _break() -> void:"]
        for stmt, _label in planted:
            body.append("\t" + stmt)
        # Two more, excused the two ways a line can be — to prove a waiver is
        # read wherever it is written, and that an excused line is reported
        # rather than silently dropped.
        body.append("\tsim.tiles[0][0].state = \"border\"  # gateway-ok: the self-test, excused on the line")
        body.append("\t# gateway-ok: the self-test, excused from the block above")
        body.append("\t# and this second comment line must not hide the marker")
        body.append("\tsim.despawn_actor(\"crow\")")
        with open(os.path.join(tmp, "world", "planted.gd"), "w", encoding="utf-8") as f:
            f.write("\n".join(body) + "\n")

        found, excused = scan(repo=tmp, dirs=["world"])
        got = {v["line"] for v in found}
        for n, (stmt, label) in enumerate(planted, start=6):
            if n in got:
                print("  caught  %s" % label)
            else:
                print("  MISSED  %s  -- %s" % (label, stmt))
                ok = False
        if len(excused) == 2 and all(e["waiver"].startswith("the self-test") for e in excused):
            print("  caught  both excused lines, and reported the excuse for each")
        else:
            print("  MISSED  %d excused lines expected, %d reported" % (2, len(excused)))
            ok = False
        if len(found) != len(planted):
            print("  MISSED  %d violations expected, %d reported" % (len(planted), len(found)))
            ok = False
        return ok
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main(argv):
    if "--self-test" in argv:
        print("Planting deliberate violations and checking each is caught:")
        ok = _self_test()
        print("SELF-TEST %s" % ("PASSED" if ok else "FAILED"))
        return 0 if ok else 1

    fields, mutators = read_sim_surface()
    violations, waivers = scan(fields=fields, mutators=mutators)

    print("The one-gateway rule (S-3): every world change goes through SimWorld.%s." % GATEWAY)
    print("Read out of %s: %d pieces of world state, %d functions that change it."
          % (SIM_SOURCE, len(fields), len(mutators)))
    print("Checked: %s" % ", ".join(WATCHED_DIRS))

    print("Functions that change the world: %s" % ", ".join(sorted(mutators)))

    if waivers:
        one = len(waivers) == 1
        print("\n%d line%s allowed past the rule, and %s why:"
              % (len(waivers), " is" if one else "s are", "says" if one else "say"))
        for w in waivers:
            print("  %s:%d  %s" % (w["file"], w["line"], w["waiver"]))

    if violations:
        one = len(violations) == 1
        print("\n%d line%s around the gateway:"
              % (len(violations), " goes" if one else "s go"))
        for v in violations:
            print("\n  %s:%d" % (v["file"], v["line"]))
            print("    %s" % v["text"])
            print("    %s" % v["why"])
        print("\nMove the change into a verb on SimWorld.%s and have the caller send"
              % GATEWAY)
        print("an action, or — if the line genuinely must stand — mark it")
        print("`# gateway-ok: <why>` so the exemption is visible to the next reader.")
        print("\nFAILED")
        return 1

    print("\nNothing in the presentation layer changes the world behind the gateway.")
    print("PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
