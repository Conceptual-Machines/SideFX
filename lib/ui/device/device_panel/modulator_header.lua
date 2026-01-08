--[[
Modulator Header Module - Draws modulator column header with collapse button
]]

local M = {}

--- Draw modulator column header (collapse button + label)
function M.draw(ctx, state_guid)
    local r = reaper
    local state_module = require('lib.core.state')
    local state = state_module.state
    local interacted = false

    state.mod_sidebar_collapsed = state.mod_sidebar_collapsed or {}
    local is_mod_sidebar_collapsed = state.mod_sidebar_collapsed[state_guid] or false

    -- Collapse/expand button
    local mod_arrow_icon = is_mod_sidebar_collapsed and "▼" or "▶"

    ctx:push_style_color(r.ImGui_Col_Text(), 0xFFFFFFFF)  -- White arrow
    ctx:push_style_color(r.ImGui_Col_Button(), 0x00000000)
    ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x44444488)
    ctx:push_style_color(r.ImGui_Col_ButtonActive(), 0x55555588)
    if ctx:button(mod_arrow_icon .. "##collapse_mod_" .. state_guid, 20, 20) then
        state.mod_sidebar_collapsed[state_guid] = not is_mod_sidebar_collapsed
        interacted = true
    end
    ctx:pop_style_color(4)
    if r.ImGui_IsItemHovered(ctx.ctx) then
        ctx:set_tooltip(is_mod_sidebar_collapsed and "Expand Modulators" or "Collapse Modulators")
    end

    ctx:same_line()
    ctx:push_style_color(r.ImGui_Col_Text(), 0x888888FF)
    ctx:text("Modulators")
    ctx:pop_style_color()

    return interacted
end

return M
