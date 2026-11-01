"""Run the module's Lua tests inside InstanceGPS's test harness.

    python tools/test.py [path to an InstanceGPS checkout]

Default: an InstanceGPS checkout next to this repo. Exits non-zero if a check fails.
"""
import glob, os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = glob.glob(os.path.join(ROOT, "InstanceGPS_*"))[0]
BASE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "..", "InstanceGPS")
HARNESS = os.path.join(BASE, "test", "run_test.py")

if not os.path.exists(HARNESS):
    sys.exit("InstanceGPS's test harness not found (%s)" % HARNESS)

modules = os.pathsep.join(os.path.join(ADDON, f) for f in ("Overrides.lua", "Difficulties.lua", "Loot.lua"))
p = subprocess.run([sys.executable, HARNESS, "", os.path.join(ROOT, "tools", "test_loot.lua")],
                   capture_output=True, text=True, env=dict(os.environ, DN_MODULES=modules))
out = p.stdout + p.stderr
results = [l for l in out.splitlines() if l.endswith(("\ttrue", "\tfalse"))]
failed = [l for l in results if l.endswith("\tfalse")]
for l in results:
    print(("FAIL  " if l.endswith("\tfalse") else "ok    ") + l.split("\t")[0].rstrip(":"))
if p.returncode or failed or "loot test done" not in out:
    print(out[-3000:])
    sys.exit(1)
