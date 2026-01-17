--- Device Chain UI Component
-- Draws the horizontal device chain with drag/drop support
-- @module ui.device_chain
-- @author Nomad Monad
-- @license MIT

local imgui = require('imgui')
local r = reaper
local helpers = require('helpers')

local M = {}

-- Lazy-loaded modules
local device_panel = nil
local rack_panel = nil

-- Logger that only logs each message once (prevents spam)
local log_once = helpers.log_once_func("DeviceChain")

-- Track which drop zone is being hovered (for visual feedback)
local hovered_drop_zone = nil

--------------------------------------------------------------------------------
-- Drop Zone Indicator
--------------------------------------------------------------------------------

--- Draw a drop zone indicator between devices
-- @param ctx ImGui context wrapper
-- @param zone_id string Unique ID for this zone
-- @param insert_pos number FX index to insert before
-- @param avail_height number Height of the drop zone
-- @param add_plugin_by_name function Callback to add plugin
-- @param add_rack_to_track function Callback to add rack
-- @param refresh_fx_list function Callback to refresh FX list
-- @param state table State object
-- @return boolean True if something was dropped
local function draw_drop_zone_indicator(ctx, zone_id, insert_pos, avail_height, add_plugin_by_name, add_rack_to_track, refresh_fx_list, state, no_same_line)
    local has_plugin = ctx:get_drag_drop_payload("PLUGIN_ADD")
    local has_fx = ctx:get_drag_drop_payload("FX_GUID")
    local has_rack = ctx:get_drag_drop_payload("RACK_ADD")
    local is_dragging = has_plugin or has_fx or has_rack

    -- Only show drop zones when actively dragging
    if not is_dragging then
        return false
    end

    if not no_same_line then
        ctx:same_line()
    end

    -- Determine zone width based on hover state
    local is_hovered = (hovered_drop_zone == zone_id)
    local zone_width = is_hovered and 24 or 8
    local zone_height = avail_height - 10

    -- Style the drop zone
    if is_hovered then
        ctx:push_style_color(imgui.Col.Button(), 0x66AAFF88)
        ctx:push_style_color(imgui.Col.ButtonHovered(), 0x88CCFFAA)
        ctx:push_style_color(imgui.Col.ButtonActive(), 0xAADDFFCC)
    else
        ctx:push_style_color(imgui.Col.Button(), 0x4488FF44)
        ctx:push_style_color(imgui.Col.ButtonHovered(), 0x66AAFF66)
        ctx:push_style_color(imgui.Col.ButtonActive(), 0x88CCFF88)
    end

    ctx:button("##drop_" .. zone_id, zone_width, zone_height)
    ctx:pop_style_color(3)

    -- Track hover state for next frame
    if ctx:is_item_hovered() then
        hovered_drop_zone = zone_id
    elseif hovered_drop_zone == zone_id then
        hovered_drop_zone = nil
    end

    -- Handle drops
    if ctx:begin_drag_drop_target() then
        -- Accept plugin drops
        local accepted, plugin_name = ctx:accept_drag_drop_payload("PLUGIN_ADD")
        if accepted and plugin_name then
            -- Check for Shift key = add as bare device (no utility)
            local shift_held = r.ImGui_IsKeyDown(ctx.ctx, r.ImGui_Mod_Shift())
            local opts = shift_held and { bare = true } or nil
            add_plugin_by_name(plugin_name, insert_pos, opts)
        end

        -- Accept FX reorder drops
        local fx_accepted, fx_guid = ctx:accept_drag_drop_payload("FX_GUID")
        if fx_accepted and fx_guid then
            local dragged = state.track:find_fx_by_guid(fx_guid)
            if dragged then
                r.TrackFX_CopyToTrack(
                    state.track.pointer, dragged.pointer,
                    state.track.pointer, insert_pos,
                    true  -- move
                )
                refresh_fx_list()
            end
        end

        -- Accept rack drops
        local rack_accepted = ctx:accept_drag_drop_payload("RACK_ADD")
        if rack_accepted then
            add_rack_to_track(insert_pos)
        end

        ctx:end_drag_drop_target()
    end

    return true  -- Zone was drawn
