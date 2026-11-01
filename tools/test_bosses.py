"""Test tools/bosses.py on a made-up instance: a moved boss, one that patrols through its spot,
a scripted one, one Synastria lacks, a custom boss and a custom add, with and without
AzerothCore's data. Run by tools/test.py; prints one "name: true/false" line per check."""
import os, subprocess, sys, tempfile, textwrap

HERE = os.path.dirname(os.path.abspath(__file__))

DATA_LUA = textwrap.dedent("""\
    local _, ns = ...
    ns.Instances = {
     [999] = { name="Test Keep", type="party", bosses={
       {name="Mover", id=1, diff=1, npcs={101}, x=0, y=0, f=1},
       {name="Walker", id=2, diff=1, npcs={102}, x=100, y=0, f=1},
       {name="Summoned", id=3, diff=1, npcs={103}, x=200, y=0, f=1},
       {name="Gone", id=4, diff=1, npcs={104}, x=300, y=0, f=1},
       {name="Stays", id=5, diff=1, npcs={105}, x=400, y=0, f=1},
     }, routes={} },
    }
""")
FILES = {
    "data/world/creatures.csv": "id,name,item_sources,difficulty_entry_1,difficulty_entry_2,difficulty_entry_3\n"
        "101,Mover,1,,,\n102,Walker,1,,,\n103,Summoned,1,,,\n104,Gone,1,,,\n105,Stays,1,,,\n"
        "80001,Custom Boss,1,,,\n80002,Custom Add,1,,,\n",
    "data/world/creature-spawns.csv": "id,name,map,map_name,x,y,waypoints\n"
        "101,Mover,999,Test Keep,60,0,0\n102,Walker,999,Test Keep,150,0,2\n103,Summoned,999,Test Keep,260,0,0\n"
        "105,Stays,999,Test Keep,400,0,0\n80001,Custom Boss,999,Test Keep,500,10,0\n80002,Custom Add,999,Test Keep,510,10,0\n",
    "data/world/creature-waypoints.csv": "id,name,spawn,step,x,y,flag\n102,Walker,0,0,150,0,0\n102,Walker,0,1,100,1,0\n",
    "data/items/items.csv": "id,name,quality\n1,Epic Sword,4\n2,Linen Scrap,1\n",
    "data/sources/creature-drops.csv": "item_id,item_name,method,source_kind,source_id,source_name,chance_pct,per_1000,mythic\n"
        "1,Epic Sword,creature_drop,creature,80001,Custom Boss,20,200,0\n2,Linen Scrap,creature_drop,creature,80002,Custom Add,20,200,0\n",
    "tools/verify/sqldump.py": textwrap.dedent("""\
        def load(table):
            if table == "creature_template":
                return [{"entry": i} for i in (101, 102, 103, 104, 105)]
            return [{"id1": i, "map": 999, "position_x": x, "position_y": 0.0}
                    for i, x in ((101, 0.0), (102, 100.0), (104, 300.0), (105, 400.0))]
    """),
}


def run(stock):
    with tempfile.TemporaryDirectory() as tmp:
        syn, base = os.path.join(tmp, "syn"), os.path.join(tmp, "base")
        for path, text in FILES.items():
            if stock or "verify" not in path:
                os.makedirs(os.path.dirname(os.path.join(syn, path)), exist_ok=True)
                open(os.path.join(syn, path), "w", encoding="utf8").write(text)
        os.makedirs(os.path.join(base, "InstanceGPS"))
        os.makedirs(os.path.join(base, "tools"))
        open(os.path.join(base, "InstanceGPS", "Data.lua"), "w", encoding="utf8").write(DATA_LUA)
        open(os.path.join(base, "tools", "boss_fixups.json"), "w", encoding="utf8").write('{"positions": {"3": {}}}')
        p = subprocess.run([sys.executable, os.path.join(HERE, "bosses.py"), syn, base], capture_output=True, text=True)
        return p.stdout + p.stderr


def section(out, kind):
    return out.split(kind + " (", 1)[1].split("\n\n", 1)[0]


def check(name, ok):
    print("%s:\t%s" % (name, "true" if ok else "false"))


out = run(True)
# a static boss Synastria lists elsewhere is MOVED, with an override to paste
check("moved", "Mover: Synastria 60,0" in section(out, "MOVED") and '["Mover"] = { x = 60, y = 0 },' in out)
# a patrol through InstanceGPS's spot isn't a move
check("patrol not moved", "Walker" not in out)
# a scripted boss only DIFFERS
check("scripted differs", "Summoned" in section(out, "DIFFERS") and "Summoned" not in section(out, "MOVED"))
# a stock spawn Synastria lacks is MISSING; an unchanged one isn't listed
check("missing", "Gone" in section(out, "MISSING") and "Stays" not in out)
# a new creature with an epic drop is CUSTOM; one with only trash loot isn't
check("custom", "Custom Boss (80001)" in section(out, "CUSTOM") and "Custom Add" not in out)

out = run(False)
# without AzerothCore's data, moves show as DIFFERS and custom bosses come from the custom ID range
check("no stock", "MOVED (0)" in out and "Mover" in section(out, "DIFFERS") and "Custom Boss (80001)" in out)
print("bosses test done")
