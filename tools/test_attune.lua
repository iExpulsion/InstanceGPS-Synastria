-- Attune.lua against a mocked Synastria loot database: the "Left to Attune" tracker row for
-- Icecrown Citadel, its zone lookup (the server's own zone, else one built from the difficulty),
-- grouping by boss, waiting for the database, and recounting after an item is attuned.
-- Run by tools/test.py inside InstanceGPS's test harness (test/run_test.py).
local DN = NS.DN
local ICC = 631

-- 501 drops from Marrowgar's 25 heroic version, 502 from a trash mob, 503 is already attuned,
-- 504 from a mob in another zone first and a trash mob here second
local ZONES = { [ICC + 0x8000 + 8 * 1024] = { 501, 502, 503, 504 }, [ICC + 0x8000 + 5 * 1024] = { 777 } }
local HERE = "Icecrown Citadel 25H"
local SOURCES = {
	[501] = { { 0, 0, 37959, 20, 200, "Lord Marrowgar (3)", HERE } },
	[502] = { { 0, 0, 99, 5, 50, "Deathbound Ward", HERE } },
	[503] = { { 0, 0, 36612, 20, 200, "Lord Marrowgar", HERE } },
	[504] = { { 0, 0, 555, 50, 500, "World Mob", "Elwynn Forest" }, { 0, 0, 98, 3, 30, "Frostwarden Handler", HERE } },
	[777] = { { 0, 0, 36612, 20, 200, "Lord Marrowgar", HERE } },
}
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
local owned = {}
function GetItemCount(id) return owned[id] and 1 or 0 end

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
print("row counts what's left:", n ~= nil and Has(n.text, "Left to Attune") and Has(n.right, "3"))

-- the tooltip groups by boss (difficulty versions count as the boss), then the rest
n.tooltip(tip)
local t = table.concat(lines, "\n")
local boss, rest = t:find("Lord Marrowgar | 1", 1, true), t:find("Trash, Chests and Others | 2", 1, true)
print("grouped by boss:", boss ~= nil and rest ~= nil and boss < rest and Has(t, "Item501") and not Has(t, "Item503"))

-- the trash row names the mobs that drop them, with their chances; the instance's own source wins
local trash = DN.trackerNotes["attune trash"]
lines = {}
if trash then trash.tooltip(tip) end
t = table.concat(lines, "\n")
print("trash row:", trash ~= nil and Has(trash.right, "2") and Has(t, "Deathbound Ward | 1") and Has(t, "Item502|r | 5.0%")
	and Has(t, "Frostwarden Handler") and not Has(t, "World Mob") and not Has(t, "Lord Marrowgar"))

-- bosses with something left to attune get a count after their name, until they're killed
local marks = DN.bossMarks.attune
local marrowgar = inst.bosses[1]
local marked = marks ~= nil and marks[marrowgar] ~= nil and marks[marrowgar]:find("(1)", 1, true) ~= nil
DN:MarkKilled(marrowgar, "manual")
local gone = DN.bossMarks.attune[marrowgar] == nil
DN:UnmarkKilled(marrowgar)
print("boss marks:", marked and gone and DN.bossMarks.attune[marrowgar] ~= nil)
DN.db.modules = { Synastria = { markBosses = false } }
DN:Fire("MODULE_OPTION", "Synastria", "markBosses", false)
print("marks option:", DN.bossMarks.attune == nil)
DN.db.modules = nil
DN:Fire("MODULE_OPTION", "Synastria", "markBosses", true)

-- each row has an option of its own, which takes effect straight away
DN.db.modules = { Synastria = { attuneRow = false } }
DN:Fire("MODULE_OPTION", "Synastria", "attuneRow", false)
local attuneOff = Note() == nil and DN.trackerNotes["attune trash"] ~= nil
DN.db.modules = { Synastria = { trashRow = false } }
DN:Fire("MODULE_OPTION", "Synastria", "trashRow", false)
print("row options:", attuneOff and Note() ~= nil and DN.trackerNotes["attune trash"] == nil)
DN.db.modules = nil
DN:Fire("MODULE_OPTION", "Synastria", "trashRow", true)

-- picking up a drop takes it off both rows within a second, like Synastria's own tracker
owned[502] = true
MOCK.Fire("BAG_UPDATE", 0)
MOCK.Tick(1.1)
print("picked up:", Has(Note().right, "2") and Has(DN.trackerNotes["attune trash"].right, "1"))
owned[502] = nil
MOCK.Fire("BAG_UPDATE", 0)
MOCK.Tick(1.1)

-- attuning an item lowers the count at the next recount (a kill, or every 30 s)
attuned[501] = true
DN:Fire("BOSS_KILLED")
DN:Fire("RUN_CHANGED")
print("recounted:", Has(Note().right, "2"))
attuned[502], attuned[504] = true, true
MOCK.Tick(31)
print("all done:", Has(Note().right, "None") and DN.trackerNotes["attune trash"] == nil)

-- With the server's zone, the list is made the way its Item Hunt tracker makes it: every item the
-- character can still attune, kept where its best source (with the tracker's filters) is in this
-- zone. 601 drops from Marrowgar here, 602 from a trash mob here, 603 only elsewhere.
local OWN = 12345
local TRACKER = { [601] = { 0, 0, 36612, "Lord Marrowgar", 20 }, [602] = { 0, 0, 97, "Ancient Skeletal Soldier", 2 } }
local args = {}
function Custom_GetCurrentZoneOur() return OWN end
function GetCustomGameData(a, b)
	return a == 37 and b == 0x10000 + 6 and 7 or a == 37 and b == 0x10000 + 27 and 0x0201 or 0
end
function ItemLocGetAllItemsInZone(z, char, _, _, _, have)
	fetches[#fetches + 1] = z or "all"
	return z == nil and char == 1 and have == -1 and { 601, 602, 603 } or ZONES[z]
end
function ItemLocGetSourcesCompacted(item, white, _, minChance, maxChance, _, z)
	args = { white = white, minChance = minChance, maxChance = maxChance, zone = z }
	local s = z == OWN and TRACKER[item]
	if s then return 0, s[1], s[3], s[4], s[5] end
end
DN:Fire("INSTANCE_CHANGED", inst)
print("row cleared on instance change:", Note() == nil)
MOCK.Tick(0.2)
local n = Note()
local trash = DN.trackerNotes["attune trash"]
print("tracker's way:", fetches[#fetches] == "all" and n ~= nil and Has(n.right, "2") and trash ~= nil and Has(trash.right, "1"))
-- its filters come from the tracker's settings: source types, and chance limits (1-2%)
print("tracker's filters:", args.white == 7 and args.minChance == 0 and args.maxChance == 1 and args.zone == OWN)
lines = {}
n.tooltip(tip)
t = table.concat(lines, "\n")
print("tracker's sources:", Has(t, "Lord Marrowgar | 1") and Has(t, "Trash, Chests and Others | 1") and not Has(t, "Item603"))
-- and each zone is fetched once per session
local count = #fetches
DN:Fire("INSTANCE_CHANGED", inst)
MOCK.Tick(0.2)
print("fetched once:", #fetches == count and Has(Note().right, "2"))
-- the server reports the normal zone first and the heroic one a moment later: the rows follow it
local HEROIC = 12346
TRACKER[603] = { 0, 0, 36612, "Lord Marrowgar", 20 }
local s = ItemLocGetSourcesCompacted
function ItemLocGetSourcesCompacted(item, a, b, c, d, e, z, g)
	if z == HEROIC then return item == 603 and 0 or nil, 0, 36612, "Lord Marrowgar", 20 end
	return s(item, a, b, c, d, e, z, g)
end
OWN = HEROIC
MOCK.Tick(1.1)
MOCK.Tick(0.1)
print("follows a zone change:", Has(Note().right, "1") and DN.trackerNotes["attune trash"] == nil)
OWN = 12345
MOCK.Tick(1.1)
MOCK.Tick(0.1)

-- /igpssyn reports what's counted
local said = {}
local print_ = DN.Print
DN.Print = function(_, msg, ...) said[#said + 1] = msg:format(...) end
SlashCmdList.INSTANCEGPSSYN("")
DN.Print = print_
local report = table.concat(said, "\n")
print("slash report:", Has(report, "12345") and Has(report, "2 left to attune") and Has(report, "Lord Marrowgar: 1")
	and Has(report, "from 1 trash mobs"))
print("attune test done")
