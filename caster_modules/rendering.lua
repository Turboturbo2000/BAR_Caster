------------------------------------------------------------------------
-- caster_modules/rendering.lua
-- Rendering helpers with FlowUI support (rounded corners, blur).
-- Falls back to plain gl.Rect if FlowUI is unavailable.
--
-- Usage:
--   local R = VFS.Include("LuaUI/Widgets/caster_modules/rendering.lua")
--   R.initFlowUI()          -- call in Initialize() and ViewResize()
--   R.setColor(C.title)
--   R.drawPanel(x1, y1, x2, y2, "caster")
------------------------------------------------------------------------

local M = {}

-- FlowUI references (nil = not available, use fallback)
local RectRound       = nil
local elementCorner   = nil
local elementPadding  = nil
local guishader       = nil

------------------------------------------------------------------------
-- FlowUI detection — call in Initialize() and ViewResize()
------------------------------------------------------------------------
function M.initFlowUI()
    if WG and WG.FlowUI then
        RectRound      = WG.FlowUI.Draw.RectRound
        elementCorner  = WG.FlowUI.elementCorner
        elementPadding = WG.FlowUI.elementPadding
    else
        RectRound      = nil
        elementCorner  = nil
        elementPadding = nil
    end
    if WG and WG['guishader'] then
        guishader = WG['guishader']
    else
        guishader = nil
    end
end

function M.hasFlowUI()
    return RectRound ~= nil
end

function M.getCorner()
    return elementCorner or 6
end

function M.getPadding()
    return elementPadding or 5
end

------------------------------------------------------------------------
-- Color helper
------------------------------------------------------------------------
function M.setColor(c)
    gl.Color(c[1], c[2], c[3], c[4])
end

------------------------------------------------------------------------
-- Rounded rectangle (falls back to gl.Rect)
-- corners: 1 = rounded, 0 = sharp (top-left, top-right, bottom-right, bottom-left)
------------------------------------------------------------------------
function M.roundedRect(x1, y1, x2, y2, radius, tl, tr, br, bl)
    if RectRound then
        RectRound(x1, y1, x2, y2, radius or elementCorner, tl or 1, tr or 1, br or 1, bl or 1)
    else
        gl.Rect(x1, y1, x2, y2)
    end
end

------------------------------------------------------------------------
-- Panel background with optional blur
------------------------------------------------------------------------
function M.drawPanel(x1, y1, x2, y2, shaderKey)
    local corner = elementCorner or 6
    gl.Color(0.02, 0.04, 0.08, 0.88)
    M.roundedRect(x1, y1, x2, y2, corner, 1, 1, 1, 1)
end

------------------------------------------------------------------------
-- Accent line at top of panel
------------------------------------------------------------------------
function M.drawAccentLine(x1, y, x2)
    local corner = elementCorner or 6
    gl.Color(0.4, 0.6, 1.0, 0.6)
    if RectRound then
        RectRound(x1, y, x2, y - 2, corner * 0.5, 1, 1, 0, 0)
    else
        gl.Rect(x1, y, x2, y - 2)
    end
end

------------------------------------------------------------------------
-- Divider line
------------------------------------------------------------------------
function M.drawDivider(lx1, ly, lx2, dividerColor)
    if dividerColor then M.setColor(dividerColor) end
    gl.Rect(lx1, ly, lx2, ly - 1)
end

------------------------------------------------------------------------
-- Section background (subtle highlight)
------------------------------------------------------------------------
function M.drawSectionBg(lx1, ly1, lx2, ly2, bgColor)
    if bgColor then M.setColor(bgColor) end
    local corner = (elementCorner or 6) * 0.5
    M.roundedRect(lx1, ly1, lx2, ly2, corner, 1, 1, 1, 1)
end

------------------------------------------------------------------------
-- Highlight bar (selected player in ranking)
------------------------------------------------------------------------
function M.drawHighlight(x1, y1, x2, y2, r, g, b, a)
    gl.Color(r or 0.15, g or 0.25, b or 0.40, a or 0.6)
    local corner = (elementCorner or 6) * 0.4
    M.roundedRect(x1, y1, x2, y2, corner, 1, 1, 1, 1)
end

------------------------------------------------------------------------
-- In-world marker background
------------------------------------------------------------------------
function M.drawMarkerBg(x1, y1, x2, y2, fade)
    gl.Color(0.0, 0.05, 0.1, 0.75 * (fade or 1))
    local corner = (elementCorner or 6) * 0.5
    M.roundedRect(x1, y1, x2, y2, corner, 1, 1, 1, 1)
end

