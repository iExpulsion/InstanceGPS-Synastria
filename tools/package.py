"""Zip the module for release: python tools/package.py [output folder]

Writes <output>/InstanceGPS_Synastria-<version>.zip with a top-level InstanceGPS_Synastria/ folder
(extract it into Interface/AddOns): the .toc, the files it loads, the README and the LICENSE.
"""
import glob, os, re, sys, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = glob.glob(os.path.join(ROOT, "InstanceGPS_*"))[0]
NAME = os.path.basename(ADDON)
DIST = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "dist")

lines = open(os.path.join(ADDON, NAME + ".toc"), encoding="utf8").read().splitlines()
version = next((m.group(1) for m in (re.match(r"##\s*Version:\s*(\S+)", l) for l in lines) if m), "0")
files = [NAME + ".toc"] + [l.strip() for l in lines if l.strip() and not l.startswith("#")]
missing = [f for f in files if not os.path.isfile(os.path.join(ADDON, f))]
if missing:
    sys.exit("Not packaged, missing: " + ", ".join(missing))
os.makedirs(DIST, exist_ok=True)
out = os.path.abspath(os.path.join(DIST, "%s-%s.zip" % (NAME, version)))
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for f in files:
        z.write(os.path.join(ADDON, f), NAME + "/" + f)
    for f in ("README.md", "LICENSE"):
        z.write(os.path.join(ROOT, f), NAME + "/" + f)
print("%s  (%d files)" % (out, len(files) + 2))
