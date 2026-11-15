---@type AvailableQuests
local AvailableQuests = QuestieLoader:ImportModule("AvailableQuests")

---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")
---@type QuestieLib
local QuestieLib = QuestieLoader:ImportModule("QuestieLib")
---@type ActiveQuests
local ActiveQuests = QuestieLoader:ImportModule("ActiveQuests")
---@type QuestieEvent
local QuestieEvent = QuestieLoader:ImportModule("QuestieEvent")

local levelRequirementCache = {}
AvailableQuests.levelRequirementCache = levelRequirementCache

---@param questId QuestId
---@param minLevel Level @The level a quest must have at least to be shown
---@param maxLevel Level @The level a quest can have at most to be shown
---@param playerLevel Level? @Pass player level to avoid calling UnitLevel or to use custom level
---@return boolean
local function _CheckLevel(questId, minLevel, maxLevel, playerLevel, ignoreLowLevel)
    local level, requiredLevel, requiredMaxLevel = QuestieLib.GetEffectiveQuestLevel(questId, playerLevel)
    -- Don't spam the map with icons of quests with requiredLevel 0
    if requiredLevel == 0 then 
        Questie.Debug(Questie.DEBUG_ELEVATED, "Field requiredLevel is missing for quest id: ", questId)
        requiredLevel = level
    end

    local parentQuestId = QuestieDB.QueryQuestSingle(questId, "parentQuest")
    if parentQuestId and ActiveQuests.Get(parentQuestId) then
        -- If the quest is in the player's log already, there's no need to do any logic here, it must already be available
        return true
    end

    if (Questie.db.profile.lowLevelStyle ~= Questie.LOWLEVEL_RANGE) and
        minLevel > requiredLevel and QuestieEvent.activeQuests[questId] and (requiredMaxLevel == 0 or playerLevel < requiredMaxLevel) then
        return true
    end

    if (Questie.IsSoD == true) and (QuestieDB.IsSoDRuneQuest(questId) == true) and (requiredLevel <= playerLevel) then
        -- Season of Discovery Rune quests are still shown when trivial
        return true
    end

    if maxLevel >= level then
        if (not ignoreLowLevel) and (Questie.db.profile.lowLevelStyle ~= Questie.LOWLEVEL_ALL) and minLevel > level then
            -- The quest level is too low and trivial quests are not shown
            return false
        end
    else
        if (Questie.db.profile.lowLevelStyle == Questie.LOWLEVEL_RANGE) or maxLevel < requiredLevel then
            -- Either an absolute level range is set and maxLevel < level OR the maxLevel is manually set to a lower value
            return false
        end
    end

    if maxLevel < requiredLevel then
        -- Either the players level is not high enough or the maxLevel is manually set to a lower value
        return false
    end

    if requiredMaxLevel ~= 0 and playerLevel > requiredMaxLevel then
        -- The players level exceeds the requiredMaxLevel of a quest
        return false
    end

    return true
end

--- The optional exception bypasses only the lower quest-level bound. It is never cached,
--- because chain protection changes independently of the baseline level cache.
function AvailableQuests.IsLevelRequirementsFulfilled(questId, minLevel, maxLevel, playerLevel, ignoreLowLevel)
    if ignoreLowLevel then
        return _CheckLevel(questId, minLevel, maxLevel, playerLevel, true)
    end
    if levelRequirementCache[questId] == nil then
        levelRequirementCache[questId] = _CheckLevel(questId, minLevel, maxLevel, playerLevel, false)
    end
    return levelRequirementCache[questId]
end

-- This needs to be called when the player levels up and when the lowLevelStyle is changed
function AvailableQuests.ResetLevelRequirementCache()
    levelRequirementCache = {}
    AvailableQuests.levelRequirementCache = levelRequirementCache
end
