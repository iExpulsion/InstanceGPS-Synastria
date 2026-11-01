# InstanceGPS: Synastria

Synastria's changes for [InstanceGPS](https://github.com/iExpulsion/InstanceGPS), the dungeon and raid GPS for WoW 3.3.5a. InstanceGPS is built from AzerothCore's data; this module adjusts it where Synastria differs (bosses moved or added, hints, routes).

## Installing

1. Install [InstanceGPS](https://github.com/iExpulsion/InstanceGPS/releases/latest) first.
2. Download `InstanceGPS_Synastria-<version>.zip` from the [latest release](../../releases/latest) and extract it into `World of Warcraft\Interface\AddOns`, next to the `InstanceGPS` folder.
3. Restart the game. The InstanceGPS options panel title reads "InstanceGPS ... + Synastria".

## What's Changed

- **Boss loot in the tooltips.** Hover a boss in the tracker, or the arrow, for that boss's drops on your current difficulty, from Synastria's own loot database: in Mythic, its Mythic drops. Items your character can still attune are listed first and marked "Attune", with a count at the end; ones already in your bags or bank read "Have".
- **What's left to attune here.** A "Left to Attune" row under the tracker's boss list counts the items from this instance and difficulty your character can still attune. Hover it to see them boss by boss, then the trash, chests and other sources.
- **Trash worth killing.** A "Trash Drops" row counts the trash mobs here that drop something your character can still attune. Hover it for each mob's items and drop chances, the mobs with the most first.

Both rows find the items the way Synastria's own item tracker does, with its filter settings, so their count matches the tracker's. `/igpssyn` prints what they're counting, boss by boss.

### Options

Under InstanceGPS in the game's options window, the Synastria page has:

- **Boss Loot in Tooltips:** the loot list in boss tooltips (on).
- **Boss Loot List:** which drops it lists: Show All (the default), Show Attunable (items your character can attune), Hide Attuned (only ones you haven't attuned yet) or Hide Owned Attunes (only what's left to farm, leaving out ones in your bags or bank).
- **Mark Bosses With Attunes:** a green count after a boss's name in the tracker, like "Grobbulus (3)": how many of its drops you can still attune and don't have yet. Bosses you've killed this run lose theirs (on).
- **Left to Attune Row** and **Trash Drops Row:** the two rows under the boss list (on).
- **Routes:** nothing yet. As far as we know, InstanceGPS's AzerothCore routes fit Synastria as they are. If you find a place where they don't, see below.

## Contributing

Route and boss changes live in [`InstanceGPS_Synastria/Overrides.lua`](InstanceGPS_Synastria/Overrides.lua). The format is in InstanceGPS's [module guide](https://github.com/iExpulsion/InstanceGPS/blob/main/docs/MODULES.md).

- **A route that goes the wrong way:** record the right one in game with `/igps record start`, walk it (each boss kill ends a leg), then `/igps record export` and paste the result into `Overrides.lua`.
- **A boss that's moved, renamed, added or gone, or a hint to add or fix:** edit `Overrides.lua` by hand.
- **Leads from the client's data:** `python tools/bosses.py` compares InstanceGPS's bosses with where Synastria's client data puts them (from a SynastriaData checkout next to this repo) and lists bosses that look moved, missing or custom, with lines to paste into `Overrides.lua`. With the AzerothCore world database dump that SynastriaData's verify tool reads, it can tell a real move from a scripted boss's location. Check each lead in game first.

Open a pull request saying where each change comes from (what you saw in game, a patch note). `python tools/check.py` checks the file; the same check runs on every pull request.

The loot tooltip is [`Loot.lua`](InstanceGPS_Synastria/Loot.lua), the attune row [`Attune.lua`](InstanceGPS_Synastria/Attune.lua). Both ask the game for the loot, so it stays current after server patches. The one thing the game can't tell it is which creature holds a boss's heroic or 25-player drops (Lord Marrowgar's 25 heroic loot is on "Lord Marrowgar (3)"). [`Difficulties.lua`](InstanceGPS_Synastria/Difficulties.lua) lists those creature IDs. `python tools/difficulties.py` regenerates it from a SynastriaData checkout next to this repo (extracted from the client's files) and InstanceGPS's `Data.lua`; run it after a client patch, or when InstanceGPS's bosses change. `python tools/test.py` tests `Loot.lua` with InstanceGPS's test harness (an InstanceGPS checkout next to this repo).

## Releasing

Raise `## Version` in `InstanceGPS_Synastria/InstanceGPS_Synastria.toc` and push: GitHub Actions checks the module and publishes a release with the zip.

Routes for moved or added bosses can be worked out properly (instead of the rough routes the game makes) with InstanceGPS's build tools: `python build.py --module <path to this repo> ...` writes `InstanceGPS_Synastria/Routes.lua`. See InstanceGPS's [BUILDING.md](https://github.com/iExpulsion/InstanceGPS/blob/main/docs/BUILDING.md).

## License

GPL-2.0, like InstanceGPS. See [LICENSE](LICENSE).

Made by Expulsion.
