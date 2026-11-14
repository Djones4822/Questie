dofile("setupTests.lua")

describe("QuestieQuestPrivates", function()
    ---@type QuestieDB
    local QuestieDB
    ---@type QuestieQuestPrivate
    local _QuestieQuest

    before_each(function()
        QuestieDB = QuestieLoader:ImportModule("QuestieDB")
        QuestieLoader:ImportModule("QuestieCorrections").questNPCBlacklist = {}
        dofile("Modules/Quest/QuestieQuestPrivates.lua")
        _QuestieQuest = QuestieLoader:ImportModule("QuestieQuest").private
    end)

    describe("monster", function()
        it("should mark rare and rare elite NPCs rare, and elites and bosses not", function()
            -- Ranks follow cmangos' creature_template: 1 elite, 2 rare elite, 3 boss, 4 rare.
            local ranks = {[1] = 1, [2] = 2, [3] = 3, [4] = 4}
            QuestieDB.QueryNPCSingle = function(npcId, key)
                if key == "name" then return "Wolf" end
                if key == "rank" then return ranks[npcId] end
            end

            local rare = {}
            for npcId = 1, 4 do
                rare[npcId] = _QuestieQuest.objectiveSpawnListCallTable.monster(npcId, {Description = "Wolves"})[npcId].IsRare
            end

            assert.are.same({[2] = true, [4] = true}, rare)
        end)
    end)

    describe("item", function()
        it("should mark an item rare where a rare drops it", function()
            QuestieDB.GetItem = function() return {Id = 10, Sources = {{Type = "monster", Id = 1}, {Type = "monster", Id = 4}}} end
            QuestieDB.QueryNPCSingle = function(npcId, key)
                if key == "name" then return "Wolf" end
                if key == "rank" then return npcId == 4 and 4 or 0 end
            end

            local spawnList = _QuestieQuest.objectiveSpawnListCallTable.item(10, {Description = "Wolf Meat"})

            assert.are.same({nil, true}, {spawnList[1].IsRare, spawnList[4].IsRare})
        end)

        it("should mark monsters dropping the item hostile, and vendors selling it and objects holding it not", function()
            QuestieDB.GetItem = function()
                return {Id = 10, Sources = {{Type = "monster", Id = 1}, {Type = "monster", Id = 3, Vendor = true}, {Type = "object", Id = 2}}}
            end
            QuestieDB.QueryNPCSingle = function(_, key) return key == "name" and "Kobold" or nil end
            QuestieDB.QueryObjectSingle = function(_, key) return key == "name" and "Crate" or nil end

            local spawnList = _QuestieQuest.objectiveSpawnListCallTable.item(10, {Description = "Candles"})

            assert.is_true(spawnList[1].Hostile)
            assert.is_nil(spawnList[3].Hostile)
            assert.is_nil(spawnList[2].Hostile)
        end)

        it("should not mark a vendor hostile that is also listed as dropping the item", function()
            QuestieDB.GetItem = function() return {Id = 10, Sources = {{Type = "monster", Id = 1}, {Type = "monster", Id = 1, Vendor = true}}} end
            QuestieDB.QueryNPCSingle = function(_, key) return key == "name" and "Innkeeper" or nil end

            local spawnList = _QuestieQuest.objectiveSpawnListCallTable.item(10, {Description = "Malt"})

            assert.is_nil(spawnList[1].Hostile)
        end)
    end)
end)
