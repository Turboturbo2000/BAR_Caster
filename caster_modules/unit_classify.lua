------------------------------------------------------------------------
-- caster_modules/unit_classify.lua
-- Unit classification helpers for BAR.
-- Loaded via VFS.Include, initialized with init().
--
-- Provides:
--   - Lookup sets for Mex/Factory/Nano/T2-Factory/Combat (lazy-built)
--   - Anti-air detection (lazy-built, separate cache)
--   - Role classification (raider/assault/skirmisher/bomber/...)
--   - Trivial helpers: isAirUnit, isT2CombatUnit
--
-- Usage:
--   local UC = VFS.Include("LuaUI/Widgets/caster_modules/unit_classify.lua")
--                .init({ S = S, artyNames = artyNames })
--   UC.isMex(defID)  ->  true/false
------------------------------------------------------------------------

local M = {}

function M.init(deps)
    local S = deps.S
    local artyNames = deps.artyNames

    ----------------------------------------------------------------
    -- Lookup sets (lazy, built once on first is*() call)
    ----------------------------------------------------------------
    local function buildDefLookups()
        if S.defLookups then return end
        local NANO_NAMES = {
            cornanotc = true, armnanotc = true,
            legnanotc = true, legnanotcplat = true,
            legnanotct2 = true, legnanotct2plat = true, legnanotcbase = true,
        }
        local T2_FACTORY_NAMES = {
            coravp = true, coralab = true, coraap = true, corgant = true,
            armavp = true, armalab = true, armaap = true, armgant = true,
            legavp = true, legalab = true, legapt3 = true,
            leghavp = true, leghalab = true, leghap = true,
        }
        local mex, fac, nano, t2fac, combat = {}, {}, {}, {}, {}
        local mexCount, facCount, combatCount = 0, 0, 0
        for defID, ud in pairs(UnitDefs) do
            local name = ud.name or ""
            local isMexU = ud.extractsMetal and ud.extractsMetal > 0
            if isMexU then mex[defID] = true; mexCount = mexCount + 1 end
            if ud.isFactory then fac[defID] = true; facCount = facCount + 1 end
            if NANO_NAMES[name] then nano[defID] = true end
            if T2_FACTORY_NAMES[name] then t2fac[defID] = true end
            if not ud.isBuilder and not ud.isFactory and not isMexU
               and ud.weapons and #ud.weapons > 0 then
                combat[defID] = true
                combatCount = combatCount + 1
            end
        end
        S.defLookups = { mex = mex, fac = fac, nano = nano, t2fac = t2fac, combat = combat }
        Spring.Echo(string.format(
            "[Caster] Def-Lookups: %d Mex, %d Factories, %d Combat-Units",
            mexCount, facCount, combatCount))
    end

    local function isMex(defID)
        if not S.defLookups then buildDefLookups() end
        return S.defLookups.mex[defID] == true
    end
    local function isFactory(defID)
        if not S.defLookups then buildDefLookups() end
        return S.defLookups.fac[defID] == true
    end
    local function isNano(defID)
        if not S.defLookups then buildDefLookups() end
        return S.defLookups.nano[defID] == true
    end
    local function isT2Factory(defID)
        if not S.defLookups then buildDefLookups() end
        return S.defLookups.t2fac[defID] == true
    end
    local function isCombatUnit(defID)
        if not S.defLookups then buildDefLookups() end
        return S.defLookups.combat[defID] == true
    end

    ----------------------------------------------------------------
    -- Anti-air detection (separate cache, lazy)
    ----------------------------------------------------------------
    local aaLookup = {}
    local aaBuilt = false

    local function buildAALookup()
        if aaBuilt then return end
        aaBuilt = true
        local aaCount = 0
        for defID, ud in pairs(UnitDefs) do
            if ud.weapons then
                for wi = 1, #ud.weapons do
                    local w = ud.weapons[wi]
                    if w.onlyTargets and type(w.onlyTargets) == "table" and w.onlyTargets.vtol then
                        aaLookup[defID] = true
                        aaCount = aaCount + 1
                        break
                    end
                end
            end
        end
        Spring.Echo(string.format("[Caster] AA detection: %d anti-air units found", aaCount))
    end

    local function isAntiAir(defID)
        if not aaBuilt then buildAALookup() end
        return aaLookup[defID] or false
    end

    ----------------------------------------------------------------
    -- Role classification (raider/assault/skirmisher/...)
    ----------------------------------------------------------------
    local unitRoleCache = {}

    local function classifyUnit(defID)
        if unitRoleCache[defID] then return unitRoleCache[defID] end

        local ud = UnitDefs[defID]
        if not ud then
            unitRoleCache[defID] = "unknown"
            return "unknown"
        end

        local role = "unknown"
        local cost = ud.metalCost or 0
        local speed = ud.speed or 0
        local maxRange = 0

        if ud.weapons then
            for wi = 1, #ud.weapons do
                local w = ud.weapons[wi]
                if w.range and w.range > maxRange then
                    maxRange = w.range
                end
            end
        end

        -- Air
        if ud.canFly then
            if ud.isBomber then
                role = "bomber"
            elseif ud.isHoveringAirUnit or (ud.hoverAttack and ud.hoverAttack == true) then
                role = "gunship"
            elseif isAntiAir(defID) then
                role = "fighter"
            elseif maxRange > 500 then
                role = "bomber"
            else
                role = "fighter"
            end

        -- Naval
        elseif ud.floatOnWater or ud.canSubmerge or
               (ud.moveDef and ud.moveDef.name and string.find(ud.moveDef.name, "boat")) or
               (ud.name and (string.find(ud.name, "ship") or string.find(ud.name, "sub")
                or string.find(ud.name, "boat") or string.find(ud.name, "pt$"))) then
            role = "naval"

        -- Artillery
        elseif artyNames[ud.name] or maxRange > 1200 then
            role = "artillery"

        -- Anti-air (static or mobile)
        elseif isAntiAir(defID) then
            role = "aa"

        -- Ground combat
        elseif ud.canMove then
            if speed > 90 and cost < 200 then
                role = "raider"
            elseif speed > 70 and cost < 350 then
                role = "raider"
            elseif maxRange > 600 and cost > 200 then
                role = "skirmisher"
            elseif cost > 800 then
                role = "assault"
            elseif cost > 300 and speed < 60 then
                role = "assault"
            else
                role = "assault"
            end
        end

        unitRoleCache[defID] = role
        return role
    end

    ----------------------------------------------------------------
    -- Trivial helpers
    ----------------------------------------------------------------
    local function isAirUnit(defID)
        local ud = UnitDefs[defID]
        if not ud then return false end
        return ud.canFly or false
    end

    local function isT2CombatUnit(defID)
        local ud = UnitDefs[defID]
        if not ud then return false end
        if not isCombatUnit(defID) then return false end
        return (ud.metalCost or 0) > 400
    end

    return {
        buildDefLookups = buildDefLookups,
        buildAALookup   = buildAALookup,
        isMex           = isMex,
        isFactory       = isFactory,
        isNano          = isNano,
        isT2Factory     = isT2Factory,
        isCombatUnit    = isCombatUnit,
        isAntiAir       = isAntiAir,
        classifyUnit    = classifyUnit,
        isAirUnit       = isAirUnit,
        isT2CombatUnit  = isT2CombatUnit,
    }
end

return M