end

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

    -- If a deletion just occurred, skip rendering this frame
    -- The next frame will have fresh FX data
    if state.deletion_pending then
        return
    end

    -- If FX list was invalidated (e.g., modulator added), skip rendering this frame
    -- The next frame will refresh the FX list first
    if state.fx_list_invalid then
        return
    end

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
        header_font = opts.header_font,
        refresh_fx_list = refresh_fx_list,
        add_plugin_by_name = add_plugin_by_name,
        add_rack_to_track = add_rack_to_track,
        get_device_utility = get_device_utility,
        draw_selected_chain_column_if_expanded = draw_selected_chain_column_if_expanded,
        draw_rack_panel = draw_rack_panel,
        on_mod_matrix = opts.on_mod_matrix,
    })

    -- Build display list - handles D-containers and legacy FX
    local display_fx = {}

    for i, fx in ipairs(fx_list) do
        if is_device_container(fx) then
            -- D-container: extract main FX and utility from inside
            local main_fx = get_device_main_fx(fx)
            local utility = get_device_utility(fx)
            local missing = (utility == nil)

            -- Log when utility is missing (safely get name)
            if missing then
                local ok_name, fx_name = pcall(function() return fx:get_name() end)
                if ok_name and fx_name then
                    log_once("Missing utility in:", fx_name)
                end
            end

            if main_fx then
                -- Update state with missing utility info (safely get GUID)
                local ok_guid, container_guid = pcall(function() return fx:get_guid() end)
                if not ok_guid or not container_guid then
                    -- Skip this item if we can't get its GUID
                    goto continue_fx_loop
                end
                if missing then
                    state.missing_utilities[container_guid] = true
                else
                    state.missing_utilities[container_guid] = nil
                end

                table.insert(display_fx, {
                    fx = main_fx,
                    utility = utility,
                    container = fx,  -- Reference to the container
                    original_idx = fx.pointer,
                    is_device = true,
                    missing_utility = missing,  -- Flag if utility is missing
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
            -- Check if this is a bare or post device
            local ok_name, fx_name = pcall(function() return fx:get_name() end)
            local naming_module = require('lib.utils.naming')
            local is_bare = ok_name and fx_name and naming_module.is_bare_device_name(fx_name)
            local is_post = ok_name and fx_name and naming_module.is_post_device_name(fx_name)
            table.insert(display_fx, {
                fx = fx,
                utility = utility,
                original_idx = fx.pointer,
                is_legacy = true,
                is_bare = is_bare or is_post,  -- Both bare and post use simplified panel
                is_post = is_post,  -- Flag for post FX (rendered in column 2)
            })
        end
        -- Skip standalone utilities (they're shown in sidebar)
        -- Skip unknown containers
        ::continue_fx_loop::
    end

    -- Separate main chain and post FX
    local main_chain = {}
    local post_chain = {}
    for _, item in ipairs(display_fx) do
        if item.is_post then
            table.insert(post_chain, item)
        else
            table.insert(main_chain, item)
        end
    end

    -- Detect drag state for styling
    local has_plugin = ctx:get_drag_drop_payload("PLUGIN_ADD")
    local has_fx = ctx:get_drag_drop_payload("FX_GUID")
    local has_rack = ctx:get_drag_drop_payload("RACK_ADD")
    local is_dragging = has_plugin or has_fx or has_rack
    local drop_h = avail_height - 10

    if #main_chain == 0 then
        -- Empty chain - full height drop zone (always visible)
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
                -- Check for Shift key = add as bare device (no utility)
                local shift_held = r.ImGui_IsKeyDown(ctx.ctx, r.ImGui_Mod_Shift())
                local drop_opts = shift_held and { bare = true } or nil
                add_plugin_by_name(plugin_name, 0, drop_opts)
            end
            -- Accept rack drops
            local rack_accepted = ctx:accept_drag_drop_payload("RACK_ADD")
            if rack_accepted then
                add_rack_to_track(0)
            end
            ctx:end_drag_drop_target()
        end
    else
        -- Drop zone before first device (only visible when dragging, so no layout shift)
        local first_item = main_chain[1]
        local drew_first_zone = false
        if first_item then
            drew_first_zone = draw_drop_zone_indicator(
                ctx,
                "zone_first",
                0,  -- Insert at position 0 (before first device)
                avail_height,
                add_plugin_by_name,
                add_rack_to_track,
                refresh_fx_list,
                state,
                true  -- no_same_line = true (first item, nothing before it)
            )
        end

        -- Draw each FX as a device panel, horizontally
        local display_idx = 0
        for _, item in ipairs(main_chain) do
            -- Check before processing each item - previous iteration may have invalidated
            if state.deletion_pending or state.fx_list_invalid then
                break
            end

            local fx = item.fx
            display_idx = display_idx + 1
            ctx:push_id("device_" .. display_idx)

            local is_container_fx = fx:is_container()

            if display_idx == 1 then
                -- First device: add same_line if we drew the first drop zone
                if drew_first_zone then
                    ctx:same_line()
                end
            else
                -- Subsequent devices: draw drop zone indicator between devices
                draw_drop_zone_indicator(
                    ctx,
                    "zone_" .. display_idx,
                    item.original_idx,  -- Insert position (before this device)
                    avail_height,
                    add_plugin_by_name,
                    add_rack_to_track,
                    refresh_fx_list,
                    state
                )
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
            elseif is_container_fx then
                -- Draw unknown container
                chain_item.draw_container_item(ctx, fx)
            else
                -- Draw device (full UI or fallback)
                chain_item.draw_device_item(ctx, fx, item, avail_height, {
                    missing_utility = item.missing_utility,  -- Pass missing utility flag
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
                    on_plugin_drop = function(plugin_name, insert_pos, plugin_drop_opts)
                        add_plugin_by_name(plugin_name, insert_pos, plugin_drop_opts)
                    end,
                    on_rack_drop = function(insert_pos)
                        add_rack_to_track(insert_pos)
                    end,
                })
            end

            ctx:pop_id()

            -- Break immediately if deletion or invalidation occurred - remaining items have stale pointers
            if state.deletion_pending or state.fx_list_invalid then
                break
            end
        end

        -- Always show add button at end of chain (full height drop zone)
        ctx:same_line()

        if is_dragging then
            ctx:push_style_color(imgui.Col.Button(), 0x4488FF44)
            ctx:push_style_color(imgui.Col.ButtonHovered(), 0x66AAFF88)
            ctx:push_style_color(imgui.Col.ButtonActive(), 0x88CCFFAA)
        else
            ctx:push_style_color(imgui.Col.Button(), 0x3A4A5A44)
            ctx:push_style_color(imgui.Col.ButtonHovered(), 0x4A6A8A88)
            ctx:push_style_color(imgui.Col.ButtonActive(), 0x5A8ABAAA)
        end

        ctx:button("+##add_end", 40, drop_h)
        ctx:pop_style_color(3)

        if ctx:is_item_hovered() then
            ctx:set_tooltip("Drag plugin or rack here")
        end

        -- Drop target for plugins and racks
        if ctx:begin_drag_drop_target() then
            local accepted, plugin_name = ctx:accept_drag_drop_payload("PLUGIN_ADD")
            if accepted and plugin_name then
                -- Check for Shift key = add as bare device (no utility)
                local shift_held = r.ImGui_IsKeyDown(ctx.ctx, r.ImGui_Mod_Shift())
                local add_opts = shift_held and { bare = true } or nil
                add_plugin_by_name(plugin_name, nil, add_opts)  -- nil = add at end
            end
            -- Accept rack drops
            local rack_accepted = ctx:accept_drag_drop_payload("RACK_ADD")
            if rack_accepted then
                add_rack_to_track(nil)  -- nil = add at end
            end
            ctx:end_drag_drop_target()
        end
    end  -- end of else (non-empty chain)

    -- Post FX area (flows right after main chain)
    ctx:same_line()

    -- Draw vertical separator line
    local sep_x, sep_y = r.ImGui_GetCursorScreenPos(ctx.ctx)
    local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)
    r.ImGui_DrawList_AddLine(draw_list, sep_x + 4, sep_y, sep_x + 4, sep_y + drop_h, 0x666688FF, 2)
    ctx:dummy(10, drop_h)

    ctx:same_line()

    -- Render existing post FX devices
    local bare_device_panel = require('lib.ui.device.bare_device_panel')
    for post_idx, item in ipairs(post_chain) do
        if state.deletion_pending or state.fx_list_invalid then
            break
        end

        ctx:push_id("post_device_" .. post_idx)
        bare_device_panel.draw(ctx, item.fx, {
            avail_height = avail_height - 10,
            on_delete = function(fx_to_delete)
                local state_module = require('lib.core.state')
                state_module.state.deletion_pending = true
                fx_to_delete:delete()
                state_module.state.fx_list = nil
            end,
            on_drop = function(dragged_guid, target_guid)
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
        ctx:pop_id()
        ctx:same_line()
    end

    -- Post FX add button/drop zone
    local post_btn_width = 50

    if is_dragging then
        ctx:push_style_color(imgui.Col.Button(), 0x88446644)
        ctx:push_style_color(imgui.Col.ButtonHovered(), 0xAA668888)
        ctx:push_style_color(imgui.Col.ButtonActive(), 0xCC88AAAA)
    else
        ctx:push_style_color(imgui.Col.Button(), 0x44335544)
        ctx:push_style_color(imgui.Col.ButtonHovered(), 0x66557788)
        ctx:push_style_color(imgui.Col.ButtonActive(), 0x887799AA)
    end

    ctx:button("+##post_add", post_btn_width, drop_h)
    ctx:pop_style_color(3)

    if ctx:is_item_hovered() then
        ctx:set_tooltip("Post FX area\nDrag plugin here for post-processing")
    end

    -- Drop target for post FX (always creates bare devices at end)
    if ctx:begin_drag_drop_target() then
        local accepted, plugin_name = ctx:accept_drag_drop_payload("PLUGIN_ADD")
        if accepted and plugin_name then
            -- Explicitly get FX count to ensure it's added at the very end
            local fx_count = state.track:get_track_fx_count()
            add_plugin_by_name(plugin_name, fx_count, { bare = true, post = true })
        end
        -- Accept FX reorder drops
        local fx_accepted, fx_guid = ctx:accept_drag_drop_payload("FX_GUID")
        if fx_accepted and fx_guid then
            local dragged = state.track:find_fx_by_guid(fx_guid)
            if dragged then
                -- Move to end (post position)
                local fx_count = state.track:get_track_fx_count()
                r.TrackFX_CopyToTrack(
                    state.track.pointer, dragged.pointer,
                    state.track.pointer, fx_count,
                    true  -- move
                )
                refresh_fx_list()
            end
        end
        ctx:end_drag_drop_target()
    end

    -- Extra padding at end
    ctx:same_line()
    ctx:dummy(20, 1)
end

return M
