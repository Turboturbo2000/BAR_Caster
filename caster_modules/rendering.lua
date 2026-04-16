------------------------------------------------------------------------
-- caster_modules/rendering.lua
-- Pure rendering helpers (gl.Rect/gl.Color wrappers).
-- No dependencies on game state — only GL + color + geometry.
--
-- Usage:
--   local R = VFS.Include("LuaUI/Widgets/caster_modules/rendering.lua")
--   R.setColor(C.title)
--   R.drawDivider(x1, y, x2, C.divider)
------------------------------------------------------------------------

local M = {}

function M.setColor(c)
    gl.Color(c[1], c[2], c[3], c[4])
end

function M.drawDivider(lx1, ly, lx2, dividerColor)
    if dividerColor then M.setColor(dividerColor) end
    gl.Rect(lx1, ly, lx2, ly - 1)
end

function M.drawSectionBg(lx1, ly1, lx2, ly2, bgColor)
    if bgColor then M.setColor(bgColor) end
    gl.Rect(lx1, ly1, lx2, ly2)
end

------------------------------------------------------------------------
-- Mini bar graph: single data series as vertical bars
------------------------------------------------------------------------
function M.drawMiniGraph(gx, gy, gw, gh, data, color, maxVal)
    -- Background
    gl.Color(0.03, 0.05, 0.10, 0.7)
    gl.Rect(gx, gy, gx + gw, gy - gh)
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
    -- Border
    gl.Color(color[1], color[2], color[3], 0.3)
    gl.Rect(gx, gy, gx + gw, gy - 1)
    gl.Rect(gx, gy - gh + 1, gx + gw, gy - gh)
end

------------------------------------------------------------------------
-- Multi-line graph: multiple data series as overlapping lines
-- series = { {data={...}, color={r,g,b}, label="Name"}, ... }
------------------------------------------------------------------------
function M.drawMultiLineGraph(gx, gy, gw, gh, series, maxVal)
    -- Background
    gl.Color(0.03, 0.05, 0.10, 0.7)
    gl.Rect(gx, gy, gx + gw, gy - gh)

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

return M
