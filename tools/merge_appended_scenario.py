"""Merge a worker branch whose only change to tools/test_runner.gd is one appended
integration scenario: a call at the end of _run_scenarios() plus a block at the end of
the file.

Why this exists (2026-09-10, the workbench build): two scenarios written in parallel both
began with the same staging lines copied from an earlier one, and git's content merge
aligned them and spliced the second's header into the first's body. "Keep both sides"
then produced a file with a one-line scenario and a hybrid, with no duplicate function
to catch it. This script rebuilds the file as main's version plus the branch's appended
block, checks for duplicate functions, and leaves the merge staged for `git commit`.

Usage, on main, from the repo root:
    python3 tools/merge_appended_scenario.py <branch> <scenario_function_name>
    git commit -m "..."

It refuses (and leaves nothing half-done) when the branch changed anything in the file
other than the append; resolve those by hand, reading both sides."""
import subprocess, sys, re
branch, scenario = sys.argv[1], sys.argv[2]
run = lambda *a: subprocess.check_output(a).decode()
mb = run('git','merge-base','main',branch).strip()
show = lambda ref: run('git','show', ref+':tools/test_runner.gd')
base, common, theirs = show('main'), show(mb), show(branch)
call = '\tawait %s()\n' % scenario
assert theirs.count(call) == 1, "branch does not call the scenario exactly once"
stripped = theirs.replace(call, '', 1)
assert stripped.startswith(common), "branch changed more than an append in tools/test_runner.gd; resolve by hand"
tail = stripped[len(common):]
# insert the call after the last scenario call in _run_scenarios
calls = list(re.finditer(r'^\tawait _scenario_[a-z0-9_]+\(\)\n', base, re.M))
last = calls[-1]
final = base[:last.end()] + call + base[last.end():]
if not final.endswith('\n'): final += '\n'
final += tail
funcs = re.findall(r'^(?:static )?func ([A-Za-z_0-9]+)', final, re.M)
dups = sorted({f for f in funcs if funcs.count(f) > 1})
assert not dups, "duplicate functions: %r" % dups
assert final.count(call) == 1 and len(re.findall(r'^func %s\(' % scenario, final, re.M)) == 1
subprocess.run(['git','merge','--no-ff','--no-commit',branch], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
open('tools/test_runner.gd','w').write(final)
subprocess.check_call(['git','add','tools/test_runner.gd'])
left = run('git','diff','--name-only','--diff-filter=U').strip()
assert not left, "other conflicts remain: %s" % left
print("staged: main + %s appended (%d lines); no duplicate funcs" % (scenario, tail.count('\n')))
