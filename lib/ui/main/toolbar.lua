--- Toolbar UI Component
-- Top toolbar with refresh, add buttons, and breadcrumb navigation
-- @module ui.toolbar
-- @author Nomad Monad
-- @license MIT

local imgui = require('imgui')
local config = require('lib.core.config')
local icons = require('lib.ui.common.icons')

local M = {}

-- Status message state
local status_message = nil
local status_time = 0
local STATUS_DURATION = 2.0  -- seconds to show message

-- Button sizing
local BUTTON_HEIGHT = 24  -- Match icon button height

--------------------------------------------------------------------------------
-- Toolbar
--------------------------------------------------------------------------------

--- Draw the toolbar
-- @param ctx ImGui context wrapper
-- @param state table State object
-- @param icon_font ImGui font handle for icons (optional)
-- @param icon_size number Size of icon font (optional)
-- @param get_fx_display_name function Function to get display name: (fx) -> string
-- @param callbacks table Callbacks:
--   - on_refresh: () -> nil
--   - on_add_rack: () -> nil
--   - on_collapse_from_depth: (depth) -> nil
function M.draw(ctx, state, icon_font, icon_size, get_fx_display_name, callbacks)
    local r = reaper

    -- Helper to draw vertical separator (matching button height)
    local function draw_separator()
        local x, y = r.ImGui_GetCursorScreenPos(ctx.ctx)
        local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)
        r.ImGui_Dummy(ctx.ctx, 8, 26)
        r.ImGui_DrawList_AddLine(draw_list, x + 4, y + 3, x + 4, y + 23, 0x666666FF, 1)
    end

    -- Use table with 2 columns: left content and right buttons
    if ctx:begin_table("toolbar", 2, imgui.TableFlags.SizingStretchProp()) then
        ctx:table_setup_column("left", imgui.TableColumnFlags.WidthStretch())
        ctx:table_setup_column("right", imgui.TableColumnFlags.WidthFixed())

        ctx:table_next_row()

        -- LEFT COLUMN: Refresh, Add Rack, Track name, Breadcrumbs
        ctx:table_set_column_index(0)

        -- Refresh button
        if icons.button_bordered(ctx, "refresh_btn", icons.Names.refresh, 26) then
            callbacks.on_refresh()
            -- Set status message
            local plugin_count = state.browser and state.browser.plugins and #state.browser.plugins or 0
            status_message = string.format("Rescanned %d plugins", plugin_count)
            status_time = reaper.time_precise()
        end
        if ctx:is_item_hovered() then ctx:set_tooltip("Refresh FX list & rescan plugins") end

        -- Show status message if recent
        if status_message then
            local elapsed = reaper.time_precise() - status_time
            if elapsed < STATUS_DURATION then
                ctx:same_line()
                -- Fade out effect (green text with fading alpha)
                local alpha = math.floor(255 * (1 - elapsed / STATUS_DURATION))
                local color = 0x88CC8800 + alpha  -- RRGGBBAA format
                ctx:text_colored(color, status_message)
            else
                status_message = nil
            end
        end

        ctx:same_line()

        -- Browser toggle button
        local browser_visible = state.browser and state.browser.visible
        local browser_tint = browser_visible and 0x88FF88FF or 0xCCCCCCFF
        if icons.button_bordered(ctx, "browser_btn", icons.Names.plug, 26, browser_tint) then
            if state.browser then
                state.browser.visible = not state.browser.visible
            end
        end
        if ctx:is_item_hovered() then
            ctx:set_tooltip(browser_visible and "Hide plugin browser" or "Show plugin browser")
        end

        ctx:same_line()

        -- Add Rack button (also draggable)
        if icons.button_bordered(ctx, "rack_btn", icons.Names.rack, 26, 0x88AAFFFF) then
            if state.track then
                callbacks.on_add_rack()
            end
        end
        -- Drag source for rack
        if ctx:begin_drag_drop_source() then
            ctx:set_drag_drop_payload("RACK_ADD", "new_rack")
            ctx:text("Drop to create Rack")
            ctx:end_drag_drop_source()
        end
        if ctx:is_item_hovered() then ctx:set_tooltip("Click to add rack at end\nOr drag to drop anywhere") end

        -- Helper to draw breadcrumb-style button
        local function draw_breadcrumb_button(ctx, label, id)
            local r = reaper
            r.ImGui_PushStyleVar(ctx.ctx, r.ImGui_StyleVar_FramePadding(), 8, 5)
            r.ImGui_PushStyleVar(ctx.ctx, r.ImGui_StyleVar_FrameRounding(), 3)
            r.ImGui_PushStyleVar(ctx.ctx, r.ImGui_StyleVar_FrameBorderSize(), 1)
            r.ImGui_PushStyleColor(ctx.ctx, r.ImGui_Col_Button(), 0x333333FF)
            r.ImGui_PushStyleColor(ctx.ctx, r.ImGui_Col_ButtonHovered(), 0x444444FF)
            r.ImGui_PushStyleColor(ctx.ctx, r.ImGui_Col_ButtonActive(), 0x555555FF)
            r.ImGui_PushStyleColor(ctx.ctx, r.ImGui_Col_Border(), 0x555555FF)
            local clicked = ctx:button(label .. "##" .. id)
            r.ImGui_PopStyleColor(ctx.ctx, 4)
            r.ImGui_PopStyleVar(ctx.ctx, 3)
            return clicked
        end

        -- Track name (if enabled) - styled as breadcrumb button
        -- Fetch fresh from track object to handle renames
        if config.get('show_track_name') and state.track then
            local ok, track_name = pcall(function() return state.track:get_name() end)
            if ok and track_name then
                ctx:same_line()
                draw_separator()
                ctx:same_line()
                draw_breadcrumb_button(ctx, track_name, "track_name")
            end
        end

        -- Breadcrumb trail (for navigating into containers)
        if config.get('show_breadcrumbs') and state.track and #state.expanded_path > 0 then
            -- Build list of valid breadcrumb items
            local breadcrumbs = {}
            for i, guid in ipairs(state.expanded_path) do
                local ok, container = pcall(function() return state.track:find_fx_by_guid(guid) end)
                if ok and container then
                    local ok_raw, raw_name = pcall(function() return container:get_name() end)
                    if ok_raw and raw_name then
                        -- Get consistent display name based on container type
                        local display_name
                        if raw_name:match("^R%d+$") then
                            -- Rack (just "R1", "R2", etc.): use "Rack" or custom display name
                            display_name = get_fx_display_name(container)
                        elseif raw_name:match("C%d+") then
                            -- Chain: extract chain number and show "Chain N"
                            -- Handles both "C1" and "R2_C1" formats
                            local chain_num = raw_name:match("C(%d+)")
                            display_name = "Chain " .. (chain_num or "?")
                        else
                            display_name = get_fx_display_name(container)
                        end
                        table.insert(breadcrumbs, { index = i, name = display_name, guid = guid })
                    end
                end
            end

            -- Only display if we have valid breadcrumbs
            if #breadcrumbs > 0 then
                ctx:same_line()
                ctx:text_disabled(">")
                for j, crumb in ipairs(breadcrumbs) do
                    ctx:same_line()
                    if draw_breadcrumb_button(ctx, crumb.name, "bread_" .. crumb.index) then
                        callbacks.on_collapse_from_depth(crumb.index + 1)
                    end
                    if j < #breadcrumbs then
                        ctx:same_line()
                        ctx:text_disabled(">")
                    end
                end
            end
        end

        -- RIGHT COLUMN: Scope, Spectrum, Preset, and Config buttons
        ctx:table_set_column_index(1)

        -- Scope button (singleton - toggles on/off)
        local has_scope = state.has_scope or false
        local scope_tint = has_scope and 0x88FF88FF or 0xCCCCCCFF
        if icons.button_bordered(ctx, "scope_btn", icons.Names.oscilloscope, 26, scope_tint) then
            if state.track and callbacks.on_toggle_scope then
                callbacks.on_toggle_scope()
            end
        end
        if ctx:is_item_hovered() then
            ctx:set_tooltip(has_scope and "Remove oscilloscope" or "Add oscilloscope at end of chain")
        end

        ctx:same_line()

        -- Spectrum button (singleton - toggles on/off)
        local has_spectrum = state.has_spectrum or false
        local spectrum_tint = has_spectrum and 0x88FF88FF or 0xCCCCCCFF
        if icons.button_bordered(ctx, "spectrum_btn", icons.Names.spectrum, 26, spectrum_tint) then
            if state.track and callbacks.on_toggle_spectrum then
                callbacks.on_toggle_spectrum()
            end
        end
        if ctx:is_item_hovered() then
            ctx:set_tooltip(has_spectrum and "Remove spectrum analyzer" or "Add spectrum analyzer at end of chain")
        end

        ctx:same_line()
        draw_separator()
        ctx:same_line()

        -- Preset button
        if icons.button_bordered(ctx, "preset_btn", icons.Names.save, 26) then
            if callbacks.on_preset then
                callbacks.on_preset()
            end
        end
        if ctx:is_item_hovered() then ctx:set_tooltip("Save/Load Preset") end

        ctx:same_line()

        -- Config button
        if icons.button_bordered(ctx, "config_btn", icons.Names.gear, 26) then
            if callbacks.on_config then
                callbacks.on_config()
            end
        end
        if ctx:is_item_hovered() then ctx:set_tooltip("Settings") end

        -- Add right padding
        ctx:same_line()
        ctx:dummy(8, 0)

        ctx:end_table()
    end
end

return M
