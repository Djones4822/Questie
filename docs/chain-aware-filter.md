# Chain-aware low-level quest filtering

General > Quest Level Options contains two independent, initially disabled options:

- **Show prerequisites for level-appropriate quests** preserves low-level prerequisites of quests passing the existing level filter.
- **Show dungeon quest chains** preserves low-level prerequisites of dungeon quests, independent of the destination's level. The existing **Show dungeon quests** option must also be enabled. The dungeon destination itself keeps its existing level filtering.

Both options affect available quest markers. They do not reveal completed, hidden, wrong-race/class, profession-ineligible, or otherwise unavailable quests. The existing upper level bound and maximum character-level requirements still apply to each displayed prerequisite. Both options off retains the original filtering behavior and performs no graph work.

## Architecture

- `Modules/Quest/AvailableQuests/AvailableQuests.lua` retains its category, completion, hidden-quest, and `IsDoable` checks. It computes protection once per availability calculation, then passes a boolean exception into the level check.
- `IsLevelRequirementFulfilled.lua` bypasses only the lower quest-level bound. Protected results do not enter the ordinary level cache.
- `QuestChainFilter.lua` builds typed AND/OR requirements from the effective `QuestieDB.QueryQuestSingle` view and `QuestieDB.QuestPointers`. It indexes successors so resolved prerequisites can wake their dependents. It never infers dependencies from `childQuests`, `inGroupWith`, `nextQuestInChain`, or breadcrumb navigation links.
- `Database/QuestieDB.lua` shares the existing eligibility implementation between ordinary availability and prospective chain eligibility. The latter defers only `preQuestSingle`/`preQuestGroup` completion checks. `IsDoableVerbose` still describes ordinary availability, whose behavior is unchanged.
- Both Ace and native settings panels expose the toggles. Defaults and migration 50 leave them off. English strings are registered; other translations await translators.

The static graph is cached until the provider ID-map identity or Questie's quest-data correction revision changes. The revision changes even when a correction changes relationships without adding/removing IDs. Dynamic protection is recalculated during existing availability passes: level/threshold, quest acceptance/completion/abandonment, profession/reputation, profile/category, and visibility changes use the existing refresh paths. It is not rebuilt by marker creation, tooltip hover, or map painting. Runtime work yields in batches through the existing availability coroutine. Diagnostic lookup is constant-time:

```lua
QuestieLoader:ImportModule("QuestChainFilter").GetReason(questId)
-- "level", "dungeon", "both", or "none"
```

## Relationship policy and limits

`preQuestSingle` takes precedence over `preQuestGroup`, matching Questie. Single prerequisites form an OR requirement; grouped prerequisites form AND requirements. Positive grouped entries also accept the exclusive substitutes recognized by Questie's existing group-completion check; negative entries require the exact quest.

Completed or active prerequisites satisfy their branch without preserving earlier ancestors. Otherwise the evaluator chooses a deterministic feasible alternative and records its prerequisite set. Merging AND branches checks mutual exclusions across their ancestors. A destination is rejected if completing its ancestors would cross its `availableUntilCompleted`, `nextQuestInChain`, or breadcrumb destination boundary. Unseeded cycles and missing prerequisite IDs remain unresolved; a cycle with a feasible OR exit can resolve. Optional breadcrumb links alone provide no protection; an explicit prerequisite field remains authoritative.

This is deliberately conservative rather than an exhaustive quest planner. It keeps one feasible alternative per node and does not backtrack through every combination if a later AND merge conflicts. It can therefore omit a valid alternative route. It also retains current reputation, skill, spell, active-parent, and `availableStartingWith` restrictions: a restriction which could become satisfied later can prevent protection today. These restrictions do not make an ineligible quest visible. Ancestor-set copying and conflict checks mean worst-case cost is greater than simple linear graph traversal.

## Forever compatibility and data audit

Development base: Questie `6e2d15b48568aaa149c87237cb69442628891416` on upstream master. Installed Questie: 12.9.0, build `624cb783bfc1d272aeccd3dfa353dde8452e276f`; the filtering/database/options files matched the development base before this change. Installed Forever TOC: interface **16001**. Installed QuestieDB: **1.1.1**, contract **4**, Forever baked build `4dbb82440a27856f8dccf57094a5d792cdc7cc9b`. The installed `Wow.exe` reports **1.60.1.70938**; live game execution was not observed.

The installed baked metadata contains 5,914 quest records, 3,784 single-prerequisite references and 281 grouped-prerequisite references: 4,065 dependency edges. There are 245 quests with multiple single alternatives, no records with both prerequisite fields, and no strongly connected cycles. One dependency references an absent record: **2955 -> 4604**. All 45 `childQuests` links are separate from the prerequisite edges; none of the 4,065 prerequisites has a matching child link. These fields are not interchangeable.

Static provider corrections are already baked into those records. The installed Forever dynamic quest-correction files contain no prerequisite/child/exclusion field changes. Runtime player eligibility and quest tags still require the client; this audit does not claim all chains are playable or complete.

Verified examples from those records:

- **Defias Brotherhood:** 65 -> 132 -> 135 -> 141 -> 142 -> 155 (level 18) -> 166 (level 22). Questie's tag correction explicitly identifies 166 as Dungeon. With minimum level 35, dungeon-chain protection preserves the currently available low-level predecessor without changing 166's own level filtering.
- **Jungle Secrets / Bookie Herod:** 215 (level 33) -> 200 (level 35). With range 35–40, the level option preserves eligible quest 215.

The offline Lua 5.1 benchmark uses all 5,914 records with synthetic eligibility, not game APIs. The final local run measured **21.52 ms** for first build/evaluation, **10.25 ms** mean for 20 warm evaluations, and **3,826.5 KiB** retained graph/results memory after collection. It measures graph construction/evaluation only. Client startup, native metadata reads, memory, quest-tag discovery, and redraw responsiveness must be measured in game.

## Validation

Tests cover disabled options, independent/combined reasons, AND/OR alternatives, completed/active choices, incompatible ancestors, negative grouped entries, corrected reverse relationships, cycles/missing IDs, breadcrumb policy, coroutine yielding, and the real Defias chain. Integration tests cover the existing eligibility and level boundaries and the profile migration.

Run from the repository root:

```sh
TZ=Europe/Berlin busted -p ".test.lua" .
luacheck -q -- Database Localization Modules Public Questie.lua
lua cli/validate-loader-usage.lua
```

Manual Forever checks (still required):

1. Install the test build with the existing compatible QuestieDB; reload and verify both new options are off in General > Quest Level Options.
2. Set the existing level range to 35–40. On an eligible Alliance character with the Defias chain unfinished, compare both-off with dungeon-chains-only. Only a currently available prerequisite should gain a marker. Turn off dungeon quest visibility and confirm that protection disappears.
3. On a character eligible for unfinished quest 215, enable only level prerequisites and verify it remains visible for its level-35 destination. Adjust the minimum above the destination and verify protection disappears.
4. Accept/complete/abandon a chain quest, change level range and category settings, and hide a prerequisite manually. Verify markers update and completed/hidden/ineligible quests stay hidden. Repeat with both toggles enabled, then disabled.
5. Check both native and Ace options where supported, profile switching, login/reload, and level-up behavior. Inspect `GetReason` for the current predecessor.
6. Measure first enable/reload and subsequent recalculations with QuestieProfiler on the actual character. Check world map/minimap responsiveness and Lua errors, especially while accepting or turning in quests during a refresh.
