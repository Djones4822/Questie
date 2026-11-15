dofile("setupTests.lua")

describe("chain-aware level filtering", function()
    local available, level, required, maximum
    before_each(function()
        Questie.LOWLEVEL_RANGE, Questie.LOWLEVEL_ALL = 4, 2
        Questie.db.profile.lowLevelStyle = Questie.LOWLEVEL_RANGE
        Questie.IsSoD = false
        level, required, maximum = 20, 15, 0
        QuestieLoader:ImportModule("QuestieLib").GetEffectiveQuestLevel = function() return level, required, maximum end
        QuestieLoader:ImportModule("QuestieDB").QueryQuestSingle = function() return nil end
        QuestieLoader:ImportModule("QuestieEvent").activeQuests = {}
        dofile("Modules/Quest/AvailableQuests/IsLevelRequirementFulfilled.lua")
        available = QuestieLoader:ImportModule("AvailableQuests")
    end)

    it("bypasses only low-level suppression without poisoning the baseline cache", function()
        assert.is_false(available.IsLevelRequirementsFulfilled(1, 35, 40, 40))
        assert.is_true(available.IsLevelRequirementsFulfilled(1, 35, 40, 40, true))
        assert.is_false(available.IsLevelRequirementsFulfilled(1, 35, 40, 40))
    end)

    it("retains the upper range, required level, and maximum character level", function()
        level = 45
        assert.is_false(available.IsLevelRequirementsFulfilled(1, 35, 40, 40, true))
        level, required = 20, 45
        assert.is_false(available.IsLevelRequirementsFulfilled(1, 35, 40, 40, true))
        required, maximum = 15, 30
        assert.is_false(available.IsLevelRequirementsFulfilled(1, 35, 40, 40, true))
    end)

    it("updates the baseline after threshold and level changes reset its cache", function()
        assert.is_false(available.IsLevelRequirementsFulfilled(1, 35, 40, 40))
        available.ResetLevelRequirementCache()
        assert.is_true(available.IsLevelRequirementsFulfilled(1, 15, 40, 40))
        available.ResetLevelRequirementCache()
        assert.is_false(available.IsLevelRequirementsFulfilled(1, 25, 50, 50))
    end)
end)
