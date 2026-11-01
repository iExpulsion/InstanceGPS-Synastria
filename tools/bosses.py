"""Report where Synastria's bosses differ from InstanceGPS's, as leads for Overrides.lua.

    python tools/bosses.py [path to SynastriaData] [path to an InstanceGPS checkout]

Compares every boss InstanceGPS knows (and the custom ones in Overrides.lua) with the creature
locations Synastria's client data lists (SynastriaData's creature-spawns.csv). Defaults: both
checkouts next to this repo. Nothing is written; the report is for a person to check in game.

Synastria lists one location for creatures that a script summons too, so a difference alone
doesn't mean a boss moved. The report sorts what it finds by how sure it is:

- MOVED: a boss AzerothCore spawns in place, which Synastria lists somewhere else. Needs the
  AzerothCore world database dump that SynastriaData's verify tool reads (tools/verify/sqldump.py);
  without it these show as DIFFERS.
- DIFFERS: Synastria's location is away from InstanceGPS's, for a boss placed by a script
  (InstanceGPS's tools/boss_fixups.json), or when there's no AzerothCore data to tell.
- MISSING: a boss AzerothCore spawns in place that Synastria lists nowhere in the instance.
- CUSTOM: a creature that isn't in AzerothCore (or, without its data, one in Synastria's custom
  ID range), placed in an instance, that drops an epic: a custom boss, or an event creature.

Patrols count: a boss whose Synastria patrol passes InstanceGPS's spot hasn't moved.

Already-overridden bosses are compared with their override, and creatures that are already a
boss here are left out of CUSTOM.
"""
import collections, csv, glob, json, math, os, re, sys

from lupa import lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = glob.glob(os.path.join(ROOT, "InstanceGPS_*"))[0]
SYN = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "..", "SynastriaData")
BASE = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "..", "InstanceGPS")

NEAR = 5          # yards: a location this close to InstanceGPS's is the same spot
SAME = 1          # yards: Synastria's truncated coordinates against a stock spawn
CUSTOM_IDS = 80000
EPIC = 4          # item quality: a creature that drops one is boss-like, not an add

# Leads already checked in game, left out of the report: creature ID -> what it turned out to be
CHECKED = {
    80020: "Lord Jaraxxus: a player's summoned guardian, not a boss (Naxxramas, 2026-11-01)",
    28921: "Hadronox: InstanceGPS's position is right (Azjol-Nerub heroic, 2026-11-01)",
}


def rows(*path):
    with open(os.path.join(SYN, "data", *path), encoding="utf8") as f:
        return list(csv.DictReader(f))


def lua_tables():
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    ns = L.eval("{}")
    L.eval("function(src, ns) local f = assert(loadstring(src)) f('InstanceGPS', ns) end")(
        open(os.path.join(BASE, "InstanceGPS", "Data.lua"), encoding="utf8").read(), ns)
    L.execute("calls = {} InstanceGPS = {} function InstanceGPS:Override(name, t) calls[#calls + 1] = t end")
    L.execute(open(os.path.join(ADDON, "Overrides.lua"), encoding="utf8").read())
    return ns.Instances, L.globals().calls


def lst(t):
    return [t[k] for k in sorted(t.keys())] if t else []


def load_stock():
    verify = os.path.join(SYN, "tools", "verify")
    if os.path.exists(os.path.join(verify, "sqldump.py")):
        sys.path.insert(0, verify)
        try:
            import sqldump
            spawns = collections.defaultdict(list)
            for r in sqldump.load("creature"):
                spawns[r.get("id1", r.get("id"))].append(
                    (r["map"], math.trunc(r["position_x"]), math.trunc(r["position_y"])))
            return spawns, {r["entry"] for r in sqldump.load("creature_template")}
        except (OSError, AttributeError) as e:
            print("AzerothCore data not available (%s): MOVED shows as DIFFERS\n" % e)
    return None, None


