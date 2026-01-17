--[[
Modulator Header Module - Draws modulator column header with collapse button and mod matrix button
]]

local M = {}
local icons = require('lib.ui.common.icons')

--- Draw modulator column header (collapse button + label + mod matrix button)
-- @param ctx ImGui context wrapper
-- @param state_guid string State GUID for this device
-- @param opts table Options: on_mod_matrix callback
function M.draw(ctx, state_guid, opts)
    local r = reaper
    local state_module = require('lib.core.state')
    local state = state_module.state
    local interacted = false
    opts = opts or {}

    state.mod_sidebar_collapsed = state.mod_sidebar_collapsed or {}
    local is_mod_sidebar_collapsed = state.mod_sidebar_collapsed[state_guid] or false

    -- Use table for layout: collapse button | "Mod" label (stretch) | matrix button
    local table_flags = r.ImGui_TableFlags_SizingFixedFit() | r.ImGui_TableFlags_NoPadOuterX()
    r.ImGui_PushStyleVar(ctx.ctx, r.ImGui_StyleVar_CellPadding(), 0, 0)
    if r.ImGui_BeginTable(ctx.ctx, "mod_header_" .. state_guid, 3, table_flags) then
        r.ImGui_TableSetupColumn(ctx.ctx, "collapse", r.ImGui_TableColumnFlags_WidthFixed(), 22)
        r.ImGui_TableSetupColumn(ctx.ctx, "label", r.ImGui_TableColumnFlags_WidthStretch())
        r.ImGui_TableSetupColumn(ctx.ctx, "matrix", r.ImGui_TableColumnFlags_WidthFixed(), 22)

        r.ImGui_TableNextRow(ctx.ctx, 0, 20)  -- Fixed row height

        -- Column 1: Collapse button
        r.ImGui_TableSetColumnIndex(ctx.ctx, 0)
        local mod_arrow_icon = is_mod_sidebar_collapsed and "▶" or "▼"
        ctx:push_style_color(r.ImGui_Col_Text(), 0xFFFFFFFF)
        ctx:push_style_color(r.ImGui_Col_Button(), 0x00000000)
        ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x44444488)
        ctx:push_style_color(r.ImGui_Col_ButtonActive(), 0x55555588)
        if ctx:button(mod_arrow_icon .. "##collapse_mod_" .. state_guid, 20, 20) then
            state.mod_sidebar_collapsed[state_guid] = not is_mod_sidebar_collapsed
            state_module.save_mod_sidebar_collapsed()
            interacted = true
        end
        ctx:pop_style_color(4)
        if r.ImGui_IsItemHovered(ctx.ctx) then
            ctx:set_tooltip(is_mod_sidebar_collapsed and "Expand Modulators" or "Collapse Modulators")
        end

        -- Column 2: "Mod" label
        r.ImGui_TableSetColumnIndex(ctx.ctx, 1)
        ctx:push_style_color(r.ImGui_Col_Text(), 0x888888FF)
        ctx:text("Mod")
        ctx:pop_style_color()

        -- Column 3: Matrix button (aligned right)
        r.ImGui_TableSetColumnIndex(ctx.ctx, 2)
        if icons.button_bordered(ctx, "mod_matrix_header_" .. state_guid, icons.Names.matrix, 18) then
            if opts.on_mod_matrix then
                opts.on_mod_matrix()
            end
            interacted = true
        end
        if r.ImGui_IsItemHovered(ctx.ctx) then
            ctx:set_tooltip("Open Mod Matrix (all LFO links)")
        end

        r.ImGui_EndTable(ctx.ctx)
    end
    r.ImGui_PopStyleVar(ctx.ctx)

    return interacted
end

return M
