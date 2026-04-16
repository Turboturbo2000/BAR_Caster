------------------------------------------------------------------------
-- BAR Caster Widget
-- Spectator & replay analysis tool for Beyond All Reason
--
-- Features:
--   - Per-player eco tracking (metal/s, energy/s, mex, factories)
--   - Team balance bar (eco + army weighted)
--   - Team eco graph (Team 1 vs Team 2 metal/s over time)
--   - Territory control mini-map
--   - Individual eco comparison graph (top 4 players)
--   - Army composition graph (stacked bar over time)
--   - Player ranking (sortable: metal, army, mex, trade, reclaim)
--   - T2 race tracking (first T2, all T2 timings)
--   - Trade balance per player (kills vs losses)
--   - Reclaim estimation per player
--   - Idle army % warnings
--   - Alert system (stall, overflow, battles, overrun)
--   - Event timeline (horizontal bar with event markers)
--   - Commentator mode (auto-switch to most exciting player)
--   - MVP display at game end
--   - OBS export (/casterobs)
--   - Battle detection with in-world markers
--
-- Controls:
--   F9          Toggle panel visibility
--   PageUp/Down Switch player
--   /castersort Cycle sort mode
--   /castercast Toggle commentator mode
--   /casterobs  Toggle OBS export
--
-- Author: BAR Coach Project
-- License: GNU GPL v2
------------------------------------------------------------------------

function widget:GetInfo()
    return {
        name      = "BAR Caster Widget",
        desc      = "Spectator & Replay Analysis (F9)",
        author    = "BAR Coach Project",
        version   = "1.0",
        date      = "2026",
        license   = "GNU GPL v2",
        layer     = 0,
        enabled   = true,
    }
end

------------------------------------------------------------------------
-- Spring API locals (performance)
------------------------------------------------------------------------
local spGetGameSeconds      = Spring.GetGameSeconds
local spGetTeamResources    = Spring.GetTeamResources
local spGetUnitDefID        = Spring.GetUnitDefID
local spGetUnitPosition     = Spring.GetUnitPosition
local spGetUnitHealth       = Spring.GetUnitHealth
local spWorldToScreenCoords = Spring.WorldToScreenCoords

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local UPDATE_INTERVAL   = 1.0     -- seconds between data updates
local GRAPH_HISTORY     = 30      -- data points in graphs
local HISTORY_SECONDS   = 30      -- time window for graphs

------------------------------------------------------------------------
-- Panel settings
------------------------------------------------------------------------
local panelVisible   = true
local panelWidth     = 300
local panelMargin    = 10
local panelTopOffset = 80
local fontSize       = 14
local lineHeight     = 18

------------------------------------------------------------------------
-- Color theme
------------------------------------------------------------------------
local C = {
    bg          = { 0.02, 0.04, 0.08, 0.88 },
    bgLight     = { 0.06, 0.08, 0.14, 0.7 },
    title       = { 0.9, 0.75, 0.3, 1.0 },
    sectionHead = { 0.5, 0.7, 1.0, 1.0 },
    text        = { 0.85, 0.85, 0.85, 1.0 },
    textDim     = { 0.55, 0.55, 0.60, 0.9 },
    metalColor  = { 0.4, 0.8, 0.7, 1.0 },
    divider     = { 0.2, 0.3, 0.5, 0.5 },
}

------------------------------------------------------------------------
-- Known artillery unit names (for role classification)
------------------------------------------------------------------------
local artyNames = {
    corint = true, armbrtha = true, legint = true,
    corsilo = true, armsilo = true, legsilo = true,
    corbhmth = true, armbhmth = true,
    armvulc = true, corvipe = true,
}

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local S = {}
local vsx, vsy = 0, 0
local timeSinceUpdate = 0

-- Player list and tracking
S.defLookups        = nil
S.specPlayerList    = {}
S.specSelectedIdx   = 1
S.specWatchTeamID   = nil
S.specWatchName     = ""
S.specInitDone      = false
S.specAllData       = {}
S.specFirstT2       = nil
S.specT2List        = {}
S.specTeamBalance   = {}
S.specTeamMetalHistory = {}
S.specBalancePct    = 50
S.specBalanceLabel  = ""
S.specFactionsDone  = false

-- Alert system
S.specAlertCooldowns = {}
S.specPrevArmy       = {}
S.specAlertLog       = {}
S.SPEC_ALERT_MAX     = 8
S.SPEC_ALERT_COOLDOWN_STALL   = 30
S.SPEC_ALERT_COOLDOWN_BATTLE  = 20
S.SPEC_ALERT_COOLDOWN_OVERRUN = 45

-- Battle detection
S.specBattles        = {}
S.specBattleTimer    = 0
S.SPEC_BATTLE_SCAN_INTERVAL = 3
S.SPEC_BATTLE_MIN_VALUE     = 2000
S.SPEC_BATTLE_RADIUS        = 1200
S.SPEC_BATTLE_DURATION      = 10

-- Sorting
S.specSortMode   = "metal"
S.specSortModes  = { "metal", "army", "mex", "trade", "reclaim" }
S.specSortLabels = {
    metal = "Metal/s", army = "Army Value", mex = "Mex Count",
    trade = "Trade Balance", reclaim = "Reclaim",
}

-- Territory control
S.specControlGrid     = {}
S.specControlGridSize = 512
S.specControlCols     = 0
S.specControlRows     = 0

-- Commentator mode
S.specAutoSwitch         = false
S.specAutoSwitchTimer    = 0
S.specAutoSwitchMinTime  = 5
S.specAutoSwitchLastScore = 0

-- Timeline
S.specTimeline    = {}
S.specTimelineMax = 100

-- OBS export
S.specOBSExport = false
S.specOBSTimer  = 0

-- Game over / MVP
S.gameOver = false
S.specMVPs = {}

-- Panel drag
local panelDragging    = false
local panelDragOffsetX = 0
local panelDragOffsetY = 0
local panelPosX        = nil
local panelPosY        = nil
local lastPanelHeight  = 400  -- cached height for background rendering

------------------------------------------------------------------------
-- Load modules
------------------------------------------------------------------------
local RENDERING
local isMex, isFactory, isNano, isT2Factory, isCombatUnit
local isAntiAir, classifyUnit, isAirUnit
local isCommander, isBuilder, isUnitIdle, isUnitFinished

------------------------------------------------------------------------
-- In-world spectator markers
------------------------------------------------------------------------
local specMarkers = {}
local SPEC_MARKER_FONT     = 18
local SPEC_MARKER_DURATION = 12

local function addSpecMarker(x, y, z, label, r, g, b, duration)
    if not x then return end
    local dur = duration or SPEC_MARKER_DURATION
    -- Update existing nearby marker
    for i = 1, #specMarkers do
        local m = specMarkers[i]
        local dx = m.x - x
        local dz = m.z - z
        if dx * dx + dz * dz < 800 * 800 then
            m.timer = dur
            m.label = label
            m.r = r or m.r
            m.g = g or m.g
            m.b = b or m.b
            return
        end
    end
    if #specMarkers >= 12 then
        table.remove(specMarkers, 1)
    end
    specMarkers[#specMarkers + 1] = {
        x = x, y = y, z = z,
        timer = dur,
        label = label or "!",
        r = r or 0.3, g = g or 1.0, b = b or 0.8,
    }
end

local function updateSpecMarkers(dt)
    local i = 1
    while i <= #specMarkers do
        specMarkers[i].timer = specMarkers[i].timer - dt
        if specMarkers[i].timer <= 0 then
            table.remove(specMarkers, i)
        else
            i = i + 1
        end
    end
end

local function drawSpecMarkers()
    for i = 1, #specMarkers do
        local m = specMarkers[i]
        local sx, sy, sz = spWorldToScreenCoords(m.x, m.y + 120, m.z)
        if sz and sz < 1 then
            local fade = math.min(1.0, m.timer / 2.0)
            local pulse = 0.8 + 0.2 * math.abs(math.sin(m.timer * 3))
            local text = m.label
            local textW = gl.GetTextWidth(text) * SPEC_MARKER_FONT
            -- Background
            gl.Color(0.0, 0.05, 0.1, 0.75 * fade)
            gl.Rect(sx - textW/2 - 10, sy + SPEC_MARKER_FONT + 6,
                     sx + textW/2 + 10, sy - 6)
            -- Colored top border
            gl.Color(m.r, m.g, m.b, 0.9 * fade * pulse)
            gl.Rect(sx - textW/2 - 10, sy + SPEC_MARKER_FONT + 6,
                     sx + textW/2 + 10, sy + SPEC_MARKER_FONT + 3)
            -- Text
            gl.Color(m.r, m.g, m.b, fade * pulse)
            gl.Text(text, sx, sy, SPEC_MARKER_FONT, "oc")
        end
    end
end

