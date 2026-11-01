-- Two rows under InstanceGPS's boss list: "Left to Attune", how many items from this instance and
-- difficulty this character can still attune (its tooltip lists them boss by boss), and "Trash
-- Drops", the trash creatures here that drop them (its tooltip lists each one's items and chances).
-- The item list comes from Synastria's loot database, the way its own Item Hunt frame finds it.
local _, ns = ...
local DN = InstanceGPS

local NOTE, TRASH_NOTE = "attune", "attune trash"   -- tracker rows, in this order
local INSTANCE_ZONE = 0x8000
local MYTHIC_DIFF = 9
local MAX_PER_GROUP = 6
local MAX_TRASH, MAX_PER_TRASH = 8, 4

local zoneItems = {}          -- zone ID -> item IDs, for the session (each lookup costs ~100 ms)
local items, zone, pending

local sources = {}            -- zone ID -> item ID -> where it comes from (see Source)

-- The Item Hunt tracker's settings (its ReadVar): source filters, chance limits, BoE, forge
local function Var(i)
	return GetCustomGameData(37, 0x10000 + i) or 0
end

-- a chance limit byte: 0 unset, else the value + 1, with 0x80 meaning hundredths of a percent
local function ChanceLimit(byte, unset)
	local v = byte - 1
	return byte == 0 and unset or v >= 0x80 and (v - 0x80) * 0.01 or v
end

