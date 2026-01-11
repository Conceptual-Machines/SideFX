--- Chain Column UI Component
-- Draws the expanded chain column showing devices within a rack chain
-- @module ui.chain_column
-- @author Nomad Monad
-- @license MIT

local imgui = require('imgui')
local r = reaper
local fx_utils = require('lib.fx.fx_utils')

local M = {}

-- Lazy-loaded modules
local device_panel = nil

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

--- Draw arrow separator between devices in chain
-- @param ctx ImGui context
-- @param is_first boolean Whether this is the first device (no arrow)
local function draw_device_separator(ctx, is_first)
    if is_first then return end
    ctx:same_line()
    ctx:push_style_color(imgui.Col.Text(), 0x555555FF)
    ctx:text("→")
    ctx:pop_style_color()
    ctx:same_line()
end

--- Draw chain column header with name and identifier
-- @param ctx ImGui context
-- @param chain_name string Display name of chain
-- @param chain_id string|nil Chain identifier (e.g., "R1_C1")
-- @param default_font ImGui font handle (optional)
local function draw_chain_header(ctx, chain_name, chain_id, default_font)
    ctx:table_next_row(0, 20)  -- Smaller row height (20px)
    ctx:table_set_column_index(0)
    if default_font then
        ctx:push_font(default_font, 12)  -- 12px smaller font for header
    end
    ctx:text_colored(0xAAAAAAFF, "Chain:")
    ctx:same_line()
    ctx:text(chain_name)
    if chain_id then
        ctx:same_line()
        ctx:text_colored(0x888888FF, " [" .. chain_id .. "]")
    end
    if default_font then
        ctx:pop_font()
    end
    ctx:separator()
end

--- Draw empty chain content with drop zone
-- @param ctx ImGui context
-- @param chain_content_h number Available height for content
-- @param has_payload boolean Whether there's a drag/drop payload
-- @param selected_chain TrackFX Selected chain container
-- @param add_device_to_chain function (chain, plugin) -> nil
-- @param add_rack_to_chain function (chain) -> nil
local function draw_empty_chain_content(ctx, chain_content_h, has_payload, selected_chain, add_device_to_chain, add_rack_to_chain)
    if has_payload then
        ctx:push_style_color(imgui.Col.Button(), 0x4488FF66)
    else
        ctx:push_style_color(imgui.Col.Button(), 0x33333344)
    end
    ctx:button("+ Drop plugin or rack to add first device", 250, chain_content_h - 20)
    ctx:pop_style_color()

    if ctx:begin_drag_drop_target() then
        local accepted, plugin_name = ctx:accept_drag_drop_payload("PLUGIN_ADD")
        if accepted and plugin_name then
            r.ShowConsoleMsg(string.format("SideFX: Empty chain drag-drop accepted: plugin=%s\n", plugin_name))
            local plugin = { full_name = plugin_name, name = plugin_name }
            add_device_to_chain(selected_chain, plugin)
        end
        local rack_accepted = ctx:accept_drag_drop_payload("RACK_ADD")
        if rack_accepted then
            add_rack_to_chain(selected_chain)
        end
        ctx:end_drag_drop_target()
    end
end

--- Draw add button at end of chain with conditional styling
-- @param ctx ImGui context
-- @param chain_content_h number Available height
-- @param has_payload boolean Whether there's a drag/drop payload
-- @param selected_chain TrackFX Selected chain container
-- @param add_device_to_chain function (chain, plugin) -> nil
-- @param add_rack_to_chain function (chain) -> nil
local function draw_chain_add_button(ctx, chain_content_h, has_payload, selected_chain, add_device_to_chain, add_rack_to_chain)
    ctx:same_line(0, 4)
    local add_btn_h = chain_content_h - 20
    if has_payload then
        ctx:push_style_color(imgui.Col.Button(), 0x4488FF66)
        ctx:push_style_color(imgui.Col.ButtonHovered(), 0x66AAFF88)
        ctx:button("+##chain_drop", 40, add_btn_h)
        ctx:pop_style_color(2)
    else
        ctx:push_style_color(imgui.Col.Button(), 0x3A4A5A88)
        ctx:push_style_color(imgui.Col.ButtonHovered(), 0x4A6A8AAA)
        ctx:button("+##chain_add", 40, add_btn_h)
        ctx:pop_style_color(2)
    end

    if ctx:begin_drag_drop_target() then
        local accepted, plugin_name = ctx:accept_drag_drop_payload("PLUGIN_ADD")
        if accepted and plugin_name then
            local plugin = { full_name = plugin_name, name = plugin_name }
            add_device_to_chain(selected_chain, plugin)
        end
        local rack_accepted = ctx:accept_drag_drop_payload("RACK_ADD")
        if rack_accepted then
            add_rack_to_chain(selected_chain)
        end
        ctx:end_drag_drop_target()
    end

    if ctx:is_item_hovered() then
        ctx:set_tooltip("Drag plugin or rack here to add")
    end
end