------------------------------------------------------------------------
-- Helper: detect faction from unit names
------------------------------------------------------------------------
local function detectFaction(teamID)
    local units = Spring.GetTeamUnits(teamID)
    if units then
        for i = 1, math.min(5, #units) do
            local defID = spGetUnitDefID(units[i])
            if defID then
                local ud = UnitDefs[defID]
                if ud and ud.name then
                    local n = ud.name
                    if string.sub(n, 1, 3) == "cor" then return "Cortex"
                    elseif string.sub(n, 1, 3) == "arm" then return "Armada"
                    elseif string.sub(n, 1, 3) == "leg" then return "Legion"
                    end
                end
            end
        end
    end
    return "???"
end

------------------------------------------------------------------------
-- Initialize player list
------------------------------------------------------------------------
local function initPlayerList()
    S.specPlayerList = {}
    local teamList = Spring.GetTeamList() or {}
    for _, teamID in pairs(teamList) do
        if teamID ~= Spring.GetGaiaTeamID() then
            -- Get player name
            local _, leader, _, isAI = Spring.GetTeamInfo(teamID)
            local playerName = "???"
            if isAI then
                local aiID, shortName = Spring.GetAIInfo(teamID)
                playerName = shortName and ("AI: " .. shortName) or "AI"
            elseif leader then
                local pName = Spring.GetPlayerInfo(leader)
                if pName and pName ~= "" then
                    playerName = pName
                end
            end

            local faction = detectFaction(teamID)
            local allyTeamID = select(6, Spring.GetTeamInfo(teamID))

            S.specPlayerList[#S.specPlayerList + 1] = {
                teamID = teamID,
                allyTeamID = allyTeamID,
                name = playerName,
                faction = faction,
            }

            -- Initialize tracking data
            local mHist = {}
            for hi = 1, GRAPH_HISTORY do mHist[hi] = 0 end
            S.specAllData[teamID] = {
                name = playerName,
                faction = faction,
                metalIncome = 0,
                energyIncome = 0,
                mexCount = 0,
                factoryCount = 0,
                nanoCount = 0,
                hasT2 = false,
                t2Time = 0,
                armyValue = 0,
                peakMetal = 0,
                peakEnergy = 0,
                unitCount = 0,
                armyComp = "",
                aaCount = 0,
                airCount = 0,
                idleArmy = 0,
                totalArmy = 0,
                metalHistory = mHist,
                metalKilled = 0,
                metalLost = 0,
                reclaimIncome = 0,
                raiderCount = 0,
                assaultCount = 0,
                skirmCount = 0,
                armyCompHistory = {},
            }
        end
    end

    table.sort(S.specPlayerList, function(a, b) return a.teamID < b.teamID end)
    S.specInitDone = true

    if #S.specPlayerList > 0 then
        S.specSelectedIdx = 1
        S.specWatchTeamID = S.specPlayerList[1].teamID
        S.specWatchName = S.specPlayerList[1].name
        Spring.Echo(string.format("[Caster] %d players found | PageUp/PageDown = switch",
            #S.specPlayerList))
    end
end

------------------------------------------------------------------------
-- Switch watched player
------------------------------------------------------------------------
local function selectPlayer(idx)
    if idx < 1 then idx = #S.specPlayerList end
    if idx > #S.specPlayerList then idx = 1 end
    S.specSelectedIdx = idx
    local p = S.specPlayerList[idx]
    if p then
        S.specWatchTeamID = p.teamID
        S.specWatchName = p.name
        Spring.Echo(string.format("[Caster] Watching: %s (%s, Team %d)",
            p.name, p.faction, p.teamID))
    end
end

------------------------------------------------------------------------
-- Tracking: update all players in parallel
------------------------------------------------------------------------
local function updateTracking(gameSecs)
    -- Detect factions that were unknown at start
    if gameSecs > 5 and not S.specFactionsDone then
        S.specFactionsDone = true
        for _, p in ipairs(S.specPlayerList) do
            if p.faction == "???" then
                p.faction = detectFaction(p.teamID)
            end
        end
    end

    -- Track all players
    for _, p in ipairs(S.specPlayerList) do
        local td = S.specAllData[p.teamID]
        if td then
            local sMCur, sMStor, _, sMInc = spGetTeamResources(p.teamID, "metal")
            local sECur, sEStor, _, sEInc = spGetTeamResources(p.teamID, "energy")
            td.metalIncome = sMInc or 0
            td.energyIncome = sEInc or 0
            td.faction = p.faction
            if td.metalIncome > td.peakMetal then td.peakMetal = td.metalIncome end
            if td.energyIncome > td.peakEnergy then td.peakEnergy = td.energyIncome end

            -- Metal history for eco graph
            if td.metalHistory then
                table.remove(td.metalHistory, 1)
                td.metalHistory[GRAPH_HISTORY] = td.metalIncome
            end

            local pUnits = Spring.GetTeamUnits(p.teamID)
            if pUnits then
                td.unitCount = #pUnits
                local pMex, pFac, pNano, pArmy = 0, 0, 0, 0
                local pMexExtraction = 0
                local pHasT2 = td.hasT2
                local pRaider, pAssault, pSkirm, pAir, pAA = 0, 0, 0, 0, 0
                local pIdleArmy, pTotalArmy = 0, 0
                local bigBuild = nil

                for j = 1, #pUnits do
                    local uDefID = spGetUnitDefID(pUnits[j])
                    if uDefID then
                        local ud = UnitDefs[uDefID]
                        if isMex(uDefID) then
                            pMex = pMex + 1
                            if ud and ud.extractsMetal then
                                pMexExtraction = pMexExtraction + ud.extractsMetal
                            end
                        end
                        if isFactory(uDefID) then pFac = pFac + 1 end
                        if isNano(uDefID) then pNano = pNano + 1 end
                        if isT2Factory(uDefID) then pHasT2 = true end
                        -- Detect T2 from expensive builders/mex
                        if not pHasT2 and ud then
                            local cost = ud.metalCost or 0
                            if isBuilder(uDefID) and not isCommander(uDefID) and cost > 200 then
                                pHasT2 = true
                            end
                            if isMex(uDefID) and cost > 400 then
                                pHasT2 = true
                            end
                        end
                        -- Combat units: army value, composition, idle
                        if ud and isCombatUnit(uDefID) then
                            pArmy = pArmy + (ud.metalCost or 0)
                            pTotalArmy = pTotalArmy + 1
                            local role = classifyUnit(uDefID)
                            if role == "raider" then pRaider = pRaider + 1
                            elseif role == "assault" then pAssault = pAssault + 1
                            elseif role == "skirmisher" then pSkirm = pSkirm + 1
                            elseif role == "bomber" or role == "gunship" or role == "fighter" then
                                pAir = pAir + 1
                            end
                            if isAntiAir(uDefID) then pAA = pAA + 1 end
                            if ud.canMove and isUnitFinished(pUnits[j]) and isUnitIdle(pUnits[j]) then
                                pIdleArmy = pIdleArmy + 1
                            end
                        elseif ud and (ud.speed or 0) > 0 and not isBuilder(uDefID) then
                            pArmy = pArmy + (ud.metalCost or 0)
                        end
                        -- Detect large builds in progress
                        if ud then
                            local _, _, _, _, buildProg = spGetUnitHealth(pUnits[j])
                            if buildProg and buildProg > 0.01 and buildProg < 0.95 then
                                local bCost = ud.metalCost or 0
                                if bCost >= 2000 then
                                    if not bigBuild or bCost > bigBuild.cost then
                                        local bx, by, bz = spGetUnitPosition(pUnits[j])
                                        local bName = (ud.humanName and ud.humanName ~= "" and ud.humanName)
                                            or (ud.name and ud.name ~= "" and ud.name) or "???"
                                        bigBuild = {
                                            name = bName, cost = bCost,
                                            progress = buildProg,
                                            x = bx, y = by, z = bz,
                                        }
                                    end
                                end
                            end
                        end
                    end
                end

                -- Big build marker
                if bigBuild and bigBuild.x then
                    local bLabel = string.format("%s: %s %d%%",
                        p.name, bigBuild.name, math.floor(bigBuild.progress * 100))
                    addSpecMarker(bigBuild.x, bigBuild.y, bigBuild.z, bLabel,
                        0.9, 0.7, 0.2, 3)
                end

                td.mexCount = pMex
                -- Estimate reclaim: metalIncome minus estimated mex output
                local estMexIncome = pMex * 2.0
                td.reclaimIncome = math.max(0, td.metalIncome - estMexIncome)
                td.factoryCount = pFac
                td.nanoCount = pNano
                td.armyValue = pArmy
                td.aaCount = pAA
                td.airCount = pAir
                td.idleArmy = pIdleArmy
                td.totalArmy = pTotalArmy

                -- Army composition string
                local compParts = {}
                if pRaider > 0 then compParts[#compParts + 1] = pRaider .. "R" end
                if pAssault > 0 then compParts[#compParts + 1] = pAssault .. "A" end
                if pSkirm > 0 then compParts[#compParts + 1] = pSkirm .. "S" end
                if pAir > 0 then compParts[#compParts + 1] = pAir .. "Air" end
                td.armyComp = table.concat(compParts, " ")
                td.raiderCount = pRaider
                td.assaultCount = pAssault
                td.skirmCount = pSkirm

                -- Army composition history (max 20 snapshots)
                local ach = td.armyCompHistory
                if #ach >= 20 then table.remove(ach, 1) end
                ach[#ach + 1] = {
                    raider = pRaider, assault = pAssault,
                    skirm = pSkirm, air = pAir,
                }

                -- T2 detection
                if pHasT2 and not td.hasT2 then
                    td.hasT2 = true
                    td.t2Time = gameSecs
                    local t2m = math.floor(gameSecs / 60)
                    local t2s = math.floor(gameSecs % 60)
                    local t2x, t2y, t2z
                    for k = 1, #pUnits do
                        local kDefID = spGetUnitDefID(pUnits[k])
                        if kDefID and isT2Factory(kDefID) then
                            t2x, t2y, t2z = spGetUnitPosition(pUnits[k])
                            break
                        end
                    end
                    S.specT2List[#S.specT2List + 1] = {
                        name = p.name, faction = p.faction,
                        time = gameSecs, teamID = p.teamID,
                    }
                    local isFirst = not S.specFirstT2
                    if isFirst then
                        S.specFirstT2 = S.specT2List[#S.specT2List]
                    end
                    Spring.Echo(string.format("[Caster] %sT2: %s (%s) at %d:%02d",
                        isFirst and "1st " or "", p.name, p.faction, t2m, t2s))
                    -- Timeline event
                    if #S.specTimeline < S.specTimelineMax then
                        S.specTimeline[#S.specTimeline + 1] = {
                            time = gameSecs,
                            text = string.format("%s%s T2", isFirst and "1st " or "", p.name),
                            r = 0.3, g = 1.0, b = 0.8,
                        }
                    end
                    if t2x then
                        local markerLabel = string.format("%s%s T2 %d:%02d",
                            isFirst and "1st! " or "", p.name, t2m, t2s)
                        if isFirst then
                            addSpecMarker(t2x, t2y, t2z, markerLabel, 1.0, 0.85, 0.2)
                        else
                            addSpecMarker(t2x, t2y, t2z, markerLabel, 0.3, 0.8, 1.0)
                        end
                    end
                end
            end
        end
    end

    -- === Team balance ===
    local teamTotals = {}
    for _, p in ipairs(S.specPlayerList) do
        local aID = p.allyTeamID
        if aID then
            if not teamTotals[aID] then
                teamTotals[aID] = { metal = 0, energy = 0, army = 0, players = 0, mex = 0, t2Count = 0 }
            end
            local td = S.specAllData[p.teamID]
            if td then
                local t = teamTotals[aID]
                t.metal   = t.metal + td.metalIncome
                t.energy  = t.energy + td.energyIncome
                t.army    = t.army + td.armyValue
                t.mex     = t.mex + td.mexCount
                t.players = t.players + 1
                if td.hasT2 then t.t2Count = t.t2Count + 1 end
            end
        end
    end

    S.specTeamBalance = {}
    for aID, totals in pairs(teamTotals) do
        S.specTeamBalance[#S.specTeamBalance + 1] = {
            allyTeamID = aID,
            metal = totals.metal, energy = totals.energy,
            army = totals.army, players = totals.players,
            mex = totals.mex, t2Count = totals.t2Count,
        }
    end
    table.sort(S.specTeamBalance, function(a, b) return a.allyTeamID < b.allyTeamID end)

    -- Team metal history
    for _, tb in ipairs(S.specTeamBalance) do
        local aID = tb.allyTeamID
        if not S.specTeamMetalHistory[aID] then
            local h = {}
            for hi = 1, GRAPH_HISTORY do h[hi] = 0 end
            S.specTeamMetalHistory[aID] = h
        end
        local h = S.specTeamMetalHistory[aID]
        table.remove(h, 1)
        h[GRAPH_HISTORY] = tb.metal
    end

    -- Balance percentage
    if #S.specTeamBalance >= 2 then
        local t1 = S.specTeamBalance[1]
        local t2 = S.specTeamBalance[2]
        local totalMetal = t1.metal + t2.metal
        local totalArmy  = t1.army + t2.army
        local ecoPct  = totalMetal > 0 and (t1.metal / totalMetal * 100) or 50
        local armyPct = totalArmy > 0  and (t1.army / totalArmy * 100)   or 50
        S.specBalancePct = math.floor((ecoPct + armyPct) / 2 + 0.5)
        local diff = math.abs(S.specBalancePct - 50)
        if diff <= 5 then S.specBalanceLabel = "balanced"
        elseif diff <= 15 then S.specBalanceLabel = "slight advantage"
        elseif diff <= 25 then S.specBalanceLabel = "clear advantage"
        else S.specBalanceLabel = "dominant" end
    else
        S.specBalancePct = 50
        S.specBalanceLabel = ""
    end

    -- === Territory control grid ===
    local mapSizeX = Game.mapSizeX or 8192
    local mapSizeZ = Game.mapSizeZ or 8192
    local gridSize = S.specControlGridSize
    S.specControlCols = math.ceil(mapSizeX / gridSize)
    S.specControlRows = math.ceil(mapSizeZ / gridSize)
    local grid = {}
    for _, p in ipairs(S.specPlayerList) do
        local aID = p.allyTeamID
        local units = Spring.GetTeamUnits(p.teamID)
        if units then
            for j = 1, #units do
                local ux, _, uz = spGetUnitPosition(units[j])
                if ux then
                    local gx = math.floor(ux / gridSize)
                    local gz = math.floor(uz / gridSize)
                    local key = gx .. "_" .. gz
                    if not grid[key] then grid[key] = {} end
                    grid[key][aID] = (grid[key][aID] or 0) + 1
                end
            end
        end
    end
    S.specControlGrid = grid

    -- === Commentator mode: auto-switch ===
    if S.specAutoSwitch then
        S.specAutoSwitchTimer = S.specAutoSwitchTimer + 1
        if S.specAutoSwitchTimer >= S.specAutoSwitchMinTime then
            local bestIdx, bestScore = S.specSelectedIdx, 0
            for idx, p in ipairs(S.specPlayerList) do
                local td = S.specAllData[p.teamID]
                if td then
                    local score = 0
                    local prevArmy = S.specPrevArmy[p.teamID] or 0
                    if prevArmy > 0 and td.armyValue < prevArmy * 0.7 then
                        score = score + (prevArmy - td.armyValue) / 100
                    end
                    local mCur = spGetTeamResources(p.teamID, "metal")
                    local eCur = spGetTeamResources(p.teamID, "energy")
                    if eCur and eCur < 50 then score = score + 20 end
                    if mCur and mCur < 10 then score = score + 10 end
                    if td.hasT2 and td.t2Time and gameSecs - td.t2Time < 15 then
                        score = score + 30
                    end
                    if score > bestScore then
                        bestScore = score
                        bestIdx = idx
                    end
                end
            end
            if bestIdx ~= S.specSelectedIdx and bestScore > S.specAutoSwitchLastScore + 10 then
                selectPlayer(bestIdx)
                S.specAutoSwitchTimer = 0
                S.specAutoSwitchLastScore = bestScore
            end
            S.specAutoSwitchLastScore = S.specAutoSwitchLastScore * 0.8
        end
    end
end

------------------------------------------------------------------------
-- Alerts: stall, battle, overrun
------------------------------------------------------------------------
local function checkAlerts(gameSecs)
    if gameSecs < 60 then return end

    local function alertOK(key, cooldown)
        local last = S.specAlertCooldowns[key]
        if last and gameSecs - last < cooldown then return false end
        return true
    end

    local function fireAlert(key, cooldown, text, r, g, b, x, y, z)
        S.specAlertCooldowns[key] = gameSecs
        if x then
            addSpecMarker(x, y, z, text, r, g, b, 8)
        end
        local mins = math.floor(gameSecs / 60)
        local secs = math.floor(gameSecs % 60)
        local logText = string.format("%d:%02d %s", mins, secs, text)
        S.specAlertLog[#S.specAlertLog + 1] = {
            text = logText, time = gameSecs, r = r, g = g, b = b,
        }
        while #S.specAlertLog > S.SPEC_ALERT_MAX do
            table.remove(S.specAlertLog, 1)
        end
        -- Timeline
        if #S.specTimeline < S.specTimelineMax then
            S.specTimeline[#S.specTimeline + 1] = {
                time = gameSecs, text = text, r = r, g = g, b = b,
            }
        end
        Spring.Echo("[Caster] " .. logText)
    end

    for _, p in ipairs(S.specPlayerList) do
        local td = S.specAllData[p.teamID]
        if td then
            local prevArmy = S.specPrevArmy[p.teamID] or 0

            -- Energy stall
            local mCur, mStor, _, mInc, mExp = spGetTeamResources(p.teamID, "metal")
            local eCur, eStor, _, eInc, eExp = spGetTeamResources(p.teamID, "energy")
            if eCur and eCur < 50 and eExp and eInc and eExp > eInc * 1.3 and eInc > 20 then
                local key = p.teamID .. "_estall"
                if alertOK(key, S.SPEC_ALERT_COOLDOWN_STALL) then
                    local units = Spring.GetTeamUnits(p.teamID)
                    local px, py, pz
                    if units and #units > 0 then
                        for i = 1, math.min(3, #units) do
                            local defID = spGetUnitDefID(units[i])
                            if defID and isCommander(defID) then
                                px, py, pz = spGetUnitPosition(units[i])
                                break
                            end
                        end
                    end
                    fireAlert(key, S.SPEC_ALERT_COOLDOWN_STALL,
                        p.name .. " ENERGY STALL!",
                        1.0, 0.3, 0.1, px, py, pz)
                end
            end

            -- Metal stall
            if mCur and mCur < 20 and mExp and mInc and mExp > mInc * 1.5 and mInc > 5 then
                local key = p.teamID .. "_mstall"
                if alertOK(key, S.SPEC_ALERT_COOLDOWN_STALL) then
                    fireAlert(key, S.SPEC_ALERT_COOLDOWN_STALL,
                        p.name .. " METAL STALL!",
                        1.0, 0.5, 0.1)
                end
            end

            -- Metal overflow
            if mCur and mStor and mStor > 0 and mCur / mStor > 0.9 and mInc and mInc > 10 then
                local key = p.teamID .. "_moverflow"
                if alertOK(key, S.SPEC_ALERT_COOLDOWN_STALL) then
                    fireAlert(key, S.SPEC_ALERT_COOLDOWN_STALL,
                        p.name .. " METAL OVERFLOW!",
                        1.0, 0.8, 0.0)
                end
            end

            -- Major battle (army value dropped significantly)
            if prevArmy > 2000 and td.armyValue < prevArmy * 0.6 then
                local loss = prevArmy - td.armyValue
                if loss > 1000 then
                    local key = p.teamID .. "_battle"
                    if alertOK(key, S.SPEC_ALERT_COOLDOWN_BATTLE) then
                        local units = Spring.GetTeamUnits(p.teamID)
                        local bx, by, bz, bCount = 0, 0, 0, 0
                        if units then
                            for i = 1, #units do
                                local defID = spGetUnitDefID(units[i])
                                if defID and isCombatUnit(defID) then
                                    local ux, uy, uz = spGetUnitPosition(units[i])
                                    if ux then
                                        bx = bx + ux; by = by + uy; bz = bz + uz
                                        bCount = bCount + 1
                                    end
                                end
                            end
                        end
                        if bCount > 0 then
                            bx = bx / bCount; by = by / bCount; bz = bz / bCount
                        else
                            bx, by, bz = nil, nil, nil
                        end
                        local lossK = string.format("%.1fk", loss / 1000)
                        fireAlert(key, S.SPEC_ALERT_COOLDOWN_BATTLE,
                            p.name .. " lost " .. lossK .. " metal in battle!",
                            1.0, 0.6, 0.2, bx, by, bz)
                    end
                end
            end

            -- Being overrun
            if td.armyValue < 500 and prevArmy > 2000 then
                local myAlly = p.allyTeamID
                for _, tb in ipairs(S.specTeamBalance) do
                    if tb.allyTeamID ~= myAlly and tb.army > td.armyValue * 5 then
                        local key = p.teamID .. "_overrun"
                        if alertOK(key, S.SPEC_ALERT_COOLDOWN_OVERRUN) then
                            fireAlert(key, S.SPEC_ALERT_COOLDOWN_OVERRUN,
                                p.name .. " is being OVERRUN!",
                                1.0, 0.1, 0.1)
                        end
                        break
                    end
                end
            end

            S.specPrevArmy[p.teamID] = td.armyValue
        end
    end
end

------------------------------------------------------------------------
-- Battle detection: mark large engagements on the map
------------------------------------------------------------------------
local function detectBattles(gameSecs, dt)
    if gameSecs < 60 then return end

    -- Tick down existing battle markers
    local i = 1
    while i <= #S.specBattles do
        S.specBattles[i].timer = S.specBattles[i].timer - dt
        if S.specBattles[i].timer <= 0 then
            table.remove(S.specBattles, i)
        else
            i = i + 1
        end
    end

    S.specBattleTimer = S.specBattleTimer + dt
    if S.specBattleTimer < S.SPEC_BATTLE_SCAN_INTERVAL then return end
    S.specBattleTimer = 0

    -- Collect combat units from all teams
    local combatUnits = {}
    for _, p in ipairs(S.specPlayerList) do
        local units = Spring.GetTeamUnits(p.teamID)
        if units then
            for j = 1, #units do
                local defID = spGetUnitDefID(units[j])
                if defID and isCombatUnit(defID) then
                    local ud = UnitDefs[defID]
                    local ux, _, uz = spGetUnitPosition(units[j])
                    if ux and ud then
                        combatUnits[#combatUnits + 1] = {
                            x = ux, z = uz,
                            value = ud.metalCost or 0,
                            ally = p.allyTeamID,
                        }
                    end
                end
            end
        end
    end

    -- Grid-based cluster detection
    local cellSize = S.SPEC_BATTLE_RADIUS
    local cells = {}
    for _, cu in ipairs(combatUnits) do
        local cx = math.floor(cu.x / cellSize)
        local cz = math.floor(cu.z / cellSize)
        local key = cx .. "_" .. cz
        if not cells[key] then cells[key] = { allies = {} } end
        local cell = cells[key]
        if not cell.allies[cu.ally] then
            cell.allies[cu.ally] = { value = 0, count = 0, sumX = 0, sumZ = 0 }
        end
        local a = cell.allies[cu.ally]
        a.value = a.value + cu.value
        a.count = a.count + 1
        a.sumX = a.sumX + cu.x
        a.sumZ = a.sumZ + cu.z
    end

    -- Check cells + neighbors for battles (2+ ally teams present)
    local foundBattles = {}
    local checked = {}
    for key, cell in pairs(cells) do
        if not checked[key] then
            local mergedAllies = {}
            local cx, cz = key:match("^(-?%d+)_(-?%d+)$")
            cx = tonumber(cx)
            cz = tonumber(cz)

            if cx then
                for dx = -1, 1 do
                    for dz = -1, 1 do
                        local nKey = (cx + dx) .. "_" .. (cz + dz)
                        local nCell = cells[nKey]
                        if nCell then
                            for aID, aData in pairs(nCell.allies) do
                                if not mergedAllies[aID] then
                                    mergedAllies[aID] = { value = 0, count = 0, sumX = 0, sumZ = 0 }
                                end
                                local m = mergedAllies[aID]
                                m.value = m.value + aData.value
                                m.count = m.count + aData.count
                                m.sumX  = m.sumX + aData.sumX
                                m.sumZ  = m.sumZ + aData.sumZ
                            end
                        end
                    end
                end

                local allyCount = 0
                local totalValue = 0
                local totalX, totalZ, totalN = 0, 0, 0
                for _, aData in pairs(mergedAllies) do
                    allyCount = allyCount + 1
                    totalValue = totalValue + aData.value
                    totalX = totalX + aData.sumX
                    totalZ = totalZ + aData.sumZ
                    totalN = totalN + aData.count
                end

                if allyCount >= 2 and totalValue >= S.SPEC_BATTLE_MIN_VALUE and totalN >= 6 then
                    local bx = totalX / totalN
                    local bz = totalZ / totalN
                    local isDup = false
                    for _, fb in ipairs(foundBattles) do
                        local ddx = fb.x - bx
                        local ddz = fb.z - bz
                        if ddx * ddx + ddz * ddz < cellSize * cellSize then
                            isDup = true
                            if totalValue > fb.totalValue then
                                fb.x = bx; fb.z = bz
                                fb.totalValue = totalValue
                                fb.unitCount = totalN
                            end
                            break
                        end
                    end
                    if not isDup then
                        foundBattles[#foundBattles + 1] = {
                            x = bx, z = bz,
                            totalValue = totalValue,
                            unitCount = totalN,
                        }
                    end
                    for dx = -1, 1 do
                        for dz = -1, 1 do
                            checked[(cx + dx) .. "_" .. (cz + dz)] = true
                        end
                    end
                end
            end
            checked[key] = true
        end
    end

    -- Create battle markers
    for _, battle in ipairs(foundBattles) do
        local alreadyMarked = false
        for _, sb in ipairs(S.specBattles) do
            local ddx = sb.x - battle.x
            local ddz = sb.z - battle.z
            if ddx * ddx + ddz * ddz < cellSize * cellSize * 4 then
                alreadyMarked = true
                if battle.totalValue > (sb.value or 0) then
                    sb.x = battle.x; sb.z = battle.z
                    sb.value = battle.totalValue
                    sb.timer = S.SPEC_BATTLE_DURATION
                end
                break
            end
        end
        if not alreadyMarked then
            local by = Spring.GetGroundHeight(battle.x, battle.z) or 0
            local label = string.format("BATTLE! %dk (%d units)",
                math.floor(battle.totalValue / 1000), battle.unitCount)
            S.specBattles[#S.specBattles + 1] = {
                x = battle.x, z = battle.z,
                value = battle.totalValue,
                timer = S.SPEC_BATTLE_DURATION,
                label = label,
            }
            addSpecMarker(battle.x, by, battle.z, label, 1.0, 0.4, 0.2, S.SPEC_BATTLE_DURATION)
        end
    end
end

------------------------------------------------------------------------
-- widget:Initialize
------------------------------------------------------------------------
function widget:Initialize()
    -- Check if we are spectating
    local _, _, isSpec = Spring.GetSpectatingState()
    if not isSpec then
        Spring.Echo("[Caster] Not spectating — widget disabled. Use as spectator or in replays.")
        widgetHandler:RemoveWidget()
        return
    end

    vsx, vsy = Spring.GetViewGeometry()

    -- Load modules
    RENDERING = VFS.Include("LuaUI/Widgets/caster_modules/rendering.lua")

    local UC = VFS.Include("LuaUI/Widgets/caster_modules/unit_classify.lua").init({
        S = S, artyNames = artyNames,
    })
    isMex        = UC.isMex
    isFactory    = UC.isFactory
    isNano       = UC.isNano
    isT2Factory  = UC.isT2Factory
    isCombatUnit = UC.isCombatUnit
    isAntiAir    = UC.isAntiAir
    classifyUnit = UC.classifyUnit
    isAirUnit    = UC.isAirUnit

    local UH = VFS.Include("LuaUI/Widgets/caster_modules/unit_helpers.lua").init({
        isT2Factory = isT2Factory,
    })
    isCommander    = UH.isCommander
    isBuilder      = UH.isBuilder
    isUnitIdle     = UH.isUnitIdle
    isUnitFinished = UH.isUnitFinished

    -- Initialize player list
    initPlayerList()

    Spring.Echo("[Caster] BAR Caster Widget v1.0 loaded (F9=Toggle, PageUp/PageDown=Switch Player)")
end

function widget:Shutdown()
    Spring.Echo("[Caster] Widget unloaded.")
end

------------------------------------------------------------------------
-- widget:ViewResize
------------------------------------------------------------------------
function widget:ViewResize(newX, newY)
    vsx = newX
    vsy = newY
end

------------------------------------------------------------------------
-- widget:Update — data collection (once per second)
------------------------------------------------------------------------
function widget:Update(dt)
    timeSinceUpdate = timeSinceUpdate + dt
    if timeSinceUpdate < UPDATE_INTERVAL then return end
    timeSinceUpdate = 0

    local gameSecs = spGetGameSeconds()

    updateTracking(gameSecs)
    checkAlerts(gameSecs)
    detectBattles(gameSecs, UPDATE_INTERVAL)
    updateSpecMarkers(UPDATE_INTERVAL)

    -- OBS export
    if S.specOBSExport then
        S.specOBSTimer = S.specOBSTimer + UPDATE_INTERVAL
        if S.specOBSTimer >= 3 then
            S.specOBSTimer = 0
            local mins = math.floor(gameSecs / 60)
            local secs = math.floor(gameSecs % 60)
            if #S.specTeamBalance >= 2 then
                local t1 = S.specTeamBalance[1]
                local t2 = S.specTeamBalance[2]
                Spring.Echo(string.format(
                    "[CasterOBS] %d:%02d | T1: +%.0fM %.0fk Army | T2: +%.0fM %.0fk Army | %s",
                    mins, secs,
                    t1.metal, t1.army / 1000,
                    t2.metal, t2.army / 1000,
                    S.specBalanceLabel))
            end
            local watchTD = S.specAllData[S.specWatchTeamID]
            if watchTD then
                local tradeVal = (watchTD.metalKilled or 0) - (watchTD.metalLost or 0)
                Spring.Echo(string.format(
                    "[CasterOBS:PLAYER] %s | +%.0fM/s | Army: %.0fk | Trade: %+.0fk",
                    S.specWatchName or "?",
                    watchTD.metalIncome,
                    watchTD.armyValue / 1000,
                    tradeVal / 1000))
            end
            if #S.specAlertLog > 0 then
                local latest = S.specAlertLog[#S.specAlertLog]
                if latest and gameSecs - latest.time < 10 then
                    Spring.Echo("[CasterOBS:WARN] " .. latest.text)
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- widget:UnitDestroyed — track kills/losses per team
------------------------------------------------------------------------
function widget:UnitDestroyed(unitID, unitDefID, unitTeam,
                              attackerID, attackerDefID, attackerTeam)
    if unitDefID and unitTeam and attackerTeam then
        local ud = UnitDefs[unitDefID]
        if ud and (ud.metalCost or 0) > 50 then
            local cost = ud.metalCost or 0
            local tdLost = S.specAllData[unitTeam]
            if tdLost then
                tdLost.metalLost = (tdLost.metalLost or 0) + cost
            end
            local tdKill = S.specAllData[attackerTeam]
            if tdKill then
                tdKill.metalKilled = (tdKill.metalKilled or 0) + cost
            end
        end
    end
end

------------------------------------------------------------------------
-- widget:GameOver — MVP calculation
------------------------------------------------------------------------
function widget:GameOver(winningAllyTeams)
    S.gameOver = true
    if #S.specPlayerList < 2 then return end

    S.specMVPs = {}
    local bestTrade = { name = "?", value = -999999 }
    local bestEco   = { name = "?", value = 0 }
    local bestKills = { name = "?", value = 0 }
    local bestT2    = { name = "?", value = 999999 }

    for _, p in ipairs(S.specPlayerList) do
        local td = S.specAllData[p.teamID]
        if td then
            local tradeVal = (td.metalKilled or 0) - (td.metalLost or 0)
            if tradeVal > bestTrade.value then
                bestTrade = { name = p.name, value = tradeVal }
            end
            if td.peakMetal > bestEco.value then
                bestEco = { name = p.name, value = td.peakMetal }
            end
            if (td.metalKilled or 0) > bestKills.value then
                bestKills = { name = p.name, value = td.metalKilled or 0 }
            end
            if td.hasT2 and td.t2Time > 0 and td.t2Time < bestT2.value then
                bestT2 = { name = p.name, value = td.t2Time }
            end
        end
    end

    local function fmtK(v)
        return math.abs(v) >= 1000
            and string.format("%.1fk", v / 1000)
            or string.format("%.0f", v)
    end

    if bestKills.value > 0 then
        S.specMVPs[#S.specMVPs + 1] = {
            category = "Top Killer", name = bestKills.name,
            label = fmtK(bestKills.value) .. " metal destroyed",
        }
    end
    if bestTrade.value > -999999 then
        S.specMVPs[#S.specMVPs + 1] = {
            category = "Best Trade", name = bestTrade.name,
            label = string.format("%+s metal", fmtK(bestTrade.value)),
        }
    end
    if bestEco.value > 0 then
        S.specMVPs[#S.specMVPs + 1] = {
            category = "Peak Eco", name = bestEco.name,
            label = string.format("+%.0f metal/s", bestEco.value),
        }
    end
    if bestT2.value < 999999 then
        local m = math.floor(bestT2.value / 60)
        local s = math.floor(bestT2.value % 60)
        S.specMVPs[#S.specMVPs + 1] = {
            category = "1st T2", name = bestT2.name,
            label = string.format("%d:%02d", m, s),
        }
    end

    if #S.specMVPs > 0 then
        Spring.Echo("[Caster] === MVPs ===")
        for _, mvp in ipairs(S.specMVPs) do
            Spring.Echo(string.format("[Caster]   %s: %s (%s)", mvp.category, mvp.name, mvp.label))
        end
    end
end

------------------------------------------------------------------------
-- widget:KeyPress
------------------------------------------------------------------------
function widget:KeyPress(key, mods, isRepeat)
    -- F9: toggle panel
    if key == 0x0128 then  -- F9
        panelVisible = not panelVisible
        return true
    end
    -- PageUp/PageDown: switch player
    if key == 0x0119 then  -- PageUp
        selectPlayer(S.specSelectedIdx - 1)
        return true
    end
    if key == 0x011A then  -- PageDown
        selectPlayer(S.specSelectedIdx + 1)
        return true
    end
    return false
end

------------------------------------------------------------------------
-- widget:TextCommand — chat commands
------------------------------------------------------------------------
function widget:TextCommand(command)
    if command == "casterobs" then
        S.specOBSExport = not S.specOBSExport
        Spring.Echo("[Caster] OBS export " .. (S.specOBSExport and "ON" or "OFF"))
        return true
    end
    if command == "castercast" then
        S.specAutoSwitch = not S.specAutoSwitch
        S.specAutoSwitchTimer = 0
        Spring.Echo("[Caster] Commentator mode " .. (S.specAutoSwitch and "ON" or "OFF"))
        return true
    end
    if command == "castersort" then
        local modes = S.specSortModes
        local idx = 1
        for i, m in ipairs(modes) do
            if m == S.specSortMode then idx = i; break end
        end
        S.specSortMode = modes[(idx % #modes) + 1]
        Spring.Echo("[Caster] Sorted by: " .. S.specSortLabels[S.specSortMode])
        return true
    end
    return false
end

------------------------------------------------------------------------
-- Rendering helpers
------------------------------------------------------------------------
local function setColor(c)
    RENDERING.setColor(c)
end

local function drawDivider(lx1, ly, lx2)
    RENDERING.drawDivider(lx1, ly, lx2, C.divider)
end

local function drawSectionBg(lx1, ly1, lx2, ly2)
    RENDERING.drawSectionBg(lx1, ly1, lx2, ly2, C.bgLight)
end

------------------------------------------------------------------------
-- widget:DrawScreen — main panel rendering
------------------------------------------------------------------------
function widget:DrawScreen()
    if not panelVisible then return end
    if #S.specPlayerList == 0 then return end

    -- Draw in-world markers first
    drawSpecMarkers()

    -- Panel position
    local px, py
    if panelPosX and panelPosY then
        px = panelPosX
        py = panelPosY
    else
        px = vsx - panelWidth - panelMargin
        py = vsy - panelMargin - panelTopOffset
    end

    local x1 = px
    local x2 = px + panelWidth
    local tx = x1 + 12
    local ty = py - 10

    -- Panel background (drawn first using cached height from previous frame)
    local startY = ty
    gl.Color(C.bg[1], C.bg[2], C.bg[3], C.bg[4])
    gl.Rect(x1, py, x2, py - lastPanelHeight)
    -- Top accent line
    gl.Color(0.4, 0.6, 1.0, 0.6)
    gl.Rect(x1, py, x2, py - 2)

    -- === Title ===
    setColor(C.title)
    gl.Text("BAR CASTER", tx, ty - fontSize, fontSize + 2, "o")
    gl.Color(1.0, 0.6, 0.2, 1.0)
    gl.Text("SPECTATOR", tx + 130, ty - fontSize, fontSize, "o")
    if S.specAutoSwitch then
        gl.Color(0.3, 1.0, 0.5, 1.0)
        gl.Text("AUTO", tx + 230, ty - fontSize, fontSize - 3, "o")
    end
    setColor(C.textDim)
    gl.Text("v1.0", x2 - 40, ty - fontSize, fontSize - 3, "o")
    ty = ty - 26

    -- === Player selection bar ===
    drawSectionBg(x1 + 2, ty + 2, x2 - 2, ty - 20)
    gl.Color(0.5, 0.8, 1.0, 0.9)
    gl.Text("<<", tx, ty - fontSize + 1, fontSize, "o")
    gl.Text(">>", x2 - 30, ty - fontSize + 1, fontSize, "o")
    local watchFaction = ""
    local cur = S.specPlayerList[S.specSelectedIdx]
    if cur then watchFaction = cur.faction or "" end
    if watchFaction == "Cortex" then gl.Color(0.5, 0.7, 1.0, 1.0)
    elseif watchFaction == "Armada" then gl.Color(1.0, 0.7, 0.4, 1.0)
    elseif watchFaction == "Legion" then gl.Color(0.7, 1.0, 0.5, 1.0)
    else setColor(C.text) end
    gl.Text(string.format("%s (%s)", S.specWatchName or "?", watchFaction),
        tx + 30, ty - fontSize + 1, fontSize, "o")
    ty = ty - 24

    -- === Watched player stats ===
    local watchTD = S.specAllData[S.specWatchTeamID]
    if watchTD then
        drawDivider(x1 + 8, ty, x2 - 8)
        ty = ty - 6

        setColor(C.metalColor)
        gl.Text(string.format("Metal: +%.0f/s", watchTD.metalIncome), tx, ty - fontSize, fontSize - 2, "o")
        gl.Color(1.0, 1.0, 0.3, 1.0)
        gl.Text(string.format("Energy: +%.0f/s", watchTD.energyIncome), tx + 130, ty - fontSize, fontSize - 2, "o")
        ty = ty - lineHeight

        setColor(C.textDim)
        local t2str = watchTD.hasT2 and "T2" or ""
        gl.Text(string.format("Mex: %d  Fac: %d  Nano: %d  %s",
            watchTD.mexCount, watchTD.factoryCount, watchTD.nanoCount, t2str),
            tx, ty - fontSize, fontSize - 3, "o")
        ty = ty - lineHeight

        -- Army value
        local armyStr = watchTD.armyValue >= 1000
            and string.format("%.1fk", watchTD.armyValue / 1000)
            or string.format("%d", watchTD.armyValue)
        setColor(C.text)
        gl.Text(string.format("Army: %s  |  %s", armyStr, watchTD.armyComp or ""),
            tx, ty - fontSize, fontSize - 3, "o")
        ty = ty - lineHeight
    end

    -- === Team balance ===
    if #S.specTeamBalance >= 2 then
        drawDivider(x1 + 8, ty, x2 - 8)
        ty = ty - 6
        setColor(C.sectionHead)
        gl.Text("TEAM BALANCE", tx, ty - fontSize, fontSize - 2, "o")
        ty = ty - lineHeight

        local t1 = S.specTeamBalance[1]
        local t2 = S.specTeamBalance[2]

        -- Balance bar
        local barX1 = x1 + 12
        local barX2 = x2 - 12
        local barW = barX2 - barX1
        local barH = 12
        local barY2 = ty - barH
        local balPct = S.specBalancePct / 100

        gl.Color(0.1, 0.1, 0.15, 0.8)
        gl.Rect(barX1, ty, barX2, barY2)
        gl.Color(0.3, 0.5, 1.0, 0.7)
        gl.Rect(barX1, ty, barX1 + barW * balPct, barY2)
        gl.Color(1.0, 0.4, 0.3, 0.7)
        gl.Rect(barX1 + barW * balPct, ty, barX2, barY2)
        gl.Color(1, 1, 1, 0.4)
        gl.Rect(barX1 + barW * 0.5 - 1, ty, barX1 + barW * 0.5 + 1, barY2)

        if S.specBalanceLabel ~= "" then
            local diff = math.abs(S.specBalancePct - 50)
            if diff <= 5 then gl.Color(0.7, 0.7, 0.7, 0.9)
            elseif S.specBalancePct > 50 then gl.Color(0.4, 0.6, 1.0, 1.0)
            else gl.Color(1.0, 0.5, 0.4, 1.0) end
            gl.Text(S.specBalanceLabel, barX1 + barW / 2, barY2 - 1, fontSize - 4, "oc")
        end
        ty = ty - barH - 4

        -- Team summary lines
        local function fmtK(v) return v >= 1000 and string.format("%.1fk", v / 1000) or string.format("%.0f", v) end
        gl.Color(0.3, 0.5, 1.0, 1.0)
        gl.Text(string.format("T1 (%dp)", t1.players), tx, ty - fontSize, fontSize - 3, "o")
        setColor(C.metalColor)
        gl.Text(string.format("+%.0f", t1.metal), tx + 65, ty - fontSize, fontSize - 3, "o")
        setColor(C.textDim)
        gl.Text(string.format("%s | %dM", fmtK(t1.army), t1.mex), tx + 120, ty - fontSize, fontSize - 3, "o")
        if t1.t2Count > 0 then
            gl.Color(0.3, 1.0, 0.8, 1.0)
            gl.Text(string.format("%dxT2", t1.t2Count), x2 - 45, ty - fontSize, fontSize - 3, "o")
        end
        ty = ty - lineHeight + 2

        gl.Color(1.0, 0.4, 0.3, 1.0)
        gl.Text(string.format("T2 (%dp)", t2.players), tx, ty - fontSize, fontSize - 3, "o")
        setColor(C.metalColor)
        gl.Text(string.format("+%.0f", t2.metal), tx + 65, ty - fontSize, fontSize - 3, "o")
        setColor(C.textDim)
        gl.Text(string.format("%s | %dM", fmtK(t2.army), t2.mex), tx + 120, ty - fontSize, fontSize - 3, "o")
        if t2.t2Count > 0 then
            gl.Color(0.3, 1.0, 0.8, 1.0)
            gl.Text(string.format("%dxT2", t2.t2Count), x2 - 45, ty - fontSize, fontSize - 3, "o")
        end
        ty = ty - lineHeight + 2

        -- Team eco graph
        local h1 = S.specTeamMetalHistory[t1.allyTeamID]
        local h2 = S.specTeamMetalHistory[t2.allyTeamID]
        if h1 and h2 then
            setColor(C.sectionHead)
            gl.Text("TEAM ECO (Metal/s, 30s)", tx, ty - fontSize, fontSize - 3, "o")
            ty = ty - lineHeight
            local teamPeak = 1
            for j = 1, GRAPH_HISTORY do
                if h1[j] > teamPeak then teamPeak = h1[j] end
                if h2[j] > teamPeak then teamPeak = h2[j] end
            end
            local teamSeries = {
                { data = h1, color = {0.3, 0.5, 1.0}, label = string.format("T1 +%.0f", t1.metal) },
                { data = h2, color = {1.0, 0.4, 0.3}, label = string.format("T2 +%.0f", t2.metal) },
            }
            RENDERING.drawMultiLineGraph(tx, ty, panelWidth - 30, 40, teamSeries, teamPeak)
            ty = ty - 44
            for li = 1, 2 do
                local s = teamSeries[li]
                gl.Color(s.color[1], s.color[2], s.color[3], 1.0)
                gl.Rect(tx + (li - 1) * 100, ty - 1, tx + (li - 1) * 100 + 8, ty - 7)
                gl.Text(s.label, tx + (li - 1) * 100 + 11, ty - fontSize + 2, fontSize - 4, "o")
            end
            ty = ty - lineHeight + 2
        end
    end

    -- === Territory control ===
    if S.specControlCols > 0 and #S.specTeamBalance >= 2 then
        drawDivider(x1 + 8, ty, x2 - 8)
        ty = ty - 6
        setColor(C.sectionHead)
        gl.Text("TERRITORY CONTROL", tx, ty - fontSize, fontSize - 2, "o")
        ty = ty - lineHeight

        local cols = S.specControlCols
        local rows = S.specControlRows
        local mapW = panelWidth - 30
        local mapH = math.floor(mapW * rows / cols)
        if mapH > 60 then mapH = 60 end
        local cellW = mapW / cols
        local cellH = mapH / rows
        local ally1 = S.specTeamBalance[1].allyTeamID
        local ally2 = S.specTeamBalance[2].allyTeamID

        gl.Color(0.05, 0.05, 0.08, 0.6)
        gl.Rect(tx, ty, tx + mapW, ty - mapH)

        for gKey, gData in pairs(S.specControlGrid) do
            local gx, gz = gKey:match("^(-?%d+)_(-?%d+)$")
            gx = tonumber(gx)
            gz = tonumber(gz)
            if gx and gz and gx >= 0 and gz >= 0 and gx < cols and gz < rows then
                local c1 = gData[ally1] or 0
                local c2 = gData[ally2] or 0
                local total = c1 + c2
                if total > 0 then
                    local ppx = tx + gx * cellW
                    local ppy = ty - gz * cellH
                    local alpha = math.min(0.6, total / 15)
                    if c1 > c2 then gl.Color(0.3, 0.5, 1.0, alpha)
                    elseif c2 > c1 then gl.Color(1.0, 0.4, 0.3, alpha)
                    else gl.Color(0.6, 0.6, 0.2, alpha) end
                    gl.Rect(ppx, ppy, ppx + cellW, ppy - cellH)
                end
            end
        end
        ty = ty - mapH - 4
    end

    -- === Eco comparison graph (top 4 players) ===
    if #S.specPlayerList > 1 then
        drawDivider(x1 + 8, ty, x2 - 8)
        ty = ty - 6
        setColor(C.sectionHead)
        gl.Text("ECO COMPARISON (Metal/s, 30s)", tx, ty - fontSize, fontSize - 2, "o")
        ty = ty - lineHeight

        local ecoRanked = {}
        for _, p in ipairs(S.specPlayerList) do
            local td = S.specAllData[p.teamID]
            if td and td.metalHistory then
                ecoRanked[#ecoRanked + 1] = {
                    name = p.name, metal = td.metalIncome,
                    history = td.metalHistory, faction = p.faction,
                }
            end
        end
        table.sort(ecoRanked, function(a, b) return a.metal > b.metal end)

        local lineColors = {
            {0.3, 0.7, 1.0}, {1.0, 0.4, 0.3},
            {0.3, 1.0, 0.5}, {1.0, 0.8, 0.2},
        }
        local series = {}
        local maxShow = math.min(#ecoRanked, 4)
        local graphPeak = 1
        for i = 1, maxShow do
            series[i] = { data = ecoRanked[i].history, color = lineColors[i], label = ecoRanked[i].name }
            if ecoRanked[i].metal > graphPeak then graphPeak = ecoRanked[i].metal end
        end
        for _, s in ipairs(series) do
            for j = 1, #s.data do
                if s.data[j] > graphPeak then graphPeak = s.data[j] end
            end
        end

        RENDERING.drawMultiLineGraph(tx, ty, panelWidth - 30, 50, series, graphPeak)
        ty = ty - 54

        local legColW = math.floor((panelWidth - 30) / 2)
        for i = 1, maxShow do
            local c = lineColors[i]
            local nameStr = ecoRanked[i].name
            if string.len(nameStr) > 8 then nameStr = string.sub(nameStr, 1, 7) .. ".." end
            local col = (i - 1) % 2
            local legX = tx + col * legColW
            if i == 3 then ty = ty - lineHeight + 4 end
            gl.Color(c[1], c[2], c[3], 1.0)
            gl.Rect(legX, ty - 1, legX + 8, ty - 7)
            gl.Text(string.format("%s +%.0f", nameStr, ecoRanked[i].metal),
                legX + 11, ty - fontSize + 2, fontSize - 4, "o")
        end
        ty = ty - lineHeight + 2
    end

    -- === Army composition of watched player ===
    if S.specWatchTeamID then
        local watchTD2 = S.specAllData[S.specWatchTeamID]
        if watchTD2 and watchTD2.armyCompHistory and #watchTD2.armyCompHistory >= 3 then
            drawDivider(x1 + 8, ty, x2 - 8)
            ty = ty - 6
            setColor(C.sectionHead)
            gl.Text("ARMY MIX: " .. (S.specWatchName or "?"), tx, ty - fontSize, fontSize - 2, "o")
            ty = ty - lineHeight

            local ach = watchTD2.armyCompHistory
            local barCount = #ach
            local graphW = panelWidth - 30
            local graphH = 28
            local barW = math.max(2, math.floor(graphW / barCount))
            for bi = 1, barCount do
                local snap = ach[bi]
                local total = snap.raider + snap.assault + snap.skirm + snap.air
                if total > 0 then
                    local bx = tx + (bi - 1) * barW
                    local segments = {
                        { count = snap.raider,  r = 0.3, g = 0.6, b = 1.0 },
                        { count = snap.assault, r = 1.0, g = 0.4, b = 0.3 },
                        { count = snap.skirm,   r = 1.0, g = 0.8, b = 0.2 },
                        { count = snap.air,     r = 0.3, g = 1.0, b = 0.5 },
                    }
                    local yOff = 0
                    for _, seg in ipairs(segments) do
                        if seg.count > 0 then
                            local segH = (seg.count / total) * graphH
                            gl.Color(seg.r, seg.g, seg.b, 0.8)
                            gl.Rect(bx, ty - yOff, bx + barW - 1, ty - yOff - segH)
                            yOff = yOff + segH
                        end
                    end
                end
            end
            ty = ty - graphH - 4

            local legItems = {
                { "R", 0.3, 0.6, 1.0 }, { "A", 1.0, 0.4, 0.3 },
                { "S", 1.0, 0.8, 0.2 }, { "Air", 0.3, 1.0, 0.5 },
            }
            for li, item in ipairs(legItems) do
                gl.Color(item[2], item[3], item[4], 1.0)
                gl.Text(item[1], tx + (li - 1) * 40, ty - fontSize + 2, fontSize - 4, "o")
            end
            ty = ty - lineHeight + 2
        end
    end

    -- === Player ranking ===
    if #S.specPlayerList > 1 then
        drawDivider(x1 + 8, ty, x2 - 8)
        ty = ty - 6
        setColor(C.sectionHead)
        local sortLabel = S.specSortLabels[S.specSortMode] or "Metal/s"
        gl.Text("RANKING (" .. sortLabel .. ") /castersort", tx, ty - fontSize, fontSize - 2, "o")
        ty = ty - lineHeight

        local ranked = {}
        local sortKey = S.specSortMode
        for _, p in ipairs(S.specPlayerList) do
            local td = S.specAllData[p.teamID]
            if td then
                local killed = td.metalKilled or 0
                local lost = td.metalLost or 0
                ranked[#ranked + 1] = {
                    name = p.name, faction = p.faction, teamID = p.teamID,
                    metal = td.metalIncome, mex = td.mexCount,
                    hasT2 = td.hasT2, army = td.armyValue,
                    armyComp = td.armyComp or "",
                    aaCount = td.aaCount or 0, airCount = td.airCount or 0,
                    idleArmy = td.idleArmy or 0, totalArmy = td.totalArmy or 0,
                    metalKilled = killed, metalLost = lost,
                    trade = killed - lost,
                    reclaim = td.reclaimIncome or 0,
                }
            end
        end
        table.sort(ranked, function(a, b) return (a[sortKey] or 0) > (b[sortKey] or 0) end)

        local maxShow = math.min(#ranked, 8)
        for i = 1, maxShow do
            local r = ranked[i]
            local isSelected = (r.teamID == S.specWatchTeamID)
            if isSelected then
                gl.Color(0.15, 0.25, 0.40, 0.6)
                gl.Rect(x1 + 4, ty + 2, x2 - 4, ty - fontSize - 2)
            end

            -- Rank
            setColor(C.textDim)
            gl.Text(string.format("%d.", i), tx, ty - fontSize, fontSize - 3, "o")

            -- Name (colored by faction)
            if r.faction == "Cortex" then gl.Color(0.5, 0.7, 1.0, 1.0)
            elseif r.faction == "Armada" then gl.Color(1.0, 0.7, 0.4, 1.0)
            elseif r.faction == "Legion" then gl.Color(0.7, 1.0, 0.5, 1.0)
            else setColor(C.text) end
            local nameStr = r.name
            if string.len(nameStr) > 14 then nameStr = string.sub(nameStr, 1, 13) .. ".." end
            gl.Text(nameStr, tx + 18, ty - fontSize, fontSize - 3, "o")

            -- Metal/s
            if sortKey == "metal" then gl.Color(0.4, 1.0, 0.9, 1.0) else setColor(C.metalColor) end
            gl.Text(string.format("+%.0f", r.metal), tx + 120, ty - fontSize, fontSize - 3, "o")

            -- Reclaim
            if r.reclaim > 0.5 then
                if sortKey == "reclaim" then gl.Color(0.4, 1.0, 0.9, 1.0)
                else gl.Color(0.8, 0.6, 0.3, 0.8) end
                gl.Text(string.format("R+%.0f", r.reclaim), tx + 155, ty - fontSize, fontSize - 4, "o")
            end

            -- Mex
            if sortKey == "mex" then gl.Color(0.4, 1.0, 0.9, 1.0) else setColor(C.textDim) end
            gl.Text(string.format("%dM", r.mex), tx + 195, ty - fontSize, fontSize - 3, "o")

            -- T2
            if r.hasT2 then
                gl.Color(0.3, 1.0, 0.8, 1.0)
                gl.Text("T2", tx + 218, ty - fontSize, fontSize - 3, "o")
            end

            -- Army value + idle
            if r.army > 0 then
                local idlePct = r.totalArmy > 0 and (r.idleArmy / r.totalArmy * 100) or 0
                if r.idleArmy >= 4 and idlePct >= 15 then
                    if idlePct > 50 then gl.Color(1.0, 0.3, 0.2, 1.0)
                    elseif idlePct > 25 then gl.Color(1.0, 0.5, 0.1, 1.0)
                    else gl.Color(1.0, 0.8, 0.2, 0.9) end
                    gl.Text(string.format("%d%%z", math.floor(idlePct)), tx + 238, ty - fontSize, fontSize - 4, "o")
                end
                if sortKey == "army" then gl.Color(0.4, 1.0, 0.9, 1.0) else setColor(C.textDim) end
                local armyStr = r.army >= 1000
                    and string.format("%.1fk", r.army / 1000)
                    or string.format("%d", r.army)
                gl.Text(armyStr, x2 - 55, ty - fontSize, fontSize - 3, "o")
            end
            ty = ty - lineHeight + 4

            -- Second line: composition + trade balance
            if r.armyComp ~= "" or (r.metalKilled > 0 or r.metalLost > 0) then
                setColor(C.textDim)
                local compStr = "    " .. (r.armyComp or "")
                if r.aaCount > 0 then compStr = compStr .. " " .. r.aaCount .. "AA" end
                if r.aaCount == 0 and r.totalArmy >= 3 then compStr = compStr .. " !noAA" end
                gl.Text(compStr, tx, ty - fontSize, fontSize - 4, "o")

                if r.metalKilled > 0 or r.metalLost > 0 then
                    local tradeVal = r.trade
                    local tradeStr
                    if math.abs(tradeVal) >= 1000 then
                        tradeStr = string.format("%+.1fk", tradeVal / 1000)
                    else
                        tradeStr = string.format("%+d", tradeVal)
                    end
                    if tradeVal > 0 then gl.Color(0.3, 1.0, 0.5, 0.9)
                    elseif tradeVal < 0 then gl.Color(1.0, 0.4, 0.3, 0.9)
                    else setColor(C.textDim) end
                    if sortKey == "trade" then gl.Color(0.4, 1.0, 0.9, 1.0) end
                    gl.Text(tradeStr, x2 - 55, ty - fontSize, fontSize - 4, "o")
                end
                ty = ty - lineHeight + 6
            end
        end
        ty = ty - 2

        -- T2 race
        if S.specFirstT2 then
            drawDivider(x1 + 8, ty, x2 - 8)
            ty = ty - 6
            gl.Color(0.3, 1.0, 0.8, 1.0)
            local t2m = math.floor(S.specFirstT2.time / 60)
            local t2s = math.floor(S.specFirstT2.time % 60)
            gl.Text(string.format("1st T2: %s (%s) %d:%02d",
                S.specFirstT2.name, S.specFirstT2.faction, t2m, t2s),
                tx, ty - fontSize, fontSize - 2, "o")
            ty = ty - lineHeight
            if #S.specT2List > 1 then
                for i = 2, math.min(#S.specT2List, 4) do
                    local t2 = S.specT2List[i]
                    setColor(C.textDim)
                    local m = math.floor(t2.time / 60)
                    local s = math.floor(t2.time % 60)
                    gl.Text(string.format("  %d. %s (%s) %d:%02d",
                        i, t2.name, t2.faction, m, s),
                        tx, ty - fontSize, fontSize - 3, "o")
                    ty = ty - lineHeight + 4
                end
            end
        end
    end

    -- === Alert log ===
    if #S.specAlertLog > 0 then
        drawDivider(x1 + 8, ty, x2 - 8)
        ty = ty - 6
        setColor(C.sectionHead)
        gl.Text("EVENTS", tx, ty - fontSize, fontSize - 2, "o")
        ty = ty - lineHeight
        local showCount = math.min(#S.specAlertLog, 5)
        for i = #S.specAlertLog, #S.specAlertLog - showCount + 1, -1 do
            local entry = S.specAlertLog[i]
            if entry then
                gl.Color(entry.r or 0.8, entry.g or 0.8, entry.b or 0.8, 0.9)
                local entryText = entry.text
                if string.len(entryText) > 40 then entryText = string.sub(entryText, 1, 39) .. ".." end
                gl.Text(entryText, tx, ty - fontSize, fontSize - 3, "o")
                ty = ty - lineHeight + 4
            end
        end
    end

    -- === Event timeline ===
    if #S.specTimeline > 0 then
        drawDivider(x1 + 8, ty, x2 - 8)
        ty = ty - 6
        setColor(C.sectionHead)
        gl.Text("TIMELINE", tx, ty - fontSize, fontSize - 2, "o")
        ty = ty - lineHeight

        local tlW = panelWidth - 30
        local tlH = 16
        local gameSecs = spGetGameSeconds()
        local maxTime = math.max(gameSecs, 60)

        gl.Color(0.08, 0.08, 0.12, 0.7)
        gl.Rect(tx, ty, tx + tlW, ty - tlH)

        for mins = 5, math.floor(maxTime / 60), 5 do
            local tickX = tx + (mins * 60 / maxTime) * tlW
            gl.Color(0.3, 0.3, 0.4, 0.5)
            gl.Rect(tickX, ty, tickX + 1, ty - tlH)
            gl.Color(0.5, 0.5, 0.5, 0.6)
            gl.Text(string.format("%d'", mins), tickX + 2, ty - tlH + 1, fontSize - 5, "o")
        end

        for _, ev in ipairs(S.specTimeline) do
            local evX = tx + (ev.time / maxTime) * tlW
            gl.Color(ev.r or 0.8, ev.g or 0.8, ev.b or 0.8, 0.9)
            gl.Rect(evX - 1, ty, evX + 1, ty - tlH)
        end

        local nowX = tx + (gameSecs / maxTime) * tlW
        gl.Color(1, 1, 1, 0.8)
        gl.Rect(nowX - 1, ty + 1, nowX + 1, ty - tlH - 1)
        ty = ty - tlH - 4
    end

    -- === MVP display (game over) ===
    if S.gameOver and #S.specMVPs > 0 then
        drawDivider(x1 + 8, ty, x2 - 8)
        ty = ty - 6
        gl.Color(1.0, 0.85, 0.2, 1.0)
        gl.Text("MVPs", tx, ty - fontSize, fontSize, "o")
        ty = ty - lineHeight
        for _, mvp in ipairs(S.specMVPs) do
            gl.Color(0.8, 0.7, 0.3, 1.0)
            gl.Text(mvp.category .. ":", tx, ty - fontSize, fontSize - 3, "o")
            gl.Color(1.0, 1.0, 1.0, 1.0)
            gl.Text(mvp.name, tx + 90, ty - fontSize, fontSize - 3, "o")
            setColor(C.textDim)
            gl.Text(mvp.label, tx + 180, ty - fontSize, fontSize - 4, "o")
            ty = ty - lineHeight + 2
        end
    end

    -- Update cached panel height for next frame's background
    local endY = ty - 10
    lastPanelHeight = startY - endY + 20
end

------------------------------------------------------------------------
-- Panel dragging
------------------------------------------------------------------------
function widget:IsAbove(mx, my)
    if not panelVisible then return false end
    local px = panelPosX or (vsx - panelWidth - panelMargin)
    local py = panelPosY or (vsy - panelMargin - panelTopOffset)
    return mx >= px and mx <= px + panelWidth and my >= py - 800 and my <= py
end

function widget:MousePress(mx, my, button)
    if button ~= 1 then return false end
    if not panelVisible then return false end
    local px = panelPosX or (vsx - panelWidth - panelMargin)
    local py = panelPosY or (vsy - panelMargin - panelTopOffset)
    if mx >= px and mx <= px + panelWidth and my >= py - 30 and my <= py then
        panelDragging = true
        panelDragOffsetX = mx - px
        panelDragOffsetY = my - py
        return true
    end
    return false
end

function widget:MouseMove(mx, my, dx, dy, button)
    if panelDragging then
        panelPosX = mx - panelDragOffsetX
        panelPosY = my - panelDragOffsetY
        return true
    end
    return false
end

function widget:MouseRelease(mx, my, button)
    if panelDragging then
        panelDragging = false
        return true
    end
    return false
end