-- The way Synastria's own Item Hunt tracker lists a zone: every item this character can still
-- attune, kept where its best source (with the tracker's filters) is in this zone.
local function FetchLikeTracker(z)
	local chances = Var(27)
	local minChance, maxChance = ChanceLimit(chances % 256, 0), ChanceLimit(math.floor(chances / 256) % 256, 100)
	local boe = math.floor(Var(4) / 0x10000) % 2 == 1 and 1 or nil
	local list, cache = {}, {}
	for _, item in ipairs(ItemLocGetAllItemsInZone(nil, 1, nil, nil, nil, -1, Var(29), boe) or {}) do
		local src, objType, objId, name, chance = ItemLocGetSourcesCompacted(item, Var(6), Var(16), minChance, maxChance, 0, z, 2)
		if src then
			list[#list + 1] = item
			cache[item] = { objType = objType, objId = objId, name = name, chance = chance }
		end
	end
	sources[z] = cache
	return list
end

-- Without the tracker's zone: the loot database's zone for this instance, built from the
-- difficulty (ItemLoc difficulties: 1 normal, 2 heroic, 3/4 10/25-player, 5-8 10N/25N/10H/25H, 9 Mythic).
local function Zones(inst)
	local _, itype, diffIndex = GetInstanceInfo()
	diffIndex = diffIndex or 1
	local diffs = ns.InMythic() and { MYTHIC_DIFF }
		or itype == "raid" and { 4 + diffIndex, 3 + (diffIndex - 1) % 2, 0 }
		or { diffIndex, 0 }
	local zones = {}
	for i, d in ipairs(diffs) do zones[i] = inst.mapId + INSTANCE_ZONE + d * 1024 end
	return zones
end

local function Fetch(inst)
	local own = Custom_GetCurrentZoneOur and ItemLocGetSourcesCompacted and Custom_GetCurrentZoneOur()
	local list, found = {}, nil
	if own and own > 0 then
		zoneItems[own] = zoneItems[own] or FetchLikeTracker(own)
		list, found = zoneItems[own], own
	else
		for _, z in ipairs(Zones(inst)) do
			if not found then
				zoneItems[z] = zoneItems[z] or ItemLocGetAllItemsInZone(z, 0, 0, 1, 1) or {}
				if #zoneItems[z] > 0 then list, found = zoneItems[z], z end
			end
		end
	end
	return list, found
end

local function BossesByNpc(inst)
	local by = {}
	for _, b in ipairs(inst.bosses) do
		for _, npc in ipairs(b.npcs or {}) do
			by[npc] = b
			for _, v in pairs(ns.DifficultyEntries[npc] or {}) do by[v] = b end
		end
	end
	return by
end

local function IsCreature(objType)
	return objType == 0 or objType == 20
end

-- Where an item comes from in this instance: { boss =, objType =, objId =, name =, chance = }.
-- Looked up once per zone and item.
local function Source(item, byNpc)
	sources[zone or 0] = sources[zone or 0] or {}
	local cache = sources[zone or 0]
	if not cache[item] then
		local s = {}
		if ItemLocGetSourcesCompacted then
			local _, objType, objId, name, chance = ItemLocGetSourcesCompacted(item, 0, 0, 0, 100, 0, zone, 2)
			s = { objType = objType, objId = objId, name = name, chance = chance }
		else
			local here = DN.inst and DN.inst.name:lower()
			for i = 1, ItemLocGetSourceCount(item) or 0 do
				local _, objType, objId, chance, _, name, zoneName = ItemLocGetSourceAt(item, i)
				local row = { objType = objType, objId = objId, name = name, chance = chance }
				local boss = IsCreature(objType) and byNpc[objId]
				local inZone = here and zoneName and zoneName:lower():sub(1, #here) == here
				if boss or (inZone and not s.objId) then s = row end
				if boss then break end
			end
		end
		cache[item] = s
	end
	local s = cache[item]
	s.boss = IsCreature(s.objType) and s.objId and byNpc[s.objId] or nil
	return s
end

local function Open()
	local open = {}
	for _, item in ipairs(items or {}) do
		if ns.CanStillAttune(item) then open[#open + 1] = item end
	end
	return open
end

-- The open items by boss (false: anywhere else), and trash creatures with their open items,
-- the creatures with the most first.
local function Groups(inst, open)
	local byNpc, groups, trash, byName = BossesByNpc(inst), {}, {}, {}
	for _, item in ipairs(open) do
		local s = Source(item, byNpc)
		local b = s.boss or false
		groups[b] = groups[b] or {}
		table.insert(groups[b], item)
		if not s.boss and IsCreature(s.objType) and s.name then
			local t = byName[s.name]
			if not t then
				t = { name = s.name, items = {} }
				byName[s.name] = t
				trash[#trash + 1] = t
			end
			table.insert(t.items, { item = item, chance = s.chance or 0 })
		end
	end
	table.sort(trash, function(a, b)
		if #a.items ~= #b.items then return #a.items > #b.items end
		return a.name < b.name
	end)
	return groups, trash
end

local function Tooltip(tip)
	local inst = DN.inst
	local open = Open()
	tip:AddLine(("%d left to attune here"):format(#open))
	if inst and #open > 0 then
		local groups = Groups(inst, open)
		local order, listed = {}, {}
		for _, bi in ipairs((DN:ActiveRoute() or {}).order or {}) do
			order[#order + 1], listed[inst.bosses[bi]] = inst.bosses[bi], true
		end
		for _, b in ipairs(inst.bosses) do
			if not listed[b] then order[#order + 1] = b end
		end
		order[#order + 1] = false
		for _, b in ipairs(order) do
			local list = groups[b]
			if list then
				tip:AddLine(" ")
				tip:AddDoubleLine(b and b.name or "Trash, Chests and Others", ("%d"):format(#list), 1, 0.82, 0, 0.3, 1, 0.3)
				for i = 1, math.min(#list, MAX_PER_GROUP) do tip:AddLine(ns.ItemText(list[i])) end
				if #list > MAX_PER_GROUP then tip:AddLine(("%d more"):format(#list - MAX_PER_GROUP), 0.6, 0.6, 0.6) end
			end
		end
	end
end

local function TrashTooltip(tip)
	local inst = DN.inst
	local _, trash = Groups(inst, Open())
	tip:AddLine("Trash worth killing here")
	tip:AddLine("Creatures that drop items you can still attune.", 1, 1, 1, true)
	for i = 1, math.min(#trash, MAX_TRASH) do
		local t = trash[i]
		tip:AddLine(" ")
		tip:AddDoubleLine(t.name, ("%d"):format(#t.items), 1, 0.82, 0, 0.3, 1, 0.3)
		table.sort(t.items, function(a, b) return a.chance > b.chance end)
		for k = 1, math.min(#t.items, MAX_PER_TRASH) do
			tip:AddDoubleLine(ns.ItemText(t.items[k].item), ns.ChanceText(t.items[k].chance), 1, 1, 1, 1, 1, 0.8)
		end
		if #t.items > MAX_PER_TRASH then tip:AddLine(("%d more"):format(#t.items - MAX_PER_TRASH), 0.6, 0.6, 0.6) end
	end
	if #trash > MAX_TRASH then
		tip:AddLine(" ")
		tip:AddLine(("%d more creatures"):format(#trash - MAX_TRASH), 0.6, 0.6, 0.6)
	end
end

local function Update()
	local note, trashNote
	local inst = DN.inst
	if inst and items and #items > 0 then
		local open = Open()
		local _, trash = Groups(inst, open)
		note = {
			text = "|cffaaaaaa" .. (ns.InMythic() and "Left to Attune (Mythic)" or "Left to Attune") .. "|r",
			right = #open > 0 and ("|cff33ff33%d|r"):format(#open) or "|cff888888none|r",
			tooltip = Tooltip,
		}
		if #trash > 0 then
			trashNote = {
				text = "|cffaaaaaaTrash Drops|r",
				right = ("|cff33ff33%d|r %s"):format(#trash, #trash == 1 and "mob" or "mobs"),
				tooltip = TrashTooltip,
			}
		end
	end
	DN:SetTrackerNote(NOTE, note)
	DN:SetTrackerNote(TRASH_NOTE, trashNote)
end

-- fetched a frame after entering (and retried each second until the database has loaded);
-- recounted every 30 s and on kills, since attuning goes on as you play
local RECOUNT = 30
local f = CreateFrame("Frame")
local wait = 0
f:SetScript("OnUpdate", function(_, elapsed)
	wait = wait - elapsed
	if wait <= 0 and (pending or items) then
		local inst = DN.inst
		if pending and inst and ns.LootLoaded() then
			pending, wait = false, RECOUNT
			items, zone = Fetch(inst)
			Update()
		elseif pending then
			pending, wait = inst ~= nil, 1
		else
			wait = RECOUNT
			Update()
		end
	end
end)

DN:On("INSTANCE_CHANGED", function()
	items, zone, pending, wait = nil, nil, true, 0
	DN:SetTrackerNote(NOTE, nil)
	DN:SetTrackerNote(TRASH_NOTE, nil)
end)
DN:On("BOSS_KILLED", Update)

-- /igpssyn: what the rows are counting here, to compare with Synastria's own Item Hunt tracker
SLASH_INSTANCEGPSSYN1 = "/igpssyn"
SlashCmdList.INSTANCEGPSSYN = function()
	local inst = DN.inst
	if inst and items then
		local open = Open()
		local groups, trash = Groups(inst, open)
		local how = Custom_GetCurrentZoneOur and ItemLocGetSourcesCompacted and "the Item Hunt tracker's way"
			or "the instance's zone from its difficulty"
		DN:Print("Zone %s (%s), found %s: %d items, %d left to attune.", tostring(zone),
			Custom_GetZoneName and tostring(Custom_GetZoneName(zone or 0)) or "?", how, #items, #open)
		for _, b in ipairs(inst.bosses) do
			if groups[b] then DN:Print("  %s: %d", b.name, #groups[b]) end
		end
		DN:Print("  Elsewhere: %d, from %d trash mobs.", #(groups[false] or {}), #trash)
	else
		DN:Print("Synastria: nothing counted yet (not in an instance, or the loot database hasn't loaded).")
	end
end
