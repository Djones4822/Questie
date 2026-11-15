---@class QuestChainFilter
local QuestChainFilter = QuestieLoader:CreateModule("QuestChainFilter")
---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")

local graph, sourceIds, sourceRevision
local levelPreserved, dungeonPreserved = {}, {}

--- Build from the effective provider view, never from childQuests or storyline links.
--- Each requirement is an OR group; all groups must be satisfied (AND).
local function _BuildGraph(ids, checkpoint)
    local nodes = {}
    for id in pairs(ids) do
        local single = QuestieDB.QueryQuestSingle(id, "preQuestSingle")
        local group = (not single) and QuestieDB.QueryQuestSingle(id, "preQuestGroup")
        local node = {requirements = {}, successors = {}, exclusive = {}, completionBlockers = {}}
        nodes[id] = node
        for _, field in ipairs({"availableUntilCompleted", "nextQuestInChain", "breadcrumbForQuestId"}) do
            local blocker = QuestieDB.QueryQuestSingle(id, field)
            if blocker and blocker ~= 0 then node.completionBlockers[blocker] = true end
        end
        for _, other in ipairs(QuestieDB.QueryQuestSingle(id, "exclusiveTo") or {}) do
            node.exclusive[other] = true
        end
        if single and #single > 0 then
            local alternatives = {}
            for _, parent in ipairs(single) do alternatives[#alternatives + 1] = parent end
            table.sort(alternatives)
            node.requirements[1] = alternatives
        elseif group then
            for _, parent in ipairs(group) do
                -- Positive grouped prerequisites accept completed exclusive alternatives in Questie.
                local alternatives = {math.abs(parent)}
                if parent > 0 then
                    for _, other in ipairs(QuestieDB.QueryQuestSingle(parent, "exclusiveTo") or {}) do
                        alternatives[#alternatives + 1] = other
                    end
                end
                table.sort(alternatives)
                node.requirements[#node.requirements + 1] = alternatives
            end
        end
        checkpoint()
    end
    for id, node in pairs(nodes) do
        for _, alternatives in ipairs(node.requirements) do
            for _, parent in ipairs(alternatives) do
                if nodes[parent] then
                    nodes[parent].successors[id] = true
                end
            end
        end
        checkpoint()
    end
    return nodes
end

--- A witness records one compatible way of completing the requirements. Keeping witnesses
--- prevents an AND branch from combining mutually exclusive ancestors. Ambiguous alternatives
--- use the first feasible witness; we deliberately do not search every possible combination.
local function _TryPlan(id, node, plans, completed, active)
    local plan = {[id] = true}
    for _, alternatives in ipairs(node.requirements) do
        local satisfied = false
        for _, parent in ipairs(alternatives) do
            if completed[parent] or active[parent] then
                satisfied = true
                break
            end
        end
        if not satisfied then
            for _, parent in ipairs(alternatives) do
                local candidate = plans[parent]
                if candidate then
                    local compatible = true
                    for member in pairs(candidate) do
                        for other in pairs(plan) do
                            if graph[member].exclusive[other] or graph[other].exclusive[member] then
                                compatible = false
                                break
                            end
                        end
                        if not compatible then break end
                    end
                    if compatible then
                        for member in pairs(candidate) do plan[member] = true end
                        satisfied = true
                        break
                    end
                end
            end
        end
        if not satisfied then return nil end
    end
    for ancestor in pairs(plan) do
        if node.completionBlockers[ancestor] then return nil end
    end
    return plan
end

--- Called once per availability calculation, never per icon/tooltip/map paint. The static graph
--- survives player-state updates; provider identity and correction revisions invalidate it.
---@param ids table<QuestId, any>
---@param completed table<QuestId, boolean>
---@param active table<QuestId, any>
---@param eligible fun(id: QuestId): boolean
---@param targetReason fun(id: QuestId): boolean, boolean
---@param yieldWork function? @Availability passes supply coroutine.yield; synchronous tests may omit it.
function QuestChainFilter.Calculate(ids, completed, active, eligible, targetReason, yieldWork)
    levelPreserved, dungeonPreserved = {}, {}
    if not Questie.db.profile.showLevelAppropriatePrerequisites and not Questie.db.profile.showDungeonQuestChains then
        return
    end
    local work = 0
    local function checkpoint()
        work = work + 1
        if yieldWork and work >= 256 then
            work = 0
            yieldWork()
        end
    end
    if sourceIds ~= ids or sourceRevision ~= QuestieDB.questDataRevision then
        graph = _BuildGraph(ids, checkpoint)
        sourceIds = ids
        sourceRevision = QuestieDB.questDataRevision
    end

    local ordered, allowed, plans, queue, queued = {}, {}, {}, {}, {}
    for id in pairs(graph) do ordered[#ordered + 1] = id end
    table.sort(ordered)
    for _, id in ipairs(ordered) do
        if (next(graph[id].successors) or #graph[id].requirements > 0)
            and not completed[id] and not active[id] and eligible(id) then
            allowed[id] = true
            queue[#queue + 1] = id
            queued[id] = true
        end
        checkpoint()
    end
    local cursor = 1
    while cursor <= #queue do
        local id = queue[cursor]
        cursor = cursor + 1
        queued[id] = nil
        if not plans[id] then
            local plan = _TryPlan(id, graph[id], plans, completed, active)
            if plan then
                plans[id] = plan
                local successors = {}
                for child in pairs(graph[id].successors) do successors[#successors + 1] = child end
                table.sort(successors)
                for _, child in ipairs(successors) do
                    if allowed[child] and not plans[child] and not queued[child] then
                        queue[#queue + 1] = child
                        queued[child] = true
                    end
                end
            end
        end
        checkpoint()
    end
    for _, id in ipairs(ordered) do
        if plans[id] then
            local levelTarget, dungeonTarget = targetReason(id)
            if levelTarget or dungeonTarget then
                for ancestor in pairs(plans[id]) do
                    -- These options preserve prerequisites, not a dungeon quest merely for its own tag.
                    if ancestor ~= id then
                        if levelTarget then levelPreserved[ancestor] = true end
                        if dungeonTarget then dungeonPreserved[ancestor] = true end
                    end
                end
            end
        end
        checkpoint()
    end
end

---@param questId QuestId
---@return "level"|"dungeon"|"both"|"none"
function QuestChainFilter.GetReason(questId)
    local level = Questie.db.profile.showLevelAppropriatePrerequisites and levelPreserved[questId]
    local dungeon = Questie.db.profile.showDungeonQuestChains and Questie.db.profile.showDungeonQuests and dungeonPreserved[questId]
    if level and dungeon then return "both" end
    if level then return "level" end
    if dungeon then return "dungeon" end
    return "none"
end