--- Draw device panel or fallback button
-- @param ctx ImGui context
-- @param dev TrackFX Device container FX
-- @param chain_content_h number Available height for content
-- @param selected_chain TrackFX Selected chain container
-- @param callbacks table Callbacks table (passed to device_panel.draw)
-- @param device_panel module Device panel module (optional)
-- @param get_device_main_fx function (container) -> TrackFX|nil
-- @param get_device_utility function (container) -> TrackFX|nil
local function draw_device_in_chain(ctx, dev, chain_content_h, selected_chain, callbacks, device_panel, get_device_main_fx, get_device_utility)
    local dev_main_fx = get_device_main_fx(dev)
    local dev_utility = get_device_utility(dev)
    local dev_name = fx_utils.get_device_display_name(dev)
    local dev_enabled = dev:get_enabled()

    if dev_main_fx and device_panel then
        device_panel.draw(ctx, dev_main_fx, callbacks)
    else
        -- Fallback: simple button
        local btn_color = dev_enabled and 0x3A5A4AFF or 0x2A2A35FF
        ctx:push_style_color(imgui.Col.Button(), btn_color)
        if ctx:button(dev_name:sub(1, 20) .. "##dev_fallback_" .. dev:get_guid(), 120, chain_content_h - 20) then
            dev:show(3)
        end
        ctx:pop_style_color()
    end
end

--- Find a chain by GUID in a list of chains
-- @param chains table Array of chain FX objects
-- @param target_guid string GUID to search for
-- @return TrackFX|nil Chain FX or nil if not found
local function find_chain_by_guid(chains, target_guid)
    for _, chain in ipairs(chains) do
        local ok_guid, chain_guid = pcall(function() return chain:get_guid() end)
        if ok_guid and chain_guid and chain_guid == target_guid then
            return chain
        end
    end
    return nil
end

--- Draw nested rack and its selected chain column
-- @param ctx ImGui context
-- @param dev TrackFX Rack container FX
-- @param chain_content_h number Available height for content
-- @param draw_rack_panel function (ctx, rack, avail_height, is_nested) -> table
-- @param draw_chain_column_fn function (ctx, chain, rack_h, opts) -> nil
-- @param state table State table
-- @param opts table Options for chain_column.draw
local function draw_nested_rack_in_chain(ctx, dev, chain_content_h, draw_rack_panel, draw_chain_column_fn, state, opts)
    -- Safety check: draw_rack_panel must be provided
    if not draw_rack_panel then
        -- Draw placeholder for nested rack when draw_rack_panel is not available
        ctx:text("[Nested Rack]")
        return
    end

    local rack_data = draw_rack_panel(ctx, dev, chain_content_h - 20, true)

    -- If a chain in this nested rack is selected, show its chain column
    local rack_guid = dev:get_guid()
    local nested_chain_guid = state.expanded_nested_chains[rack_guid]
    if rack_data.is_expanded and nested_chain_guid then
        local nested_chain = find_chain_by_guid(rack_data.chains, nested_chain_guid)
        if nested_chain then
            ctx:same_line()
            draw_chain_column_fn(ctx, nested_chain, rack_data.rack_h, opts)
        end
    end
end

--------------------------------------------------------------------------------
-- Main Drawing Function
--------------------------------------------------------------------------------

