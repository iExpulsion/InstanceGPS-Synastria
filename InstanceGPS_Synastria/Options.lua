-- The module's options: a Synastria page under InstanceGPS's in the game's options window.
local _, ns = ...

ns.opt = InstanceGPS:ModuleOptions("Synastria", {
	{ key = "bossLoot", label = "Boss Loot in Tooltips", default = true,
	  tip = "Hovering a boss in the tracker, or the arrow, lists its loot for this difficulty." },
	{ key = "lootList", label = "Boss Loot List", default = "all",
	  tip = "Which of a boss's drops its tooltip lists.",
	  choices = {
		{ "all", "Show All" },
		{ "attunable", "Show Attunable" },
		{ "unattuned", "Hide Attuned" },
		{ "farm", "Hide Owned Attunes" },
	  } },
	{ key = "markBosses", label = "Mark Bosses With Attunes", default = true,
	  tip = "After a boss's name in the tracker, how many of its drops you can still attune and don't have yet." },
	{ key = "attuneRow", label = "Left to Attune Row", default = true,
	  tip = "A row under the boss list counting what's left to attune in this instance." },
	{ key = "trashRow", label = "Trash Drops Row", default = true,
	  tip = "A row under the boss list naming the trash that drops what's left to attune." },
})
