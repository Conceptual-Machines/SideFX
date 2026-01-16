--- Mod Matrix UI Component
-- Modal dialog showing all parameter links from all modulators
-- @module ui.modulator.mod_matrix
-- @author Nomad Monad
-- @license MIT

local r = reaper
local imgui = require('imgui')
local state_module = require('lib.core.state')
local config = require('lib.core.config')
local PARAM = require('lib.modulator.modulator_constants')
local drawing = require('lib.ui.common.drawing')
local modulator_bake = require('lib.modulator.modulator_bake')

local M = {}

-- Dialog state
local dialog_state = {
    open = false,
    popup_opened = false,
}

--------------------------------------------------------------------------------
-- Link Collection
--------------------------------------------------------------------------------

--- Get all modulators from a container (device)
-- @param container TrackFX container object
-- @return table Array of modulator FX objects
local function get_container_modulators(container)
    local modulators = {}
    if not container then return modulators end

    local ok, iter = pcall(function() return container:iter_container_children() end)
    if not ok or not iter then return modulators end

    for child in iter do
        local ok_name, name = pcall(function() return child:get_name() end)
        if ok_name and name and name:match("SideFX[_ ]Modulator") then
            table.insert(modulators, child)
        end
    end

    return modulators
end

--- Get the local index of a modulator within its container
-- @param container TrackFX container object
-- @param mod_guid string GUID of the modulator
-- @return number|nil Local index (0-based) or nil if not found
local function get_modulator_local_index(container, mod_guid)
    local ok_children, children = pcall(function() return container:get_container_children() end)
    if not ok_children or not children then return nil end

    for i, child in ipairs(children) do
        local ok_guid, child_guid = pcall(function() return child:get_guid() end)
        if ok_guid and child_guid == mod_guid then
            return i - 1  -- 0-based
        end
    end
    return nil
end

--- Get parameter links for a modulator targeting a specific FX
-- @param fx TrackFX target FX object
-- @param modulator TrackFX modulator object
-- @param modulator_idx number Local index of modulator in container
-- @return table Array of link info {param_idx, param_name, scale, offset}
local function get_modulator_links(fx, modulator, modulator_idx)
    local links = {}

    local ok_params, param_count = pcall(function() return fx:get_num_params() end)
    if not ok_params or not param_count then return links end

    for param_idx = 0, param_count - 1 do
        local link_info = fx:get_param_link_info(param_idx)
        if link_info and link_info.effect == modulator_idx and link_info.param == PARAM.PARAM_OUTPUT then
            local ok_pname, param_name = pcall(function() return fx:get_param_name(param_idx) end)
            if ok_pname and param_name then
                table.insert(links, {
                    param_idx = param_idx,
                    param_name = param_name,
                    scale = link_info.scale or 1.0,
                    offset = link_info.offset or 0,
                })
            end
        end
    end

    return links
end

--- Collect all parameter links from all modulators across all devices
-- @param state table State object
-- @param track TrackFX track object
-- @return table Array of link records {lfo_num, device_name, fx, param_name, param_idx, modulator, scale, offset, device_guid, mod_guid}
local function collect_all_links(state, track)
    local all_links = {}
    if not track then return all_links end

    -- Iterate through top-level FX to find devices
    for _, fx in ipairs(state.top_level_fx) do
        local ok_is_container, is_container = pcall(function() return fx:is_container() end)
        if not ok_is_container or not is_container then goto continue end

        local ok_name, name = pcall(function() return fx:get_name() end)
        if not ok_name or not name then goto continue end

        -- Check if this is a device container (D{n}: ...)
        local device_num, device_name = name:match("^D(%d+): (.+)$")
        if not device_num then goto continue end

        local ok_guid, device_guid = pcall(function() return fx:get_guid() end)
        if not ok_guid or not device_guid then goto continue end

        -- Get modulators in this device
        local modulators = get_container_modulators(fx)

        -- Get the main FX in this device (first non-modulator, non-utility child)
        local main_fx = nil
        local ok_children, children = pcall(function() return fx:get_container_children() end)
        if ok_children and children then
            for _, child in ipairs(children) do
                local ok_child_name, child_name = pcall(function() return child:get_name() end)
                if ok_child_name and child_name then
                    -- Skip modulators and utilities
                    if not child_name:match("SideFX[_ ]Modulator") and
                       not child_name:match("SideFX[_ ]Utility") and
                       not child_name:match("_Util$") then
                        main_fx = child
                        break
                    end
                end
            end
        end

        if not main_fx then goto continue end

        -- For each modulator, get its links to the main FX
        for mod_idx, modulator in ipairs(modulators) do
            local ok_mod_guid, mod_guid = pcall(function() return modulator:get_guid() end)
            if not ok_mod_guid or not mod_guid then goto continue_mod end

            local mod_local_idx = get_modulator_local_index(fx, mod_guid)
            if mod_local_idx == nil then goto continue_mod end

            local links = get_modulator_links(main_fx, modulator, mod_local_idx)

            for _, link in ipairs(links) do
                table.insert(all_links, {
                    lfo_num = mod_idx,
                    device_name = device_name,
                    device_num = tonumber(device_num),
                    fx = main_fx,
                    param_name = link.param_name,
                    param_idx = link.param_idx,
                    modulator = modulator,
                    scale = link.scale,
                    offset = link.offset,
                    device_guid = device_guid,
                    mod_guid = mod_guid,
                })
            end

            ::continue_mod::
        end

        ::continue::
    end

    -- Sort by device number, then LFO number
    table.sort(all_links, function(a, b)
        if a.device_num ~= b.device_num then
            return a.device_num < b.device_num
        end
        return a.lfo_num < b.lfo_num
    end)

    return all_links
