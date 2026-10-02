# InstanceGPS: Synastria

Synastria's changes for [InstanceGPS](https://github.com/iExpulsion/InstanceGPS), the dungeon and raid GPS for WoW 3.3.5a. InstanceGPS is built from AzerothCore's data; this module adjusts it where Synastria differs (bosses moved or added, hints, routes).

## Installing

1. Install [InstanceGPS](https://github.com/iExpulsion/InstanceGPS/releases/latest) first.
2. Download `InstanceGPS_Synastria-<version>.zip` from the [latest release](../../releases/latest) and extract it into `World of Warcraft\Interface\AddOns`, next to the `InstanceGPS` folder.
3. Restart the game. The InstanceGPS options panel title reads "InstanceGPS ... + Synastria".

## What's Changed

Nothing yet: as far as we know, InstanceGPS's AzerothCore routes fit Synastria as they are. If you find a place where they don't, see below.

## Contributing

Every change lives in [`InstanceGPS_Synastria/Overrides.lua`](InstanceGPS_Synastria/Overrides.lua). The format is in InstanceGPS's [module guide](https://github.com/iExpulsion/InstanceGPS/blob/main/docs/MODULES.md).

- **A route that goes the wrong way:** record the right one in game with `/igps record start`, walk it (each boss kill ends a leg), then `/igps record export` and paste the result into `Overrides.lua`.
- **A boss that's moved, renamed, added or gone, or a hint to add or fix:** edit `Overrides.lua` by hand.

Open a pull request saying where each change comes from (what you saw in game, a patch note). `python tools/check.py` checks the file; the same check runs on every pull request.

## Releasing

Raise `## Version` in `InstanceGPS_Synastria/InstanceGPS_Synastria.toc` and push: GitHub Actions checks the module and publishes a release with the zip.

Routes for moved or added bosses can be worked out properly (instead of the rough routes the game makes) with InstanceGPS's build tools: `python build.py --module <path to this repo> ...` writes `InstanceGPS_Synastria/Routes.lua`. See InstanceGPS's [BUILDING.md](https://github.com/iExpulsion/InstanceGPS/blob/main/docs/BUILDING.md).

## License

GPL-2.0, like InstanceGPS. See [LICENSE](LICENSE).

Made by Expulsion.
