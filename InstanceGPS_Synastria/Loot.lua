-- Boss loot in InstanceGPS's boss tooltips (tracker rows and the arrow), from Synastria's loot
-- database: the drops for this difficulty (Mythic drops in Mythic), marking what this character
-- can still attune.
local _, ns = ...
local DN = InstanceGPS

local MAX_LINES = 15
local MYTHIC_SRC = 20         -- ItemLoc source types from 20 up drop only in Mythic
local SKINNING, PICKPOCKET = 13, 14

local cache = {}

local function InMythic()
	return GetCustomGameData ~= nil and (GetCustomGameData(12, 11) or 0) >= 10
end

local function LootLoaded()
	return ItemLocGetObjCount ~= nil and ItemLocIsLoaded ~= nil and ItemLocIsLoaded() ~= nil
end

local function CanStillAttune(item)
	return CanAttuneItemHelper ~= nil and (CanAttuneItemHelper(item) or 0) > 0
		and not (HasAttunedAnyVariantOfItem and HasAttunedAnyVariantOfItem(item))
end

local function LootCount(id)
	return ItemLocGetObjCount(0, id) or 0
end

-- The creature whose loot applies here. The heroic and 25-player drops sit on the difficulty
-- versions; a heroic raid without its own version uses the normal one of the same size.
-- Mythic drops sit on the base creature.
local function LootCreature(npc, mythic)
	local _, _, diffIndex = GetInstanceInfo()
	local slot = (diffIndex or 1) - 1
	local versions = ns.DifficultyEntries and ns.DifficultyEntries[npc]
	if versions and not mythic then
		for _, s in ipairs({ slot, slot - 2 }) do
			local id = s > 0 and versions[s]
			if id and LootCount(id) > 0 then return id end
		end
	end
	return npc
end

local function CreatureLoot(id, mythic)
	local key = id .. (mythic and "m" or "")
	local list = cache[key]
	if not list then
		list = {}
		local n = LootCount(id)
		if n > 0 then
			ItemLocSetObjSort(0, id, 2)
			for i = 1, n do
				local src, item, chance = ItemLocGetObjAt(0, id, i)
				local wanted = src and src ~= SKINNING and src ~= PICKPOCKET and (src >= MYTHIC_SRC) == mythic
				if wanted then list[#list + 1] = { item = item, chance = chance or 0 } end
			end
		end
		cache[key] = list
	end
	return list
end

local function BossLoot(boss, mythic)
	local best, order = {}, {}
	for _, npc in ipairs(boss.npcs or {}) do
		for _, row in ipairs(CreatureLoot(LootCreature(npc, mythic), mythic)) do
			local had = best[row.item]
			if not had then order[#order + 1] = row.item end
			if not had or row.chance > had then best[row.item] = row.chance end
		end
	end
	local rows = {}
	for _, item in ipairs(order) do
		rows[#rows + 1] = { item = item, chance = best[item], attune = CanStillAttune(item) }
	end
	table.sort(rows, function(a, b)
		if a.attune ~= b.attune then return a.attune end
		return a.chance > b.chance
	end)
	return rows
end

local function ItemText(item)
	local name, _, quality = GetItemInfoCustom(item)
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	return (color and color.hex or "|cffffffff") .. (name or ("item " .. item)) .. "|r"
end

local function ChanceText(chance)
	return chance >= 100.5 and "" or chance >= 10 and ("%.0f%%"):format(chance) or ("%.1f%%"):format(chance)
end

DN:On("BOSS_TOOLTIP", function(boss, tip)
	local mythic = InMythic()
	tip:AddLine(" ")
	tip:AddDoubleLine(mythic and "Mythic Loot" or "Loot", boss.name, 1, 0.82, 0, 0.6, 0.6, 0.6)
	if LootLoaded() then
		local rows = BossLoot(boss, mythic)
		local open = 0
		for i, r in ipairs(rows) do
			if r.attune then open = open + 1 end
			if i <= MAX_LINES then
				local right = ChanceText(r.chance)
				if r.attune then right = "|cff33ff33attune|r  " .. right end
				tip:AddDoubleLine(ItemText(r.item), right, 1, 1, 1, 1, 1, 0.8)
			end
		end
		if #rows > MAX_LINES then
			tip:AddLine(("%d more"):format(#rows - MAX_LINES), 0.6, 0.6, 0.6)
		end
		if #rows == 0 then
			tip:AddLine("No creature loot listed. The fight may drop a chest instead.", 0.6, 0.6, 0.6, true)
		elseif open > 0 then
			tip:AddLine(("%d you can still attune"):format(open), 0.3, 1, 0.3)
		end
	else
		tip:AddLine("The loot database hasn't loaded yet.", 0.6, 0.6, 0.6)
	end
end)

-- the loot database is refreshed by the server (patches, Mythic changes): look it up again per instance
DN:On("INSTANCE_CHANGED", function() cache = {} end)

ns.InMythic, ns.LootLoaded, ns.CanStillAttune, ns.ItemText = InMythic, LootLoaded, CanStillAttune, ItemText