end

--------------------------------------------------------------------------------
-- Matrix Table Drawing
--------------------------------------------------------------------------------

--- Draw the mod matrix table
-- @param ctx ImGui context wrapper
-- @param state table State object
-- @param links table Array of link records
-- @return boolean True if any interaction occurred
local function draw_matrix_table(ctx, state, links)
    local interacted = false

    if #links == 0 then
        ctx:text_disabled("No parameter links found.")
        ctx:spacing()
        ctx:text_disabled("To create links:")
        ctx:text_disabled("1. Add a modulator to a device")
        ctx:text_disabled("2. Right-click a parameter slider")
        ctx:text_disabled("3. Select 'Link to LFO'")
        return false
    end

    -- Initialize state tables
    state.link_bipolar = state.link_bipolar or {}
    state.link_disabled = state.link_disabled or {}
    state.link_saved_scale = state.link_saved_scale or {}

    local table_flags = r.ImGui_TableFlags_SizingFixedFit() |
                        r.ImGui_TableFlags_RowBg() |
                        r.ImGui_TableFlags_BordersInnerV()

    -- Columns: LFO | Device | Param | Mode | Depth | Dis | Bake | Del
    if ctx:begin_table("mod_matrix_table", 8, table_flags) then
        r.ImGui_TableSetupColumn(ctx.ctx, "LFO", r.ImGui_TableColumnFlags_WidthFixed(), 35)
        r.ImGui_TableSetupColumn(ctx.ctx, "Device", r.ImGui_TableColumnFlags_WidthFixed(), 80)
        r.ImGui_TableSetupColumn(ctx.ctx, "Param", r.ImGui_TableColumnFlags_WidthFixed(), 80)
        r.ImGui_TableSetupColumn(ctx.ctx, "Mode", r.ImGui_TableColumnFlags_WidthFixed(), 44)
        r.ImGui_TableSetupColumn(ctx.ctx, "Depth", r.ImGui_TableColumnFlags_WidthStretch(), 1)
        r.ImGui_TableSetupColumn(ctx.ctx, "Dis", r.ImGui_TableColumnFlags_WidthFixed(), 22)
        r.ImGui_TableSetupColumn(ctx.ctx, "Bake", r.ImGui_TableColumnFlags_WidthFixed(), 22)
        r.ImGui_TableSetupColumn(ctx.ctx, "Del", r.ImGui_TableColumnFlags_WidthFixed(), 22)

        -- Header row
        r.ImGui_TableHeadersRow(ctx.ctx)

        for i, link in ipairs(links) do
            local link_key = link.device_guid .. "_" .. link.param_idx
            local plink_prefix = string.format("param.%d.plink.", link.param_idx)
            local actual_depth = link.scale

            -- Check if link is disabled
            local is_disabled = math.abs(actual_depth) < 0.001
            if is_disabled then
                state.link_disabled[link_key] = true
            elseif state.link_disabled[link_key] then
                state.link_disabled[link_key] = false
            end

            local is_bipolar = state.link_bipolar[link_key] or false

            ctx:table_next_row()

            -- Grey out disabled links
            if is_disabled then
                ctx:push_style_color(imgui.Col.Text(), 0x666666FF)
            end

            -- Column 1: LFO number
            ctx:table_set_column_index(0)
            ctx:text(tostring(link.lfo_num))

            -- Column 2: Device name
            ctx:table_set_column_index(1)
            local short_device = link.device_name:sub(1, 10)
            if #link.device_name > 10 then short_device = short_device .. ".." end
            if not is_disabled then
                ctx:push_style_color(imgui.Col.Text(), 0x88CCFFFF)
            end
            ctx:text(short_device)
            if not is_disabled then
                ctx:pop_style_color()
            end
            if ctx:is_item_hovered() and #link.device_name > 10 then
                ctx:set_tooltip(link.device_name)
            end

            -- Column 3: Parameter name
            ctx:table_set_column_index(2)
            local short_param = link.param_name:sub(1, 10)
            if #link.param_name > 10 then short_param = short_param .. ".." end
            ctx:text(short_param)
            if ctx:is_item_hovered() and #link.param_name > 10 then
                ctx:set_tooltip(link.param_name)
            end

            -- Column 4: Mode (U/B buttons)
            ctx:table_set_column_index(3)
            if is_disabled then
                r.ImGui_BeginDisabled(ctx.ctx)
            end

            if not is_bipolar and not is_disabled then
                ctx:push_style_color(imgui.Col.Button(), 0x5588AAFF)
            end
            if ctx:button("U##mm_bi_" .. i, 20, 0) then
                if is_bipolar and not is_disabled then
                    state.link_bipolar[link_key] = false
                    link.fx:set_named_config_param(plink_prefix .. "offset", "0")
                    interacted = true
                end
            end
            if not is_bipolar and not is_disabled then
                ctx:pop_style_color()
            end
            if ctx:is_item_hovered() then ctx:set_tooltip("Unipolar") end

            ctx:same_line(0, 0)

            if is_bipolar and not is_disabled then
                ctx:push_style_color(imgui.Col.Button(), 0x5588AAFF)
            end
            if ctx:button("B##mm_bi_" .. i, 20, 0) then
                if not is_bipolar and not is_disabled then
                    state.link_bipolar[link_key] = true
                    link.fx:set_named_config_param(plink_prefix .. "offset", "-0.5")
                    interacted = true
                end
            end
            if is_bipolar and not is_disabled then
                ctx:pop_style_color()
            end
            if ctx:is_item_hovered() then ctx:set_tooltip("Bipolar") end

            if is_disabled then
                r.ImGui_EndDisabled(ctx.ctx)
            end

            -- Column 5: Depth slider
            ctx:table_set_column_index(4)
            local depth_slider_x, depth_slider_y = r.ImGui_GetCursorScreenPos(ctx.ctx)
            local depth_avail_w = r.ImGui_GetContentRegionAvail(ctx.ctx)
            ctx:set_next_item_width(-1)

            local depth_value = is_disabled and (state.link_saved_scale[link_key] or 0.5) or actual_depth

            if is_disabled then
                r.ImGui_BeginDisabled(ctx.ctx)
            end

            -- Use -1 to 1 range directly for the slider so text input works correctly
            -- default_value 0.0 = center (no modulation bias)
            local changed, new_display_depth, in_text_mode = drawing.slider_double_fine(
                ctx, "##mm_depth_" .. i, depth_value, -1.0, 1.0, " ", nil, 1, 0.0
            )

            -- Overlay depth value (centered on slider) - only when NOT in text input mode
            if not in_text_mode then
                local depth_text = string.format("%+.2f", depth_value)
                local depth_text_w = r.ImGui_CalcTextSize(ctx.ctx, depth_text)
                local depth_slider_h = r.ImGui_GetFrameHeight(ctx.ctx)
                local depth_text_x = depth_slider_x + (depth_avail_w - depth_text_w) / 2
                local depth_text_y = depth_slider_y + (depth_slider_h - r.ImGui_GetTextLineHeight(ctx.ctx)) / 2
                local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)
                local depth_text_color = is_disabled and 0x666666FF or 0xFFFFFFFF
                r.ImGui_DrawList_AddText(draw_list, depth_text_x, depth_text_y, depth_text_color, depth_text)
            end

            if changed and not is_disabled then
                -- new_display_depth is already in -1..1 range
                if is_bipolar then
                    link.fx:set_named_config_param(plink_prefix .. "offset", "-0.5")
                end
                link.fx:set_named_config_param(plink_prefix .. "scale", tostring(new_display_depth))
                interacted = true
            end

            if is_disabled then
                r.ImGui_EndDisabled(ctx.ctx)
            end
            if ctx:is_item_hovered() then ctx:set_tooltip("Modulation depth") end

            -- Column 6: Disable/Enable button
            ctx:table_set_column_index(5)
            local disable_icon = is_disabled and ">" or "||"
            if is_disabled then
                ctx:push_style_color(imgui.Col.Button(), 0x444444FF)
            end
            if ctx:button(disable_icon .. "##mm_dis_" .. i, 20, 0) then
                if is_disabled then
                    local saved = state.link_saved_scale[link_key] or 0.5
                    link.fx:set_named_config_param(plink_prefix .. "scale", tostring(saved))
                    state.link_disabled[link_key] = false
                else
                    state.link_saved_scale[link_key] = actual_depth
                    link.fx:set_named_config_param(plink_prefix .. "scale", "0")
                    state.link_disabled[link_key] = true
                end
                state_module.save_link_scales()
                interacted = true
            end
            if is_disabled then
                ctx:pop_style_color()
            end
            if ctx:is_item_hovered() then
                ctx:set_tooltip(is_disabled and "Enable link" or "Disable link")
            end

            -- Column 7: Bake button
            ctx:table_set_column_index(6)
            if ctx:button("B##mm_bake_" .. i, 20, 0) then
                local bake_options = {
                    range_mode = config.get('bake_default_range_mode'),
                    disable_link = config.get('bake_disable_link_after'),
                }
                local current_scale = link.scale
                local ok, result, msg = pcall(function()
                    return modulator_bake.bake_to_automation(
                        state.track, link.modulator, link.fx, link.param_idx, bake_options
                    )
                end)
                if ok and result then
                    r.ShowConsoleMsg("SideFX: " .. (msg or "Baked") .. "\n")
                    if bake_options.disable_link then
                        state.link_saved_scale[link_key] = current_scale
                        state.link_disabled[link_key] = true
                        state_module.save_link_scales()
                    end
                elseif not ok then
                    r.ShowConsoleMsg("SideFX Bake Error: " .. tostring(result) .. "\n")
                else
                    r.ShowConsoleMsg("SideFX: " .. tostring(msg or "No automation created") .. "\n")
                end
                interacted = true
            end
            if ctx:is_item_hovered() then ctx:set_tooltip("Bake to automation") end

            -- Column 8: Remove button
            ctx:table_set_column_index(7)
            if ctx:button("X##mm_rm_" .. i, 20, 0) then
                local restore_value = (state.link_baselines and state.link_baselines[link_key]) or 0
                if link.fx:remove_param_link(link.param_idx) then
                    link.fx:set_param_normalized(link.param_idx, restore_value)
                    if state.link_baselines then state.link_baselines[link_key] = nil end
                    if state.link_bipolar then state.link_bipolar[link_key] = nil end
                    if state.link_disabled then state.link_disabled[link_key] = nil end
                    if state.link_saved_scale then state.link_saved_scale[link_key] = nil end
                    interacted = true
                end
            end
            if ctx:is_item_hovered() then ctx:set_tooltip("Remove link") end

            if is_disabled then
                ctx:pop_style_color()
            end
        end

        ctx:end_table()
    end

    return interacted
