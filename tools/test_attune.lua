-- Attune.lua against a mocked Synastria loot database: the "Left to Attune" tracker row for
-- Icecrown Citadel, its zone lookup (the server's own zone, else one built from the difficulty),
-- grouping by boss, waiting for the database, and recounting after an item is attuned.
-- Run by tools/test.py inside InstanceGPS's test harness (test/run_test.py).
local DN = NS.DN
local ICC = 631

-- 501 drops from Marrowgar's 25 heroic version, 502 from a trash mob, 503 is already attuned
local ZONES = { [ICC + 0x8000 + 8 * 1024] = { 501, 502, 503 }, [ICC + 0x8000 + 5 * 1024] = { 777 } }
local SOURCES = { [501] = { { 0, 0, 37959 } }, [502] = { { 0, 0, 99 } }, [503] = { { 0, 0, 36612 } }, [777] = { { 0, 0, 36612 } } }
local loaded, attuned, fetches = false, { [503] = true }, {}
function ItemLocIsLoaded() return loaded or nil end
function ItemLocGetObjCount() return 0 end
function ItemLocGetAllItemsInZone(z) fetches[#fetches + 1] = z return ZONES[z] end
function ItemLocGetSourceCount(item) return SOURCES[item] and #SOURCES[item] or 0 end
function ItemLocGetSourceAt(item, i) return unpack(SOURCES[item][i]) end
function GetCustomGameData() return 0 end
function GetItemInfoCustom(id) return "Item" .. id, nil, 4 end
function CanAttuneItemHelper() return 1 end
function HasAttunedAnyVariantOfItem(id) return attuned[id] or false end

local lines = {}
local tip = {
	AddLine = function(_, t) lines[#lines + 1] = t end,
	AddDoubleLine = function(_, l, r) lines[#lines + 1] = l .. " | " .. r end,
}
local function Note() return DN.trackerNotes.attune end
local function Has(text, s) return text:find(s, 1, true) ~= nil end

MOCK.now = 1000000
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
local inst = NS.Instances[ICC]
MOCK.inInstance, MOCK.itype, MOCK.instName, MOCK.mapFile, MOCK.diff = true, "raid", inst.name, inst.file, 4
MOCK.Fire("ZONE_CHANGED_NEW_AREA")

-- nothing until the loot database has loaded, then the row appears
MOCK.Tick(1.2)
print("waits for the database:", DN.inst == inst and Note() == nil and #fetches == 0)
loaded = true
MOCK.Tick(1.2)
local n = Note()
print("25H zone built from the difficulty:", fetches[1] == ICC + 0x8000 + 8 * 1024 and #fetches == 1)
print("row counts what's left:", n ~= nil and Has(n.text, "Left to Attune") and Has(n.right, "2"))

-- the tooltip groups by boss (difficulty versions count as the boss), then the rest
n.tooltip(tip)
local t = table.concat(lines, "\n")
local boss, rest = t:find("Lord Marrowgar | 1", 1, true), t:find("Trash, Chests and Others | 1", 1, true)
print("grouped by boss:", boss ~= nil and rest ~= nil and boss < rest and Has(t, "Item501") and not Has(t, "Item503"))

-- attuning an item lowers the count at the next recount (a kill, or every 30 s)
attuned[501] = true
DN:Fire("BOSS_KILLED")
print("recounted:", Has(Note().right, "1"))
attuned[502] = true
MOCK.Tick(31)
print("all done:", Has(Note().right, "none"))

-- the server's own zone for this instance wins, and each zone is fetched once per session
function Custom_GetCurrentZoneOur() return ICC + 0x8000 + 5 * 1024 end
DN:Fire("INSTANCE_CHANGED", inst)
print("row cleared on instance change:", Note() == nil)
MOCK.Tick(0.2)
DN:Fire("INSTANCE_CHANGED", inst)
MOCK.Tick(0.2)
print("server zone used once:", fetches[2] == ICC + 0x8000 + 5 * 1024 and #fetches == 2 and Has(Note().right, "1"))
print("attune test done")
