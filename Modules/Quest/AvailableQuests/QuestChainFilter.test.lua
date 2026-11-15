dofile("setupTests.lua")

describe("QuestChainFilter", function()
    local filter, db, rows, ids, completed, active, blocked, levels, dungeons
    local function Calculate()
        filter.Calculate(ids, completed, active, function(id) return not blocked[id] end,
            function(id) return levels[id], dungeons[id] end)
    end
    local function Rows(value)
        rows, ids = value, {}
        for id in pairs(rows) do ids[id] = true end
    end
    before_each(function()
        db = QuestieLoader:ImportModule("QuestieDB")
        db.QueryQuestSingle = function(id, field) return rows[id] and rows[id][field] end
        dofile("Modules/Quest/AvailableQuests/QuestChainFilter.lua")
        filter = QuestieLoader:ImportModule("QuestChainFilter")
        Questie.db.profile.showLevelAppropriatePrerequisites = true
        Questie.db.profile.showDungeonQuestChains = true
        Questie.db.profile.showDungeonQuests = true
        completed, active, blocked, levels, dungeons = {}, {}, {}, {}, {}
        Rows({[1] = {}, [2] = {preQuestSingle = {1}}, [3] = {preQuestSingle = {2}}, [4] = {}})
    end)
    after_each(function()
        Questie.db.profile.showLevelAppropriatePrerequisites = false
        Questie.db.profile.showDungeonQuestChains = false
    end)

    it("does no database work when both options are off", function()
        Questie.db.profile.showLevelAppropriatePrerequisites = false
        Questie.db.profile.showDungeonQuestChains = false
        db.QueryQuestSingle = function() error("unexpected DB read") end
        Calculate()
        assert.are_same("none", filter.GetReason(1))
    end)

    it("preserves transitive level prerequisites but not unrelated quests", function()
        levels[3] = true
        Calculate()
        assert.are_same("level", filter.GetReason(1))
        assert.are_same("level", filter.GetReason(2))
        assert.are_same("none", filter.GetReason(4))
    end)

    it("preserves dungeon chains without a level target, not the dungeon itself", function()
        dungeons[3] = true
        Calculate()
        assert.are_same("dungeon", filter.GetReason(1))
        assert.are_same("none", filter.GetReason(3))
        Questie.db.profile.showDungeonQuests = false
        assert.are_same("none", filter.GetReason(1))
    end)

    it("returns the union of independent reasons", function()
        levels[3], dungeons[3] = true, true
        Calculate()
        assert.are_same("both", filter.GetReason(1))
        Questie.db.profile.showLevelAppropriatePrerequisites = false
        assert.are_same("dungeon", filter.GetReason(1))
        Questie.db.profile.showLevelAppropriatePrerequisites = true
        Questie.db.profile.showDungeonQuestChains = false
        assert.are_same("level", filter.GetReason(1))
    end)

    it("recomputes on target, eligibility, and completion changes", function()
        levels[3] = true
        Calculate()
        levels[3] = nil
        Calculate()
        assert.are_same("none", filter.GetReason(1))
        levels[3], blocked[2] = true, true
        Calculate()
        assert.are_same("none", filter.GetReason(1))
        blocked[2], completed[2] = nil, true
        Calculate()
        assert.are_same("none", filter.GetReason(1))
        assert.are_same("none", filter.GetReason(2))
    end)

    it("requires every AND branch to be feasible", function()
        Rows({[1] = {}, [2] = {}, [3] = {preQuestGroup = {1, 2}}})
        levels[3] = true
        Calculate()
        assert.are_same("level", filter.GetReason(1))
        assert.are_same("level", filter.GetReason(2))
        blocked[2] = true
        Calculate()
        assert.are_same("none", filter.GetReason(1))
    end)

    it("selects a feasible OR alternative and stops at a completed or active choice", function()
        Rows({[1] = {}, [2] = {}, [3] = {preQuestSingle = {1, 2}}})
        levels[3], blocked[1] = true, true
        Calculate()
        assert.are_same("none", filter.GetReason(1))
        assert.are_same("level", filter.GetReason(2))
        active[1] = true
        Calculate()
        assert.are_same("none", filter.GetReason(2))
        active[1], completed[1] = nil, true
        Calculate()
        assert.are_same("none", filter.GetReason(2))
    end)

    it("rejects incompatible ancestors across AND branches", function()
        Rows({[1] = {exclusiveTo = {2}}, [2] = {}, [3] = {preQuestSingle = {1}},
            [4] = {preQuestSingle = {2}}, [5] = {preQuestGroup = {3, 4}}})
        levels[5] = true
        Calculate()
        assert.are_same("none", filter.GetReason(1))
        assert.are_same("none", filter.GetReason(2))
    end)

    it("honors completed group substitutes but negative group entries require the exact quest", function()
        Rows({[1] = {exclusiveTo = {2}}, [2] = {}, [3] = {}, [4] = {preQuestGroup = {1, 3}}})
        completed[2], blocked[1], levels[4] = true, true, true
        Calculate()
        assert.are_same("level", filter.GetReason(3))
        rows[4].preQuestGroup = {-1, 3}
        ids = {[1] = true, [2] = true, [3] = true, [4] = true}
        Calculate()
        assert.are_same("none", filter.GetReason(3))
    end)

    it("prefers single prerequisites when both prerequisite fields exist", function()
        Rows({[1] = {}, [2] = {}, [3] = {preQuestSingle = {1}, preQuestGroup = {2}}})
        levels[3] = true
        Calculate()
        assert.are_same("level", filter.GetReason(1))
        assert.are_same("none", filter.GetReason(2))
    end)

    it("terminates on cycles and missing IDs, and can use a cycle's reachable exit", function()
        Rows({[1] = {preQuestSingle = {2}}, [2] = {preQuestSingle = {1}},
            [3] = {preQuestSingle = {99}}, [4] = {}})
        levels[1], levels[3] = true, true
        Calculate()
        assert.are_same("none", filter.GetReason(2))
        rows[2].preQuestSingle = {1, 4}
        ids = {[1] = true, [2] = true, [3] = true, [4] = true}
        Calculate()
        assert.are_same("level", filter.GetReason(4))
    end)

    it("ignores breadcrumb, child, group, and next-chain navigation links", function()
        Rows({[1] = {breadcrumbForQuestId = 2, childQuests = {2}, inGroupWith = {2}, nextQuestInChain = 2}, [2] = {}})
        levels[2] = true
        Calculate()
        assert.are_same("none", filter.GetReason(1))
    end)

    it("uses corrected reverse prerequisites and rebuilds when the provider replaces the ID map", function()
        levels[3] = true
        Calculate()
        assert.are_same("level", filter.GetReason(1))
        rows[3].preQuestSingle = {4}
        ids = {[1] = true, [2] = true, [3] = true, [4] = true}
        Calculate()
        assert.are_same("none", filter.GetReason(1))
        assert.are_same("level", filter.GetReason(4))
        db.QueryQuestSingle = function() error("static graph should be cached") end
        Calculate()
    end)
    it("invalidates on a correction revision even when the ID map is unchanged", function()
        levels[3] = true
        Calculate()
        rows[3].preQuestSingle = {4}
        db.questDataRevision = (db.questDataRevision or 0) + 1
        Calculate()
        assert.are_same("none", filter.GetReason(1))
        assert.are_same("level", filter.GetReason(4))
    end)

    it("preserves the installed Forever Defias dungeon chain", function()
        -- QuestieDB Forever 1.1.1, build 4dbb824: effective preQuestSingle fields.
        Rows({[65] = {}, [132] = {preQuestSingle = {65}}, [135] = {preQuestSingle = {132}},
            [141] = {preQuestSingle = {135}}, [142] = {preQuestSingle = {141}},
            [155] = {preQuestSingle = {142}}, [166] = {preQuestSingle = {155}}})
        dungeons[166] = true -- Questie's questTagInfoCorrections marks 166 as Dungeon (81).
        Calculate()
        assert.are_same("dungeon", filter.GetReason(65))
        assert.are_same("dungeon", filter.GetReason(155))
        assert.are_same("none", filter.GetReason(166))
    end)

    it("rejects a target that completing its own prerequisite would disable", function()
        Rows({[1] = {}, [2] = {preQuestSingle = {1}, availableUntilCompleted = 1}})
        levels[2] = true
        Calculate()
        assert.are_same("none", filter.GetReason(1))
    end)

    it("yields bounded batches when called from the availability coroutine", function()
        local many = {}
        for id = 1, 600 do many[id] = {} end
        many[600].preQuestSingle = {1}
        Rows(many)
        levels[600] = true
        local thread = coroutine.create(function()
            filter.Calculate(ids, completed, active, function() return true end,
                function(id) return levels[id], false end, coroutine.yield)
        end)
        local yields = 0
        repeat
            local ok, message = coroutine.resume(thread)
            assert.is_true(ok, message)
            yields = yields + 1
        until coroutine.status(thread) == "dead"
        assert.is_true(yields > 1)
        assert.are_same("level", filter.GetReason(1))
    end)

end)
