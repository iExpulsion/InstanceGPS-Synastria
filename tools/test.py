"""Run the module's Lua tests inside InstanceGPS's test harness.

    python tools/test.py [path to an InstanceGPS checkout]

Default: an InstanceGPS checkout next to this repo. The module's files load in .toc order, after
InstanceGPS, as they do in game. Exits non-zero if a check fails.
"""
import glob, os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = glob.glob(os.path.join(ROOT, "InstanceGPS_*"))[0]
BASE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "..", "InstanceGPS")
HARNESS = os.path.join(BASE, "test", "run_test.py")
TESTS = [("test_loot.lua", "loot test done"), ("test_attune.lua", "attune test done")]

if not os.path.exists(HARNESS):
    sys.exit("InstanceGPS's test harness not found (%s)" % HARNESS)

toc = open(glob.glob(os.path.join(ADDON, "*.toc"))[0], encoding="utf8").read().splitlines()
modules = os.pathsep.join(os.path.join(ADDON, l.strip()) for l in toc if l.strip() and not l.startswith("#"))
failed = False
for test, done in TESTS:
    p = subprocess.run([sys.executable, HARNESS, "", os.path.join(ROOT, "tools", test)],
                       capture_output=True, text=True, env=dict(os.environ, DN_MODULES=modules))
    out = p.stdout + p.stderr
    results = [l for l in out.splitlines() if l.endswith(("\ttrue", "\tfalse"))]
    for l in results:
        print(("FAIL  " if l.endswith("\tfalse") else "ok    ") + l.split("\t")[0].rstrip(":"))
    if p.returncode or any(l.endswith("\tfalse") for l in results) or done not in out:
        failed = True
        print(out[-3000:])
sys.exit(1 if failed else 0)
