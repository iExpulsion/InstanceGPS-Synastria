"""Check the module before release.

    python tools/check.py [path to InstanceGPS's Data.lua]

- Overrides.lua must load and call InstanceGPS:Override with the format in InstanceGPS's
  docs/MODULES.md (unknown keys and wrong types are errors).
- With InstanceGPS's Data.lua (default: a checkout next to this repo), boss names are checked
  against it: a boss that isn't there is a custom one and needs npcs and a position.
- Built routes (Routes.lua) made from an older version of an instance than that Data.lua are
  reported, so they can be rebuilt (InstanceGPS's build.py --module).
"""
import glob, hashlib, os, re, sys

from lupa import lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = glob.glob(os.path.join(ROOT, "InstanceGPS_*"))[0]
BASE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "..", "InstanceGPS", "InstanceGPS", "Data.lua")

errors, warnings = [], []


def err(msg):
    errors.append(msg)


def py(v):
    if hasattr(v, "items"):
        d = {k: py(x) for k, x in v.items()}
        if d and all(isinstance(k, int) for k in d) and sorted(d) == list(range(1, len(d) + 1)):
            return [d[k] for k in range(1, len(d) + 1)]
        return d
    return v


L = lua51.LuaRuntime(unpack_returned_tuples=True)
L.execute("calls = {} InstanceGPS = {} function InstanceGPS:Override(name, t) calls[#calls + 1] = { name = name, t = t } end")
try:
    L.execute(open(os.path.join(ADDON, "Overrides.lua"), encoding="utf8").read())
except Exception as e:
    sys.exit("Overrides.lua doesn't load: %s" % e)
calls = py(L.globals().calls) or []
if len(calls) != 1 or not isinstance(calls[0].get("name"), str) or not isinstance(calls[0].get("t"), (dict, list)):
    sys.exit('Overrides.lua must call InstanceGPS:Override("<Server name>", { ... }) once')
data = calls[0]["t"] if isinstance(calls[0]["t"], dict) else {}

# InstanceGPS's instances and boss names, when available
base = {}
base_text = None
if os.path.exists(BASE):
    base_text = open(BASE, encoding="utf8").read()
    ns = L.eval("{}")
    L.eval("function(src, ns) local f = assert(loadstring(src)) f('InstanceGPS', ns) end")(base_text, ns)
    for mid, inst in ns.Instances.items():
        base[mid] = {"name": inst.name, "bosses": {b.name for b in inst.bosses.values()}}
else:
    warnings.append("InstanceGPS's Data.lua not found (%s): boss names not checked" % BASE)

NUM = (int, float)
BOSS_FIELDS = {"name": str, "npcs": list, "spell": int, "yells": list, "noDeath": bool, "friendly": bool,
               "diff": int, "x": NUM, "y": NUM, "z": NUM, "f": int, "after": str, "wing": str, "id": int, "r": NUM}
INSTANCE_KEYS = {"bosses", "hints", "removeHints", "paths", "order", "doors", "links"}

for mid, t in data.items():
    where = "[%s]" % mid
    if not isinstance(mid, int):
        err("%s: instances are keyed by map ID (a number)" % where)
        continue
    known = base.get(mid)
    if base and not known:
        err("%s: InstanceGPS has no instance with this map ID" % where)
    if known:
        where = "[%d] %s" % (mid, known["name"])
    if t is False:
        continue
    if not isinstance(t, dict):
        err("%s: must be false or a table" % where)
        continue
    for k in t:
        if k not in INSTANCE_KEYS:
            err("%s: unknown key %r (known: %s)" % (where, k, ", ".join(sorted(INSTANCE_KEYS))))
    for name, v in (t.get("bosses") or {}).items():
        w = "%s boss %r" % (where, name)
        if v is False:
            if known and name not in known["bosses"]:
                err("%s: removed, but InstanceGPS has no boss by that name here" % w)
            continue
        if not isinstance(v, dict):
            err("%s: must be false or a table" % w)
            continue
        for f, val in v.items():
            want = BOSS_FIELDS.get(f)
            if want is None:
                err("%s: unknown field %r" % (w, f))
            elif not isinstance(val, want) or isinstance(val, bool) and want is not bool:
                err("%s: %s has the wrong type" % (w, f))
        if ("x" in v) != ("y" in v):
            err("%s: x and y go together" % w)
        if known and name not in known["bosses"]:
            # a custom boss
            if not v.get("npcs") or "x" not in v:
                err("%s: not one of InstanceGPS's bosses here, so it's a custom one and needs npcs, x and y" % w)
            if v.get("after") and v["after"] not in known["bosses"] and v["after"] not in t.get("bosses", {}):
                err("%s: comes after %r, which isn't a boss here" % (w, v["after"]))
    for i, h in enumerate(t.get("hints") or [], 1):
        if not isinstance(h, dict) or not isinstance(h.get("x"), NUM) or not isinstance(h.get("y"), NUM) \
                or not isinstance(h.get("text"), str):
            err("%s hint %d: needs x, y and text" % (where, i))
    for s in t.get("removeHints") or []:
        if not isinstance(s, str):
            err("%s removeHints: list the start of each hint's text" % where)
    for name, p in (t.get("paths") or {}).items():
        w = "%s path to %r" % (where, name)
        pts = p.get("points") if isinstance(p, dict) else None
        if not isinstance(pts, list) or len(pts) < 6 or len(pts) % 3 or not all(isinstance(v, NUM) for v in pts):
            err("%s: points must be x, y, level triples" % w)
        if known and name not in known["bosses"] and name not in (t.get("bosses") or {}):
            err("%s: not a boss here" % w)

# built routes against the current InstanceGPS data
routes = os.path.join(ADDON, "Routes.lua")
if os.path.exists(routes) and base_text:
    m = re.search(r"^-- base: (.*)$", open(routes, encoding="utf8").read(), re.M)
    built = dict(kv.split("=") for kv in m.group(1).split()) if m else {}
    blocks = {int(k): b for k, b in re.findall(r"\n \[(\d+)\] = \{(.*?)\n \},", base_text, re.S)}
    for k, h in built.items():
        now = hashlib.sha1(blocks[int(k)].encode("utf8")).hexdigest()[:12] if int(k) in blocks else "none"
        if now != h:
            name = base.get(int(k), {}).get("name", k)
            warnings.append("Routes.lua: %s has changed in InstanceGPS since its routes were built; rebuild them "
                            "(InstanceGPS's tools/build.py --module)" % name)

for w in warnings:
    print(("::warning::" if os.environ.get("GITHUB_ACTIONS") else "warning: ") + w)
for e in errors:
    print(("::error::" if os.environ.get("GITHUB_ACTIONS") else "error: ") + e)
n = sum(1 for t in data.values() if t is not None)
print("%s: %d instance(s) changed, %d error(s), %d warning(s)" % (calls[0]["name"], n, len(errors), len(warnings)))
sys.exit(1 if errors else 0)
