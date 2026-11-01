-- Loot.lua against a mocked Synastria loot database: which creature's loot each difficulty uses,
-- Mythic-only drops, attunable items first, and the tooltip before the database has loaded.
-- Run by tools/test.py inside InstanceGPS's test harness (test/run_test.py).
local DN = NS.DN

-- Marrowgar (36612) and his versions: 37957 25N, 37958 10H (no loot of its own here), 37959 25H
local LOOT = {
	[36612] = { { 0, 101, 20 }, { 0, 102, 15 }, { 20, 201, 30 }, { 13, 301, 50 } },
	[37957] = { { 0, 111, 20 } },
	[37959] = { { 0, 121, 20 }, { 0, 122, 25 }, { 0, 123, 100 } },
}
local loaded, mythicLevel, attunable, attuned = true, 0, { [122] = true, [101] = true }, { [101] = true }
function ItemLocIsLoaded() return loaded or nil end
function ItemLocGetObjCount(_, id) return LOOT[id] and #LOOT[id] or 0 end
function ItemLocSetObjSort() end
function ItemLocGetObjAt(_, id, i) local r = LOOT[id][i] return r[1], r[2], r[3], r[3] * 10 end
function GetCustomGameData(a, b) return a == 12 and b == 11 and mythicLevel or 0 end
function GetItemInfoCustom(id) return "Item" .. id, nil, 4 end
function CanAttuneItemHelper(id) return attunable[id] and 1 or 0 end
function HasAttunedAnyVariantOfItem(id) return attuned[id] or false end
local owned = {}
function GetItemCount(id) return owned[id] and 1 or 0 end
ITEM_QUALITY_COLORS = { [4] = { hex = "|cffa335ee" } }

local lines
local tip = {
	AddLine = function(_, t) lines[#lines + 1] = t end,
	AddDoubleLine = function(_, l, r) lines[#lines + 1] = l .. " | " .. r end,
}
local boss = { name = "Lord Marrowgar", npcs = { 36612 } }
local function Hover(diff)
	MOCK.diff = diff
	DN:Fire("INSTANCE_CHANGED")
	lines = {}
	DN:Fire("BOSS_TOOLTIP", boss, tip)
	return table.concat(lines, "\n")
end
local function Has(text, s) return text:find(s, 1, true) ~= nil end

MOCK.Fire("ADDON_LOADED", "InstanceGPS")

-- 10-player normal: the base creature's drops, without skinning or Mythic-only rows
local t = Hover(1)
print("10N base loot:", Has(t, "Item101") and Has(t, "Item102") and not Has(t, "Item201") and not Has(t, "Item301"))
-- an already attuned item isn't marked
print("attuned not marked:", not Has(t, "Item101|r | |cff33ff33Attune"))

-- 25-player normal and heroic: their own versions
print("25N version:", Has(Hover(2), "Item111"))
t = Hover(4)
print("25H version:", Has(t, "Item121") and not Has(t, "Item101"))
-- attunable first, then by chance
local first = t:find("Item122", 1, true)
print("attunable first:", first ~= nil and first < t:find("Item123", 1, true) and t:find("Item123", 1, true) < t:find("Item121", 1, true)
	and Has(t, "1 Still to Attune"))
-- one already in the bags reads "Have", not "Attune", and isn't counted
owned[122] = true
t = Hover(4)
owned[122] = nil
print("have not counted:", Has(t, "Item122|r | |cff888888Have") and not Has(t, "Item122|r | |cff33ff33Attune")
	and not Has(t, "Still to Attune"))

-- 10-player heroic with no loot on its version: the normal 10-player loot
print("10H falls back:", Has(Hover(3), "Item101"))

-- Mythic: only the Mythic rows, from the base creature, whatever the difficulty
mythicLevel = 12
t = Hover(2)
print("mythic loot:", Has(t, "Mythic Loot") and Has(t, "Item201") and not Has(t, "Item111") and not Has(t, "Item101"))
mythicLevel = 0

-- a boss with no creature loot
boss = { name = "Chest Boss", npcs = { 99999 } }
print("no loot note:", Has(Hover(1), "No Creature Loot"))

-- before the database has loaded
loaded = false
print("not loaded:", Has(Hover(1), "hasn't loaded yet"))
-- The Boss Loot List option, on 25H: 124 isn't attunable, 121 is but is attuned, 123 is in the
-- bags, 122 is still to farm
LOOT[37959][4] = { 0, 124, 10 }
loaded, attunable[121], attunable[123], attuned[121], owned[123] = true, true, true, true, true
boss = { name = "Lord Marrowgar", npcs = { 36612 } }
local function Listed(mode)
	DN.db.modules = { Synastria = { lootList = mode } }
	local text = Hover(4)
	local got = {}
	for _, id in ipairs({ 121, 122, 123, 124 }) do
		if Has(text, "Item" .. id .. "|r") then got[#got + 1] = id end
	end
	return table.concat(got, ","), text
end
print("show all:", (Listed("all")) == "121,122,123,124")
print("show attunable:", (Listed("attunable")) == "121,122,123")
print("hide attuned:", (Listed("unattuned")) == "122,123")
local farm, text = Listed("farm")
print("hide owned attunes:", farm == "122" and Has(text, "1 Still to Attune"))
attunable[122] = nil
print("nothing to show:", Has(select(2, Listed("farm")), "Nothing to Show"))
-- Boss Loot in Tooltips off: no loot lines at all
DN.db.modules = { Synastria = { bossLoot = false } }
print("loot off:", Hover(4) == "")
DN.db.modules = nil
print("loot test done")
