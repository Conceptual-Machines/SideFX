--- Device Chain UI Component
-- Draws the horizontal device chain with drag/drop support
-- @module ui.device_chain
-- @author Nomad Monad
-- @license MIT

local imgui = require('imgui')
local r = reaper

local M = {}

-- Lazy-loaded modules
local device_panel = nil
local rack_panel = nil

--------------------------------------------------------------------------------
-- Device Chain Drawing
--------------------------------------------------------------------------------

--- Draw the horizontal device chain
-- @param ctx ImGui context wrapper
-- @param fx_list table Array of FX objects
-- @param avail_width number Available width
-- @param avail_height number Available height
-- @param opts table Options:
--   - state: State table
--   - get_fx_display_name: function (fx) -> string
--   - refresh_fx_list: function () -> nil
--   - add_plugin_by_name: function (name, position) -> nil
--   - add_rack_to_track: function (position) -> nil
--   - get_device_main_fx: function (container) -> TrackFX|nil
--   - get_device_utility: function (container) -> TrackFX|nil
--   - is_device_container: function (fx) -> boolean
--   - is_rack_container: function (fx) -> boolean
--   - is_utility_fx: function (fx) -> boolean
--   - chain_item: chain_item module
--   - draw_selected_chain_column_if_expanded: function (ctx, rack_data, rack_guid) -> nil
--   - draw_rack_panel: function (ctx, rack, avail_height, is_nested) -> table
function M.draw(ctx, fx_list, avail_width, avail_height, opts)
    local state = opts.state
    local get_fx_display_name = opts.get_fx_display_name
    local refresh_fx_list = opts.refresh_fx_list
    local add_plugin_by_name = opts.add_plugin_by_name
    local add_rack_to_track = opts.add_rack_to_track
    local get_device_main_fx = opts.get_device_main_fx
    local get_device_utility = opts.get_device_utility
    local is_device_container = opts.is_device_container
    local is_rack_container = opts.is_rack_container
    local is_utility_fx = opts.is_utility_fx
    local chain_item = opts.chain_item
    local draw_selected_chain_column_if_expanded = opts.draw_selected_chain_column_if_expanded
    local draw_rack_panel = opts.draw_rack_panel

    -- Lazy load UI components
    if not device_panel then
        local ok, mod = pcall(require, 'lib.ui.device.device_panel')
        if ok then device_panel = mod end
    end
    if not rack_panel then
        local ok, mod = pcall(require, 'lib.ui.rack.rack_panel')
        if ok then rack_panel = mod end
    end

    -- Initialize chain_item with dependencies
    chain_item.init({
        get_fx_display_name = get_fx_display_name,
        device_panel = device_panel,
        state = state,
        icon_font = opts.icon_font,
        refresh_fx_list = refresh_fx_list,
        add_plugin_by_name = add_plugin_by_name,
        add_rack_to_track = add_rack_to_track,
        get_device_utility = get_device_utility,
        draw_selected_chain_column_if_expanded = draw_selected_chain_column_if_expanded,
        draw_rack_panel = draw_rack_panel,
    })

    -- Build display list - handles D-containers and legacy FX
    local display_fx = {}
    for i, fx in ipairs(fx_list) do
        if is_device_container(fx) then
            -- D-container: extract main FX and utility from inside
            local main_fx = get_device_main_fx(fx)
            local utility = get_device_utility(fx)
            if main_fx then
                table.insert(display_fx, {
                    fx = main_fx,
                    utility = utility,
                    container = fx,  -- Reference to the container
                    original_idx = fx.pointer,
                    is_device = true,
                })
            end
        elseif is_rack_container(fx) then
            -- R-container (rack) - handle differently
            table.insert(display_fx, {
                fx = fx,
                container = fx,
                original_idx = fx.pointer,
                is_rack = true,
            })
        elseif not is_utility_fx(fx) and not fx:is_container() then
            -- Legacy FX (not in container) - show with paired utility if exists
            local utility = nil
            if i < #fx_list and is_utility_fx(fx_list[i + 1]) then
                utility = fx_list[i + 1]
            end
            table.insert(display_fx, {
                fx = fx,
                utility = utility,
                original_idx = fx.pointer,
                is_legacy = true,
            })
        end
        -- Skip standalone utilities (they're shown in sidebar)
        -- Skip unknown containers
    end

    if #display_fx == 0 then
        -- Empty chain - full height drop zone (always visible)
        local has_plugin = ctx:get_drag_drop_payload("PLUGIN_ADD")
        local has_fx = ctx:get_drag_drop_payload("FX_GUID")
        local has_rack = ctx:get_drag_drop_payload("RACK_ADD")
        local is_dragging = has_plugin or has_fx or has_rack
        local drop_h = avail_height - 10

        if is_dragging then
            ctx:push_style_color(imgui.Col.Button(), 0x4488FF44)
            ctx:push_style_color(imgui.Col.ButtonHovered(), 0x66AAFF88)
            ctx:push_style_color(imgui.Col.ButtonActive(), 0x88CCFFAA)
        else
            ctx:push_style_color(imgui.Col.Button(), 0x3A4A5A44)
            ctx:push_style_color(imgui.Col.ButtonHovered(), 0x4A6A8A88)
            ctx:push_style_color(imgui.Col.ButtonActive(), 0x5A8ABAAA)
        end

        ctx:button("+ Drop plugin or rack##empty_drop", 200, drop_h)
        ctx:pop_style_color(3)

        if ctx:is_item_hovered() then
            ctx:set_tooltip("Drag plugin or rack here")
        end

        if ctx:begin_drag_drop_target() then
            -- Accept plugin drops
            local accepted, plugin_name = ctx:accept_drag_drop_payload("PLUGIN_ADD")
            if accepted and plugin_name then
                add_plugin_by_name(plugin_name, 0)
            end
            -- Accept rack drops
            local rack_accepted = ctx:accept_drag_drop_payload("RACK_ADD")
            if rack_accepted then
                add_rack_to_track(0)
            end
            ctx:end_drag_drop_target()
        end
        return
    end

    -- Note: No drop zone before first device - drop ON the first device to insert before it
    -- This prevents layout shifts that cause scroll jumping

    -- Draw each FX as a device panel, horizontally
    local display_idx = 0
    for _, item in ipairs(display_fx) do
        local fx = item.fx
        display_idx = display_idx + 1
        ctx:push_id("device_" .. display_idx)

        local is_container = fx:is_container()

        if display_idx > 1 then
            ctx:same_line()
        end

        if item.is_rack then
            -- Draw rack with chain column
            chain_item.draw_rack_item(ctx, fx, avail_height, {
                on_drop = function(dragged_guid, target_guid)
                    -- Handle FX/container reordering (works for both devices and racks)
                    local dragged = state.track:find_fx_by_guid(dragged_guid)
                    local target = state.track:find_fx_by_guid(target_guid)
                    if dragged and target then
                        r.TrackFX_CopyToTrack(
                            state.track.pointer, dragged.pointer,
                            state.track.pointer, target.pointer,
                            true  -- move
                        )
                        refresh_fx_list()
                    end
                end,
            })
        elseif is_container then
            -- Draw unknown container
            chain_item.draw_container_item(ctx, fx)
        else
            -- Draw device (full UI or fallback)
            chain_item.draw_device_item(ctx, fx, item, avail_height, {
                on_drop = function(dragged_guid, target_guid)
                    -- Handle FX/container reordering
                    local dragged = state.track:find_fx_by_guid(dragged_guid)
                    local target = state.track:find_fx_by_guid(target_guid)
                    if dragged and target then
                        r.TrackFX_CopyToTrack(
                            state.track.pointer, dragged.pointer,
                            state.track.pointer, target.pointer,
                            true  -- move
                        )
                        refresh_fx_list()
                    end
                end,
                on_plugin_drop = function(plugin_name, insert_pos)
                    add_plugin_by_name(plugin_name, insert_pos)
                end,
                on_rack_drop = function(insert_pos)
                    add_rack_to_track(insert_pos)
                end,
            })
        end

        ctx:pop_id()
    end

    -- Always show add button at end of chain (full height drop zone)
    ctx:same_line()

    local add_btn_h = avail_height - 10
    local has_plugin = ctx:get_drag_drop_payload("PLUGIN_ADD")
    local has_fx = ctx:get_drag_drop_payload("FX_GUID")
    local has_rack = ctx:get_drag_drop_payload("RACK_ADD")
    local is_dragging = has_plugin or has_fx or has_rack

    if is_dragging then
        ctx:push_style_color(imgui.Col.Button(), 0x4488FF44)
        ctx:push_style_color(imgui.Col.ButtonHovered(), 0x66AAFF88)
        ctx:push_style_color(imgui.Col.ButtonActive(), 0x88CCFFAA)
    else
        ctx:push_style_color(imgui.Col.Button(), 0x3A4A5A44)
        ctx:push_style_color(imgui.Col.ButtonHovered(), 0x4A6A8A88)
        ctx:push_style_color(imgui.Col.ButtonActive(), 0x5A8ABAAA)
    end

    ctx:button("+##add_end", 40, add_btn_h)
    ctx:pop_style_color(3)

    if ctx:is_item_hovered() then
        ctx:set_tooltip("Drag plugin or rack here")
    end

    -- Drop target for plugins and racks
    if ctx:begin_drag_drop_target() then
        local accepted, plugin_name = ctx:accept_drag_drop_payload("PLUGIN_ADD")
        if accepted and plugin_name then
            add_plugin_by_name(plugin_name, nil)  -- nil = add at end
        end
        -- Accept rack drops
        local rack_accepted = ctx:accept_drag_drop_payload("RACK_ADD")
        if rack_accepted then
            add_rack_to_track(nil)  -- nil = add at end
        end
        ctx:end_drag_drop_target()
    end

    -- Extra padding at end to ensure scrolling doesn't cut off the + button
    ctx:same_line()
    ctx:dummy(20, 1)
end

return M