end

--------------------------------------------------------------------------------
-- Dialog Rendering
--------------------------------------------------------------------------------

--- Draw the mod matrix dialog
-- @param ctx ImGui context wrapper
-- @param state table State object
function M.draw(ctx, state)
    if not dialog_state.open then
        return
    end

    -- Open the popup on first frame
    if not dialog_state.popup_opened then
        r.ImGui_OpenPopup(ctx.ctx, "Mod Matrix##sidefx_mod_matrix")
        dialog_state.popup_opened = true
    end

    -- Set minimum window size
    r.ImGui_SetNextWindowSize(ctx.ctx, 550, 300, imgui.Cond.FirstUseEver())

    local flags = r.ImGui_WindowFlags_NoCollapse()
    local visible, p_open = r.ImGui_BeginPopupModal(ctx.ctx, "Mod Matrix##sidefx_mod_matrix", true, flags)

    if not visible then
        if not p_open then
            dialog_state.open = false
            dialog_state.popup_opened = false
        end
        return
    end

    -- Collect all links
    local all_links = collect_all_links(state, state.track)

    -- Info text
    ctx:text_disabled("All parameter links from all modulators")
    ctx:separator()
    ctx:spacing()

    -- Scrollable table area
    local avail_h = r.ImGui_GetContentRegionAvail(ctx.ctx) - 40  -- Leave room for close button
    if ctx:begin_child("mod_matrix_scroll", 0, avail_h, 0) then
        draw_matrix_table(ctx, state, all_links)
        ctx:end_child()
    end

    ctx:spacing()
    ctx:separator()
    ctx:spacing()

    -- Close button (centered)
    local avail_w = ctx:get_content_region_avail_width()
    local btn_w = 100
    local btn_x = (avail_w - btn_w) / 2
    if btn_x > 0 then
        ctx:dummy(btn_x, 0)
        ctx:same_line()
    end

    if ctx:button("Close", btn_w, 0) then
        dialog_state.open = false
        dialog_state.popup_opened = false
        r.ImGui_CloseCurrentPopup(ctx.ctx)
    end

    if not p_open then
        dialog_state.open = false
        dialog_state.popup_opened = false
    end

    r.ImGui_EndPopup(ctx.ctx)
end

--------------------------------------------------------------------------------
-- Dialog Control
--------------------------------------------------------------------------------

--- Open the mod matrix dialog
function M.open()
    dialog_state.open = true
    dialog_state.popup_opened = false
end

--- Check if dialog is open
-- @return boolean
function M.is_open()
    return dialog_state.open
end

return M
