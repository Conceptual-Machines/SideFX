--[[
Collapsed Device Header Module - Draws 2-row button layout for collapsed device
Row 1: ON | × | ▼
Row 2: UI | Mix | Delta
]]

local M = {}

--- Draw collapsed device header with 2-row button layout
function M.draw(ctx, fx, container, state_guid, enabled, device_collapsed, opts, colors)
    local r = reaper
    local drawing = require('lib.ui.common.drawing')
    local interacted = false

    -- Check for mix (container parameter)
    local has_mix = false
    local mix_val, mix_idx
    if container then
        local ok_mix
        ok_mix, mix_idx = pcall(function() return container:get_param_from_ident(":wet") end)
        if ok_mix and mix_idx and mix_idx >= 0 then
            local ok_mv
            ok_mv, mix_val = pcall(function() return container:get_param_normalized(mix_idx) end)
            has_mix = ok_mv and mix_val
        end
    end

    -- === ROW 1: ON | × | ▼ ===
    -- ON/OFF toggle
    if drawing.draw_on_off_circle(ctx, "##on_off_collapsed_" .. state_guid, enabled, 24, 20, colors.bypass_on, colors.bypass_off) then
        container:set_enabled(not enabled)
        interacted = true
    end
    if r.ImGui_IsItemHovered(ctx.ctx) then
        ctx:set_tooltip(enabled and "Bypass" or "Enable")
    end

    -- Delete button
    ctx:same_line()
    ctx:push_style_color(r.ImGui_Col_Button(), 0x663333FF)
    ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x884444FF)
    if ctx:button("×##delete_collapsed_" .. state_guid, 20, 20) then
        if opts.on_delete then
            opts.on_delete(fx)
        else
            fx:delete()
        end
        interacted = true
    end
    ctx:pop_style_color(2)
    if r.ImGui_IsItemHovered(ctx.ctx) then
        ctx:set_tooltip("Delete device")
    end

    -- Expand button
    ctx:same_line()
    ctx:push_style_color(r.ImGui_Col_Button(), 0x00000000)
    ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x44444488)
    ctx:push_style_color(r.ImGui_Col_ButtonActive(), 0x55555588)
    if ctx:button("◀##expand_collapsed_" .. state_guid, 20, 20) then  -- Left arrow for collapsed (click to expand)
        device_collapsed[state_guid] = false
        interacted = true
    end
    ctx:pop_style_color(3)
    if r.ImGui_IsItemHovered(ctx.ctx) then
        ctx:set_tooltip("Expand device controls")
    end

    -- === ROW 2: UI | Mix | Delta ===
    -- UI button (start new row)
    if drawing.draw_ui_icon(ctx, "##ui_collapsed_" .. state_guid, 24, 20, opts.icon_font) then
        pcall(function() fx:show(3) end)
        interacted = true
    end
    if r.ImGui_IsItemHovered(ctx.ctx) then
        ctx:set_tooltip("Open plugin UI")
    end

    -- Mix knob (if present)
    if has_mix then
        ctx:same_line()
        local knob_size = 24
        local mix_changed, new_mix = drawing.draw_knob(ctx, "##mix_knob_collapsed_" .. state_guid, mix_val, knob_size)
        if mix_changed then
            pcall(function() container:set_param_normalized(mix_idx, new_mix) end)
            interacted = true
        end
        if r.ImGui_IsItemHovered(ctx.ctx) then
            local mix_pct = math.floor(mix_val * 100)
            ctx:set_tooltip(string.format("Mix: %d%% (parallel blend)", mix_pct))
        end
    end

    -- Check for delta (container parameter)
    local has_delta = false
    local delta_val, delta_idx
    if container then
        local ok_delta
        ok_delta, delta_idx = pcall(function() return container:get_param_from_ident(":delta") end)
        if ok_delta and delta_idx and delta_idx >= 0 then
            local ok_dv
            ok_dv, delta_val = pcall(function() return container:get_param_normalized(delta_idx) end)
            has_delta = ok_dv and delta_val
        end
    end

    -- Delta button (if present)
    if has_delta then
        ctx:same_line()
        local delta_on = delta_val > 0.5
        if delta_on then
            ctx:push_style_color(r.ImGui_Col_Button(), 0x6666CCFF)
            ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x7777DDFF)
            ctx:push_style_color(r.ImGui_Col_ButtonActive(), 0x8888EEFF)
        else
            ctx:push_style_color(r.ImGui_Col_Button(), 0x444444FF)
            ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x555555FF)
            ctx:push_style_color(r.ImGui_Col_ButtonActive(), 0x666666FF)
        end
        if ctx:button((delta_on and "∆" or "—") .. "##delta_collapsed_" .. state_guid, 20, 20) then
            pcall(function() container:set_param_normalized(delta_idx, delta_on and 0 or 1) end)
            interacted = true
        end
        ctx:pop_style_color(3)
        if r.ImGui_IsItemHovered(ctx.ctx) then
            ctx:set_tooltip(delta_on and "Delta Solo: ON (wet - dry)\nClick to toggle" or "Delta Solo: OFF\nClick to toggle")
        end
    end

    return interacted
end

return M
