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
print("attuned not marked:", not Has(t, "Item101|r | |cff33ff33attune"))

-- 25-player normal and heroic: their own versions
print("25N version:", Has(Hover(2), "Item111"))
t = Hover(4)
print("25H version:", Has(t, "Item121") and not Has(t, "Item101"))
-- attunable first, then by chance
local first = t:find("Item122", 1, true)
print("attunable first:", first ~= nil and first < t:find("Item123", 1, true) and t:find("Item123", 1, true) < t:find("Item121", 1, true)
	and Has(t, "1 you can still attune"))

-- 10-player heroic with no loot on its version: the normal 10-player loot
print("10H falls back:", Has(Hover(3), "Item101"))

-- Mythic: only the Mythic rows, from the base creature, whatever the difficulty
mythicLevel = 12
t = Hover(2)
print("mythic loot:", Has(t, "Mythic Loot") and Has(t, "Item201") and not Has(t, "Item111") and not Has(t, "Item101"))
mythicLevel = 0

-- a boss with no creature loot
boss = { name = "Chest Boss", npcs = { 99999 } }
print("no loot note:", Has(Hover(1), "may drop a chest"))

-- before the database has loaded
loaded = false
print("not loaded:", Has(Hover(1), "hasn't loaded yet"))
print("loot test done")
