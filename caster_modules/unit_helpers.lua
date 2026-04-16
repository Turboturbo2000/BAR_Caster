------------------------------------------------------------------------
-- caster_modules/unit_helpers.lua
-- Helper functions for unit identification and naming.
--
-- Usage:
--   local UH = VFS.Include("LuaUI/Widgets/caster_modules/unit_helpers.lua")
--              .init({ isT2Factory = isT2Factory })
------------------------------------------------------------------------

local UH = {}

-- Spring API locals (performance)
local spGetUnitCommands    = Spring.GetUnitCommands
local spGetUnitHealth      = Spring.GetUnitHealth

------------------------------------------------------------------------
-- Lookup tables
------------------------------------------------------------------------
local commNames = {
    corcom = true, armcom = true,
    corcommander = true, armcommander = true,
    legcom = true, legcomdef = true, legcomecon = true,
    legcomlvl2 = true, legcomlvl3 = true, legcomlvl4 = true,
    legcomlvl5 = true, legcomlvl6 = true, legcomlvl7 = true,
    legcomlvl8 = true, legcomlvl9 = true, legcomlvl10 = true,
    legcomt2com = true, legcomt2def = true, legcomt2off = true,
    legdecom = true,
}

------------------------------------------------------------------------
-- Functions
------------------------------------------------------------------------

local function isCommander(unitDefID)
    local ud = UnitDefs[unitDefID]
    if not ud then return false end
    local name = ud.name or ""
    if commNames[name] then return true end
    if ud.customParams and ud.customParams.iscommander then return true end
    return false
end

local function isBuilder(unitDefID)
    local ud = UnitDefs[unitDefID]
    if not ud then return false end
    if ud.isFactory then return false end
    return ud.isBuilder or false
end

local function isUnitIdle(unitID)
    local cmds = spGetUnitCommands(unitID, 1)
    if not cmds or #cmds == 0 then return true end
    return false
end

local function isUnitFinished(unitID)
    local _, _, _, _, buildProgress = spGetUnitHealth(unitID)
    if buildProgress and buildProgress >= 1.0 then return true end
    return false
end

------------------------------------------------------------------------
-- Dependency: isT2Factory comes from unit_classify.lua
------------------------------------------------------------------------
local isT2Factory

------------------------------------------------------------------------
-- Init: Dependency Injection
------------------------------------------------------------------------
function UH.init(deps)
    isT2Factory = deps.isT2Factory

    return {
        isCommander    = isCommander,
        isBuilder      = isBuilder,
        isUnitIdle     = isUnitIdle,
        isUnitFinished = isUnitFinished,
        commNames      = commNames,
    }
end

return UH