------------------------------------------------------------------------
-- Balance bar with rounded ends
------------------------------------------------------------------------
function M.drawBalanceBar(barX1, barY1, barX2, barY2, balPct)
    local corner = (elementCorner or 6) * 0.5
    local barW = barX2 - barX1
    local splitX = barX1 + barW * balPct

    -- Background
    gl.Color(0.1, 0.1, 0.15, 0.8)
    M.roundedRect(barX1, barY1, barX2, barY2, corner, 1, 1, 1, 1)

    -- Team 1 (left, blue)
    gl.Color(0.3, 0.5, 1.0, 0.7)
    if RectRound then
        RectRound(barX1, barY1, splitX, barY2, corner, 1, 0, 0, 1)
    else
        gl.Rect(barX1, barY1, splitX, barY2)
    end

    -- Team 2 (right, red)
    gl.Color(1.0, 0.4, 0.3, 0.7)
    if RectRound then
        RectRound(splitX, barY1, barX2, barY2, corner, 0, 1, 1, 0)
    else
        gl.Rect(splitX, barY1, barX2, barY2)
    end

    -- Center marker
    gl.Color(1, 1, 1, 0.4)
    gl.Rect(barX1 + barW * 0.5 - 1, barY1, barX1 + barW * 0.5 + 1, barY2)
end

------------------------------------------------------------------------
-- Mini bar graph: single data series as vertical bars
------------------------------------------------------------------------
function M.drawMiniGraph(gx, gy, gw, gh, data, color, maxVal)
    local corner = (elementCorner or 6) * 0.4
    -- Background
    gl.Color(0.03, 0.05, 0.10, 0.7)
    M.roundedRect(gx, gy, gx + gw, gy - gh, corner, 1, 1, 1, 1)
    -- Find peak
    local peak = maxVal or 1
    if not maxVal then
        for gi = 1, #data do
            if data[gi] > peak then peak = data[gi] end
        end
    end
    -- Bars
    local barW = gw / #data
    for gi = 1, #data do
        local val = math.min(data[gi] / peak, 1.0)
        if val > 0 then
            local barH = val * (gh - 2)
            local bx = gx + (gi - 1) * barW
            gl.Color(color[1], color[2], color[3], 0.4 + val * 0.5)
            gl.Rect(bx, gy - gh + barH + 1, bx + barW - 1, gy - gh + 1)
        end
    end
    -- Border (top + bottom lines)
    gl.Color(color[1], color[2], color[3], 0.3)
    gl.Rect(gx, gy, gx + gw, gy - 1)
    gl.Rect(gx, gy - gh + 1, gx + gw, gy - gh)
end

------------------------------------------------------------------------
-- Multi-line graph: multiple data series as overlapping lines
-- series = { {data={...}, color={r,g,b}, label="Name"}, ... }
------------------------------------------------------------------------
function M.drawMultiLineGraph(gx, gy, gw, gh, series, maxVal)
    local corner = (elementCorner or 6) * 0.4
    -- Background
    gl.Color(0.03, 0.05, 0.10, 0.7)
    M.roundedRect(gx, gy, gx + gw, gy - gh, corner, 1, 1, 1, 1)

    if #series == 0 then return end

    -- Find peak across all series
    local peak = maxVal or 1
    if not maxVal then
        for _, s in ipairs(series) do
            for i = 1, #s.data do
                if s.data[i] > peak then peak = s.data[i] end
            end
        end
    end

    -- Draw lines
    gl.LineWidth(2)
    for _, s in ipairs(series) do
        local c = s.color or {1, 1, 1}
        gl.Color(c[1], c[2], c[3], 0.85)
        local numPts = #s.data
        if numPts >= 2 then
            gl.BeginEnd(GL.LINE_STRIP, function()
                for i = 1, numPts do
                    local px = gx + (i - 1) / (numPts - 1) * gw
                    local val = math.min(s.data[i] / peak, 1.0)
                    local py = (gy - gh) + val * (gh - 2) + 1
                    gl.Vertex(px, py)
                end
            end)
        end
    end
    gl.LineWidth(1)

    -- Border
    gl.Color(0.3, 0.3, 0.4, 0.3)
    gl.Rect(gx, gy, gx + gw, gy - 1)
    gl.Rect(gx, gy - gh + 1, gx + gw, gy - gh)
    gl.Rect(gx, gy, gx + 1, gy - gh)
    gl.Rect(gx + gw - 1, gy, gx + gw, gy - gh)
end

------------------------------------------------------------------------
-- Timeline background
------------------------------------------------------------------------
function M.drawTimelineBg(x1, y1, x2, y2)
    local corner = (elementCorner or 6) * 0.4
    gl.Color(0.08, 0.08, 0.12, 0.7)
    M.roundedRect(x1, y1, x2, y2, corner, 1, 1, 1, 1)
end

------------------------------------------------------------------------
-- Territory map background
------------------------------------------------------------------------
function M.drawMapBg(x1, y1, x2, y2)
    local corner = (elementCorner or 6) * 0.4
    gl.Color(0.05, 0.05, 0.08, 0.6)
    M.roundedRect(x1, y1, x2, y2, corner, 1, 1, 1, 1)
end

return M
