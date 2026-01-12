--- Toolbar UI Component
-- Top toolbar with refresh, add buttons, and breadcrumb navigation
-- @module ui.toolbar
-- @author Nomad Monad
-- @license MIT

local imgui = require('imgui')
local constants = require('lib.core.constants')
local config = require('lib.core.config')

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
    local emojimgui = package.loaded['emojimgui'] or require('emojimgui')

    -- Use table with 2 columns: left content and right buttons
    if ctx:begin_table("toolbar", 2, imgui.TableFlags.SizingStretchProp()) then
        ctx:table_setup_column("left", imgui.TableColumnFlags.WidthStretch())
        ctx:table_setup_column("right", imgui.TableColumnFlags.WidthFixed())

        ctx:table_next_row()

        -- LEFT COLUMN: Refresh, Add Rack, Track name, Breadcrumbs
        ctx:table_set_column_index(0)

        -- Refresh button
        if icon_font then ctx:push_font(icon_font, icon_size) end
        local refresh_icon = constants.icon_text(emojimgui, constants.Icons.arrows_counterclockwise)
        if ctx:button(refresh_icon) then
            callbacks.on_refresh()
            -- Set status message
            local plugin_count = state.browser and state.browser.plugins and #state.browser.plugins or 0
            status_message = string.format("Rescanned %d plugins", plugin_count)
            status_time = reaper.time_precise()
        end
        if icon_font then ctx:pop_font() end
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
        local browser_btn_color = browser_visible and 0x446644FF or 0x444444FF
        ctx:push_style_color(imgui.Col.Button(), browser_btn_color)
        if ctx:button(browser_visible and "Browser" or "Browser", 0, BUTTON_HEIGHT) then
            if state.browser then
                state.browser.visible = not state.browser.visible
            end
        end
        ctx:pop_style_color()
        if ctx:is_item_hovered() then
            ctx:set_tooltip(browser_visible and "Hide plugin browser" or "Show plugin browser")
        end

        ctx:same_line()

        -- Add Rack button (also draggable)
        ctx:push_style_color(imgui.Col.Button(), 0x446688FF)
        if ctx:button("+ Rack", 0, BUTTON_HEIGHT) then
            if state.track then
                callbacks.on_add_rack()
            end
        end
        ctx:pop_style_color()
        -- Drag source for rack
        if ctx:begin_drag_drop_source() then
            ctx:set_drag_drop_payload("RACK_ADD", "new_rack")
            ctx:text("Drop to create Rack")
            ctx:end_drag_drop_source()
        end
        if ctx:is_item_hovered() then ctx:set_tooltip("Click to add rack at end\nOr drag to drop anywhere") end

        -- Track name (if enabled)
        if config.get('show_track_name') then
            ctx:same_line()
            ctx:text("|")
            ctx:same_line()
            ctx:push_style_color(imgui.Col.Text(), 0xAADDFFFF)
            ctx:text(state.track_name)
            ctx:pop_style_color()
        end

        -- Breadcrumb trail (for navigating into containers)
        if config.get('show_breadcrumbs') and state.track and #state.expanded_path > 0 then
            -- Build list of valid breadcrumb items
            local breadcrumbs = {}
            for i, guid in ipairs(state.expanded_path) do
                local ok, container = pcall(function() return state.track:find_fx_by_guid(guid) end)
                if ok and container then
                    local ok_name, name = pcall(function() return get_fx_display_name(container) end)
                    if ok_name and name then
                        table.insert(breadcrumbs, { index = i, name = name, guid = guid })
                    end
                end
            end

            -- Only display if we have valid breadcrumbs
            if #breadcrumbs > 0 then
                ctx:same_line()
                ctx:text_disabled(">")
                for j, crumb in ipairs(breadcrumbs) do
                    ctx:same_line()
                    if ctx:small_button(crumb.name .. "##bread_" .. crumb.index) then
                        callbacks.on_collapse_from_depth(crumb.index + 1)
                    end
                    if j < #breadcrumbs then
                        ctx:same_line()
                        ctx:text_disabled(">")
                    end
                end
            end
        end

        -- RIGHT COLUMN: Preset and Config buttons
        ctx:table_set_column_index(1)

        local button_width = 30

        -- Preset button
        if icon_font then ctx:push_font(icon_font, icon_size) end
        local preset_icon = constants.icon_text(emojimgui, constants.Icons.floppy_disk)
        if ctx:button(preset_icon .. "##preset", button_width, 0) then
            if callbacks.on_preset then
                callbacks.on_preset()
            end
        end
        if icon_font then ctx:pop_font() end
        if ctx:is_item_hovered() then ctx:set_tooltip("Save/Load Preset") end

        ctx:same_line()

        -- Config button
        if icon_font then ctx:push_font(icon_font, icon_size) end
        local config_icon = constants.icon_text(emojimgui, constants.Icons.gear)
        if ctx:button(config_icon .. "##config", button_width, 0) then
            if callbacks.on_config then
                callbacks.on_config()
            end
        end
        if icon_font then ctx:pop_font() end
        if ctx:is_item_hovered() then ctx:set_tooltip("Settings") end

        -- Add right padding
        ctx:same_line()
        ctx:dummy(8, 0)

        ctx:end_table()
    end
end

return M