--- Draw expanded chain column with devices
-- @param ctx ImGui context wrapper
-- @param selected_chain TrackFX Selected chain container
-- @param rack_h number Rack height
-- @param opts table Options:
--   - state: State table
--   - get_fx_display_name: function (fx) -> string
--   - refresh_fx_list: function () -> nil
--   - get_device_main_fx: function (container) -> TrackFX|nil
--   - get_device_utility: function (container) -> TrackFX|nil
--   - is_rack_container: function (fx) -> boolean
--   - add_device_to_chain: function (chain, plugin) -> nil
--   - add_rack_to_chain: function (chain) -> nil
--   - draw_rack_panel: function (ctx, rack, avail_height, is_nested) -> table
--   - icon_font: ImGui font handle (optional)
--   - default_font: ImGui font handle (optional)
function M.draw(ctx, selected_chain, rack_h, opts)
    local state = opts.state
    local get_fx_display_name = opts.get_fx_display_name
    local refresh_fx_list = opts.refresh_fx_list
    local get_device_main_fx = opts.get_device_main_fx
    local get_device_utility = opts.get_device_utility
    local is_rack_container = opts.is_rack_container
    local add_device_to_chain = opts.add_device_to_chain
    local add_rack_to_chain = opts.add_rack_to_chain
    local draw_rack_panel = opts.draw_rack_panel
    local icon_font = opts.icon_font
    local default_font = opts.default_font

    -- Lazy load device_panel
    if not device_panel then
        local ok, mod = pcall(require, 'lib.ui.device.device_panel')
        if ok then device_panel = mod end
    end

    local selected_chain_guid = selected_chain:get_guid()
    -- Get chain name and identifier separately
    local chain_name_full = fx_utils.get_chain_label_name(selected_chain)
    local fx_naming = require('lib.fx.fx_naming')
    local chain_name = fx_naming.get_short_path(chain_name_full)

    local chain_id = nil
    local ok_name, raw_name = pcall(function() return selected_chain:get_name() end)
    if ok_name and raw_name then
        local chain_id_full = raw_name:match("^(R%d+_C%d+)") or raw_name:match("R%d+_C%d+")
        if chain_id_full then
            chain_id = fx_naming.get_short_path(chain_id_full)
        end
    end

    -- Get devices from chain
    local devices = {}
    for child in selected_chain:iter_container_children() do
        local ok, child_name = pcall(function() return child:get_name() end)
        if ok and child_name then
            table.insert(devices, child)
        end
    end

    local chain_content_h = rack_h - 30  -- Leave room for header
    local has_plugin_payload = ctx:get_drag_drop_payload("PLUGIN_ADD")
    local has_rack_payload = ctx:get_drag_drop_payload("RACK_ADD")

    -- Auto-resize wrapper to fit content (Border=1, AutoResizeX=16)
    local wrapper_flags = 17  -- Border + AutoResizeX

    -- Add padding around content, especially on the right
    ctx:push_style_var(imgui.StyleVar.WindowPadding(), 12, 8)

    ctx:push_style_color(imgui.Col.ChildBg(), 0x252530FF)
    local window_flags = imgui.WindowFlags.NoScrollbar()
    if ctx:begin_child("chain_wrapper_" .. selected_chain_guid, 0, rack_h, wrapper_flags, window_flags) then
        -- Wrap in pcall to ensure end_child is always called
        local ok, err = pcall(function()
            -- Use table layout so header width matches content width
            local table_flags = imgui.TableFlags.SizingStretchSame()
            if ctx:begin_table("chain_table_" .. selected_chain_guid, 1, table_flags) then
                -- Draw header with chain name and identifier
                draw_chain_header(ctx, chain_name, chain_id, default_font)

                -- Row 2: Content
                ctx:table_next_row()
                ctx:table_set_column_index(0)

                -- Chain contents - auto-resize to fit devices
                ctx:push_style_color(imgui.Col.ChildBg(), 0x252530FF)
                local chain_content_flags = 81  -- Border (1) + AutoResizeX (16) + AlwaysAutoResize (64)
                if ctx:begin_child("chain_contents_" .. selected_chain_guid, 0, chain_content_h, chain_content_flags) then
                    -- Inner pcall for chain contents
                    local ok_inner, err_inner = pcall(function()
                        if #devices == 0 then
                            -- Empty chain - show drop zone
                            draw_empty_chain_content(ctx, chain_content_h, has_plugin_payload or has_rack_payload, selected_chain, add_device_to_chain, add_rack_to_chain)
                        else
                            -- Draw each device or rack HORIZONTALLY with arrows
                            ctx:begin_group()

                            for k, dev in ipairs(devices) do
                                -- Draw arrow separator between devices
                                draw_device_separator(ctx, k == 1)

                                -- Draw device or nested rack
                                if is_rack_container(dev) then
                                    draw_nested_rack_in_chain(ctx, dev, chain_content_h, draw_rack_panel, M.draw, state, opts)
                                else
                                    draw_device_in_chain(ctx, dev, chain_content_h, selected_chain, {
                                        avail_height = chain_content_h - 20,
                                        utility = get_device_utility(dev),
                                        container = dev,
                                        icon_font = icon_font,
                                        track = state.track,
                                        refresh_fx_list = refresh_fx_list,
                                        on_delete = function()
                                            dev:delete()
                                            refresh_fx_list()
                                        end,
                                        on_rename = function(fx)
                                            -- Rename the container (dev), not the main FX
                                            local dev_guid = dev:get_guid()
                                            state.renaming_fx = dev_guid
                                            state.rename_text = get_fx_display_name(dev)
                                        end,
                                        on_plugin_drop = function(plugin_name, insert_before_idx)
                                            local plugin = { full_name = plugin_name, name = plugin_name }
                                            add_device_to_chain(selected_chain, plugin)
                                        end,
                                    }, device_panel, get_device_main_fx, get_device_utility)
                                end
                            end

                            -- Draw add button at end of chain
                            draw_chain_add_button(ctx, chain_content_h, has_plugin_payload or has_rack_payload, selected_chain, add_device_to_chain, add_rack_to_chain)

                            ctx:end_group()
                        end
                    end)
                    ctx:end_child()  -- Always end chain_contents child
                    if not ok_inner then
                        reaper.ShowConsoleMsg("SideFX chain contents error: " .. tostring(err_inner) .. "\n")
                    end
                end
                ctx:pop_style_color()

                ctx:end_table()
            end
        end)
        ctx:end_child()  -- Always end chain_wrapper child
        if not ok then
            reaper.ShowConsoleMsg("SideFX chain column error: " .. tostring(err) .. "\n")
        end
    end
    ctx:pop_style_color()
    ctx:pop_style_var()
end

return M