def main():
    instances, calls = lua_tables()
    fixed = set(json.load(open(os.path.join(BASE, "tools", "boss_fixups.json"), encoding="utf8"))["positions"])
    creatures = {int(r["id"]): r for r in rows("world", "creatures.csv")}
    spawns = collections.defaultdict(list)
    for r in rows("world", "creature-spawns.csv"):
        spawns[int(r["id"])].append((int(r["map"]), int(r["x"]), int(r["y"])))
    # patrol points, by creature and the number of its spawn: a patrol passing InstanceGPS's spot isn't a move
    patrol = collections.defaultdict(list)
    for r in rows("world", "creature-waypoints.csv"):
        patrol[int(r["id"]), int(r["spawn"])].append((int(r["x"]), int(r["y"])))
    quality = {int(r["id"]): int(r["quality"] or 0) for r in rows("items", "items.csv")}
    drops, epics = collections.Counter(), collections.Counter()
    for r in rows("sources", "creature-drops.csv"):
        if r["source_kind"] == "creature":
            drops[int(r["source_id"])] += 1
            epics[int(r["source_id"])] += quality.get(int(r["item_id"]), 0) >= EPIC
    stock, stock_ids = load_stock()

    overrides = collections.defaultdict(dict)
    for t in calls.values():
        for mid, inst in t.items():
            for name, b in (inst.bosses.items() if inst and inst.bosses else []):
                overrides[mid][name] = b

    found = collections.defaultdict(list)
    boss_npcs = set()
    for mid in sorted(instances.keys()):
        inst = instances[mid]
        bosses = [(b.name, b, b.id) for b in lst(inst.bosses)]
        bosses += [(name, b, None) for name, b in overrides[mid].items()
                   if b and name not in {n for n, _, _ in bosses}]
        for name, b, eid in bosses:
            o = overrides[mid].get(name)
            if o is False:
                continue
            npcs = [int(n) for n in lst((o and o.npcs) or b.npcs)]
            boss_npcs.update(npcs)
            for n in npcs:
                boss_npcs.update(int(creatures[n][k]) for k in ("difficulty_entry_1", "difficulty_entry_2",
                                 "difficulty_entry_3") if n in creatures and creatures[n][k])
            x, y = (o.x, o.y) if o and o.x is not None else (b.x, b.y)
            if x is None or any(n in CHECKED for n in npcs):
                continue
            here = [(sx, sy) for n in npcs for (m, sx, sy) in spawns.get(n, []) if m == mid]
            walked = here + [p for n in npcs for i, (m, _, _) in enumerate(spawns.get(n, [])) if m == mid
                             for p in patrol[n, i]]
            static = [(sx, sy) for n in npcs for (m, sx, sy) in (stock or {}).get(n, []) if m == mid]
            scripted = eid is not None and str(eid) in fixed
            d = min((math.hypot(sx - x, sy - y) for sx, sy in walked), default=None)
            if here and d > NEAR:
                off_stock = static and not any(abs(sx - tx) <= SAME and abs(sy - ty) <= SAME
                                               for sx, sy in here for tx, ty in static)
                kind = "MOVED" if off_stock and not scripted else "DIFFERS"
                sx, sy = min(here, key=lambda p: math.hypot(p[0] - x, p[1] - y))
                d = math.hypot(sx - x, sy - y)
                why = ("placed by a script in InstanceGPS" if scripted
                       else "off AzerothCore's spawn" if off_stock
                       else "no AzerothCore data to compare" if stock is None
                       else "AzerothCore doesn't spawn it in place" if not static
                       else "on another of AzerothCore's spawns")
                found[kind].append((mid, inst.name, '%s: Synastria %d,%d, InstanceGPS %.0f,%.0f (%d yd; %s)'
                                    % (name, sx, sy, x, y, d, why),
                                    '["%s"] = { x = %d, y = %d },' % (name, sx, sy) if kind == "MOVED" else None))
            elif not here and static and not scripted:
                found["MISSING"].append((mid, inst.name, "%s: AzerothCore spawns it at %d,%d; Synastria lists it nowhere here"
                                         % (name, static[0][0], static[0][1]), None))

    custom = collections.defaultdict(list)
    for cid, pts in spawns.items():
        c = creatures.get(cid)
        new = cid not in stock_ids if stock_ids is not None else cid >= CUSTOM_IDS
        if c and new and cid not in boss_npcs and cid not in CHECKED and epics[cid] > 0:
            for m, sx, sy in pts:
                if m in instances.keys():
                    custom[m].append((cid, c["name"], sx, sy, drops[cid], epics[cid]))
    for mid in sorted(custom):
        for cid, name, sx, sy, n, e in custom[mid]:
            found["CUSTOM"].append((mid, instances[mid].name, "%s (%d) at %d,%d, drops %d items (%d epic)"
                                    % (name, cid, sx, sy, n, e),
                                    '["%s"] = { npcs = { %d }, x = %d, y = %d, after = "?" },' % (name, cid, sx, sy)))

    for kind in ("MOVED", "CUSTOM", "MISSING", "DIFFERS"):
        print("%s (%d)" % (kind, len(found[kind])))
        for mid, iname, text, snippet in found[kind]:
            print("  [%d] %s: %s" % (mid, iname, text))
            if snippet:
                print("        " + snippet)
        print()
    print("Check each in game before it goes in Overrides.lua. A position without f keeps the boss's map level.")


if __name__ == "__main__":
    main()
