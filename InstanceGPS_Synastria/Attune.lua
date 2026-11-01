-- A "Left to Attune" row under InstanceGPS's boss list: how many items from this instance and
-- difficulty this character can still attune, and in its tooltip where they drop, boss by boss.
-- The item list comes from Synastria's loot database, the way its own Item Hunt frame finds it.
local _, ns = ...
local DN = InstanceGPS

local NOTE = "attune"
local INSTANCE_ZONE = 0x8000
local MYTHIC_DIFF = 9
local MAX_PER_GROUP = 6

local zoneItems = {}          -- zone ID -> item IDs, for the session (each lookup costs ~100 ms)
local items, zone, pending

-- The loot database's zone for this instance: the server's own, else built from the difficulty
-- (ItemLoc difficulties: 1 normal, 2 heroic, 3/4 10/25-player, 5-8 10N/25N/10H/25H, 9 Mythic).
local function Zones(inst)
	local own = Custom_GetCurrentZoneOur and Custom_GetCurrentZoneOur()
	if own and own >= INSTANCE_ZONE then return { own } end
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
	local list, found = {}, nil
	for _, z in ipairs(Zones(inst)) do
		if not found then
			zoneItems[z] = zoneItems[z] or ItemLocGetAllItemsInZone(z, 0, 0, 1, 1) or {}
			if #zoneItems[z] > 0 then list, found = zoneItems[z], z end
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

-- the boss an item drops from here, if any
local function Holder(item, byNpc)
	if ItemLocGetSourcesCompacted then
		local _, _, objId = ItemLocGetSourcesCompacted(item, 0, 0, 0, 100, 0, zone, 2)
		return objId and byNpc[objId]
	end
	for i = 1, ItemLocGetSourceCount(item) or 0 do
		local _, objType, objId = ItemLocGetSourceAt(item, i)
		local b = (objType == 0 or objType == 20) and byNpc[objId]
		if b then return b end
	end
end

local function Open()
	local open = {}
	for _, item in ipairs(items or {}) do
		if ns.CanStillAttune(item) then open[#open + 1] = item end
	end
	return open
end

local function Tooltip(tip)
	local inst = DN.inst
	local open = Open()
	tip:AddLine(("%d left to attune here"):format(#open))
	if inst and #open > 0 then
		local byNpc, groups = BossesByNpc(inst), {}
		for _, item in ipairs(open) do
			local b = Holder(item, byNpc) or false
			groups[b] = groups[b] or {}
			table.insert(groups[b], item)
		end
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

local function Update()
	local note
	if items and #items > 0 then
		local open = #Open()
		note = {
			text = "|cffaaaaaa" .. (ns.InMythic() and "Left to Attune (Mythic)" or "Left to Attune") .. "|r",
			right = open > 0 and ("|cff33ff33%d|r"):format(open) or "|cff888888none|r",
			tooltip = Tooltip,
		}
	end
	DN:SetTrackerNote(NOTE, note)
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
end)
DN:On("BOSS_KILLED", Update)
