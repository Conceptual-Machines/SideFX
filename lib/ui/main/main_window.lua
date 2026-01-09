--- Main Window UI Component
-- Handles the main window callbacks (on_close, on_draw)
-- @module ui.main_window
-- @author Nomad Monad
-- @license MIT

local imgui = require('imgui')
local r = reaper

local M = {}

--- Draw the "not a SideFX track" warning message with conversion button.
-- @param ctx ImGui context
-- @param state State table
-- @param device_module Device module (for conversion)
-- @param refresh_fx_list Function to refresh FX list after conversion
local function draw_not_sidefx_warning(ctx, state, device_module, refresh_fx_list)
    local avail_w, avail_h = ctx:get_content_region_avail()
    local msg_w = 400
    local msg_h = 120  -- Increased height for button
    local msg_x = (avail_w - msg_w) / 2
    local msg_y = (avail_h - msg_h) / 2

    -- Position using dummy spacing
    if msg_y > 0 then
        ctx:dummy(0, msg_y)
    end
    if msg_x > 0 then
        ctx:dummy(msg_x, 0)
        ctx:same_line()
    end

    -- Warning message with red border
    ctx:push_style_color(imgui.Col.ChildBg(), 0x2A1A1AFF)  -- Slightly red-tinted background
    ctx:push_style_var(imgui.StyleVar.WindowPadding(), 20, 15)
    if ctx:begin_child("not_sidefx_msg", msg_w, msg_h, 0) then
        -- Get window bounds for border drawing
        local window_min_x, window_min_y = r.ImGui_GetWindowPos(ctx.ctx)
        local window_max_x = window_min_x + r.ImGui_GetWindowWidth(ctx.ctx)
        local window_max_y = window_min_y + r.ImGui_GetWindowHeight(ctx.ctx)
        local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)
        local border_thickness = 2.0

        -- Draw red border rectangle around the child window
        r.ImGui_DrawList_AddRect(draw_list, window_min_x, window_min_y, window_max_x, window_max_y, 0xFF0000FF, 0, 0, border_thickness)

        -- Center the text using available space
        local track_name = state.track_name or "Unknown"
        local text = string.format("Track '%s' is not a SideFX track", track_name)
        local text_w, text_h = ctx:calc_text_size(text)
        local child_w, child_h = ctx:get_content_region_avail()
        
        -- Center vertically (accounting for button below)
        local text_x = (child_w - text_w) / 2
        local text_y = (child_h - text_h - 35) / 2  -- Leave space for button
        if text_y > 0 then
            ctx:dummy(0, text_y)
        end
        if text_x > 0 then
            ctx:dummy(text_x, 0)
            ctx:same_line()
        end
        ctx:push_style_color(imgui.Col.Text(), 0xFFFFAAFF)  -- Yellow text for warning
        ctx:text(text)
        ctx:pop_style_color()
        
        -- Convert button
        ctx:dummy(0, 10)  -- Spacing
        local btn_w = 200
        local btn_x = (child_w - btn_w) / 2
        if btn_x > 0 then
            ctx:dummy(btn_x, 0)
            ctx:same_line()
        end
        
        if device_module and device_module.convert_track_to_sidefx then
            if ctx:button("Convert to SideFX Track", btn_w, 0) then
                local success = device_module.convert_track_to_sidefx()
                if success then
                    -- Refresh FX list to show converted structure
                    refresh_fx_list()
                end
            end
        end
    end
    ctx:end_child()
    ctx:pop_style_var()
    ctx:pop_style_color()
end

--- Draw FX chain protection warning banner.
-- Shows when FX chain has been modified externally (outside SideFX).
-- @param ctx ImGui context
-- @param state_module State module
local function draw_fx_chain_warning_banner(ctx, state_module)
    local avail_w = ctx:get_content_region_avail_width()
    
    -- Warning banner with yellow/orange background
    ctx:push_style_color(imgui.Col.ChildBg(), 0x4A3A1AFF)  -- Dark yellow/orange
    ctx:push_style_color(imgui.Col.Text(), 0xFFFFAAFF)  -- Light yellow text
    ctx:push_style_var(imgui.StyleVar.WindowPadding(), 12, 8)
    
    -- Use auto height for banner
    if ctx:begin_child("fx_chain_warning", avail_w, -1, 0) then
        ctx:push_style_color(imgui.Col.Text(), 0xFFFF00FF)  -- Bright yellow for warning icon
        ctx:text("⚠️")
        ctx:pop_style_color()
        
        ctx:same_line()
        ctx:text("FX chain has been modified outside SideFX. This may break SideFX structure.")
        
        ctx:same_line()
        local button_w = 120
        local spacing = 8
        
        -- "Revert Changes" button
        ctx:push_style_color(imgui.Col.Button(), 0x663333FF)  -- Dark red
        ctx:push_style_color(imgui.Col.ButtonHovered(), 0x884444FF)  -- Lighter red
        if ctx:button("Revert Changes", button_w, 0) then
            state_module.revert_fx_chain_changes()
        end
        ctx:pop_style_color(2)
        
        ctx:same_line()
        ctx:dummy(spacing, 0)
        ctx:same_line()
        
        -- "Refresh SideFX" button
        ctx:push_style_color(imgui.Col.Button(), 0x336633FF)  -- Dark green
        ctx:push_style_color(imgui.Col.ButtonHovered(), 0x448844FF)  -- Lighter green
        if ctx:button("Refresh SideFX", button_w, 0) then
            state_module.refresh_sidefx_from_reaper()
        end
        ctx:pop_style_color(2)
    end
    ctx:end_child()
    
    ctx:pop_style_var()
    ctx:pop_style_color(2)
end

--- Create window callbacks for SideFX main window
-- @param opts table Options:
--   - state: State table
--   - state_module: State module
--   - default_font: ImGui font handle (will be set if nil)
--   - icon_font: ImGui font handle (will be set if nil)
--   - reaper_theme: Theme module
--   - get_selected_track: function () -> (track, name)
--   - check_fx_changes: function () -> nil
--   - clear_multi_select: function () -> nil
--   - draw_toolbar: function (ctx) -> nil
--   - draw_plugin_browser: function (ctx) -> nil
--   - draw_device_chain: function (ctx, fx_list, width, height) -> nil
--   - refresh_fx_list: function () -> nil
--   - EmojImGui: EmojImGui module
-- @return table {on_close, on_draw}
function M.create_callbacks(opts)
    local state = opts.state
    local state_module = opts.state_module
    local device_module = opts.device_module
    local reaper_theme = opts.reaper_theme
    local get_selected_track = opts.get_selected_track
    local check_fx_changes = opts.check_fx_changes
    local clear_multi_select = opts.clear_multi_select
    local draw_toolbar = opts.draw_toolbar
    local draw_plugin_browser = opts.draw_plugin_browser
    local draw_device_chain = opts.draw_device_chain
    local refresh_fx_list = opts.refresh_fx_list
    local EmojImGui = opts.EmojImGui

    -- Font references (passed in so they can be updated)
    local default_font_ref = opts.default_font_ref or { value = opts.default_font }
    local icon_font_ref = opts.icon_font_ref or { value = opts.icon_font }

    local callbacks = {
        on_close = function(self)
            -- Save expansion state and display names when window closes
            if state.track then
                state_module.save_expansion_state()
                state_module.save_display_names()
            end
        end,

        on_draw = function(self, ctx)
            -- Handle pending deletion: refresh FX list and clear flag
            if state.deletion_pending then
                state.deletion_pending = false
                refresh_fx_list()
            end
            
            reaper_theme:apply(ctx)

            -- Load fonts on first frame
            if not default_font_ref.value then
                -- Create a larger, more legible default font
                -- Try common system fonts that are known to be readable
                local font_families = {
                    "Segoe UI",      -- Windows default
                    "Helvetica Neue", -- macOS default
                    "Arial",         -- Fallback
                    "DejaVu Sans",   -- Linux/common
                }

                for _, family in ipairs(font_families) do
                    -- ImGui_CreateFont takes: family_or_file, size (flags are optional via separate call)
                    default_font_ref.value = r.ImGui_CreateFont(family, 14)
                    if default_font_ref.value then
                        break
                    end
                end

                -- If no font was created, try with a generic name
                if not default_font_ref.value then
                    default_font_ref.value = r.ImGui_CreateFont("", 14)
                end
            end

            -- Push default font if available
            if default_font_ref.value then
                ctx:push_font(default_font_ref.value, 14)
            end

            -- Load icon font on first frame
            if not icon_font_ref.value then
                icon_font_ref.value = EmojImGui.Asset.Font(ctx.ctx, "OpenMoji")
            end

            -- Track change detection
            local track, name = get_selected_track()

            -- Check if current state.track is still valid (not deleted)
            local state_track_valid = false
            if state.track then
                local ok = pcall(function()
                    -- Try to access track info to validate pointer
                    return state.track:get_info_value("IP_TRACKNUMBER")
                end)
                state_track_valid = ok
                if not ok then
                    -- Track was deleted, clear all related state
                    state.track = nil
                    state.top_level_fx = {}
                    state.last_fx_count = 0
                    state.expanded_path = {}
                    state.expanded_racks = {}
                    state.expanded_nested_chains = {}
                    state.selected_fx = nil
                    clear_multi_select()
                end
            end

            local track_changed = (track and state.track and track.pointer ~= state.track.pointer)
                or (track and not state.track)
                or (not track and state.track)
            if track_changed then
                -- Save expansion state for previous track before switching
                -- (save_expansion_state will handle invalid tracks safely)
                if state_track_valid then
                    state_module.save_expansion_state()
                    state_module.save_display_names()
                end

                state.track, state.track_name = track, name
                state.expanded_path = {}
                state.expanded_racks = {}
                state.expanded_nested_chains = {}
                state.display_names = {}  -- Clear display names for new track
                state.selected_fx = nil
                clear_multi_select()
                refresh_fx_list()


                -- Load expansion state for new track
                if state.track then
                    state_module.load_expansion_state()
                    state_module.load_display_names()
                    -- Capture snapshot of FX chain when track changes
                    state_module.capture_fx_chain_snapshot()
                end
            else
                -- Check for external FX changes (e.g. user deleted FX in REAPER)
                check_fx_changes()
                -- Also check for FX chain modifications (every 500ms)
                state_module.check_fx_chain_changes()
                
                -- Capture snapshot on first frame if not already captured
                if state.track and not state.fx_chain_snapshot then
                    state_module.capture_fx_chain_snapshot()
                end
            end

            -- Toolbar
            draw_toolbar(ctx, icon_font_ref)
            ctx:separator()

            -- Layout dimensions
            local browser_w = 260
            local avail_w, avail_h = ctx:get_content_region_avail()

            -- Plugin Browser (fixed left)
            ctx:push_style_color(imgui.Col.ChildBg(), 0x1E1E22FF)
            if ctx:begin_child("Browser", browser_w, 0, imgui.ChildFlags.Border()) then
                ctx:text("Plugins")
                ctx:separator()
                draw_plugin_browser(ctx, icon_font_ref)
                ctx:end_child()
            end
            ctx:pop_style_color()

            ctx:same_line()

            -- Calculate remaining width for device chain
            local chain_w = avail_w - browser_w - 20

            -- Device Chain (horizontal scroll, center area)
            ctx:push_style_color(imgui.Col.ChildBg(), 0x1A1A1EFF)
            local chain_flags = imgui.WindowFlags.HorizontalScrollbar()
            if ctx:begin_child("DeviceChain", chain_w, 0, imgui.ChildFlags.Border(), chain_flags) then

                if not state.track then
                    -- No track selected - show message with red border
                    local avail_w, avail_h = ctx:get_content_region_avail()
                    local msg_w = 300
                    local msg_h = 60
                    local msg_x = (avail_w - msg_w) / 2
                    local msg_y = (avail_h - msg_h) / 2

                    -- Position using dummy spacing
                    if msg_y > 0 then
                        ctx:dummy(0, msg_y)
                    end
                    if msg_x > 0 then
                        ctx:dummy(msg_x, 0)
                        ctx:same_line()
                    end

                    -- Red border using child window with manual border drawing
                    ctx:push_style_color(imgui.Col.ChildBg(), 0x2A1A1AFF)  -- Slightly red-tinted background
                    ctx:push_style_var(imgui.StyleVar.WindowPadding(), 20, 15)
                    if ctx:begin_child("no_track_msg", msg_w, msg_h, 0) then
                        -- Get window bounds for border drawing
                        local window_min_x, window_min_y = r.ImGui_GetWindowPos(ctx.ctx)
                        local window_max_x = window_min_x + r.ImGui_GetWindowWidth(ctx.ctx)
                        local window_max_y = window_min_y + r.ImGui_GetWindowHeight(ctx.ctx)
                        local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)
                        local border_thickness = 2.0

                        -- Draw red border rectangle around the child window
                        r.ImGui_DrawList_AddRect(draw_list, window_min_x, window_min_y, window_max_x, window_max_y, 0xFF0000FF, 0, 0, border_thickness)

                        -- Center the text using available space
                        local text = "Select a track"
                        local text_w, text_h = ctx:calc_text_size(text)
                        local child_w, child_h = ctx:get_content_region_avail()
                        local text_x = (child_w - text_w) / 2
                        local text_y = (child_h - text_h) / 2
                        if text_y > 0 then
                            ctx:dummy(0, text_y)
                        end
                        if text_x > 0 then
                            ctx:dummy(text_x, 0)
                            ctx:same_line()
                        end
                        ctx:push_style_color(imgui.Col.Text(), 0xFFFFFFFF)
                        ctx:text(text)
                        ctx:pop_style_color()
                    end
                    ctx:end_child()
                    ctx:pop_style_var()
                    ctx:pop_style_color()
                else
                    -- Check if track has FX and if it's a SideFX track
                    local has_fx = false
                    local is_sidefx = false
                    local ok_fx, fx_count = pcall(function()
                        return state.track:get_track_fx_count()
                    end)
                    if ok_fx and fx_count and fx_count > 0 then
                        has_fx = true
                        is_sidefx = state_module.is_sidefx_track(state.track)
                    end
                    
                    if has_fx and not is_sidefx then
                        -- Track has FX but is not a SideFX track - show warning message
                        draw_not_sidefx_warning(ctx, state, device_module, refresh_fx_list)
                    else
                        -- Track has no FX or is a SideFX track - proceed normally
                        -- Filter out invalid FX (from deleted tracks)
                        local filtered_fx = {}
                        for _, fx in ipairs(state.top_level_fx) do
                            -- Validate FX is still accessible (track may have been deleted)
                            local ok = pcall(function()
                                return fx:get_name()
                            end)
                            if ok then
                                table.insert(filtered_fx, fx)
                            end
                        end

                        -- Draw the horizontal device chain (includes modulators)
                        draw_device_chain(ctx, filtered_fx, chain_w, avail_h, icon_font_ref)
                    end
                end

                ctx:end_child()
            end
            ctx:pop_style_color()

            reaper_theme:unapply(ctx)

            -- Pop default font if we pushed it
            if default_font_ref.value then
                ctx:pop_font()
            end

            -- Periodically save state (every 60 frames ~= 1 second at 60fps)
            -- Only save if there are actual display names to avoid clearing saved data
            if state.track and (not state.last_save_frame or (ctx.frame_count - state.last_save_frame) > 60) then
                state_module.save_expansion_state()
                -- Only save display names if there are any (don't clear saved data)
                local has_display_names = false
                for _ in pairs(state.display_names) do
                    has_display_names = true
                    break
                end
                if has_display_names then
                    state_module.save_display_names()
                end
                state.last_save_frame = ctx.frame_count
            end
            
            -- Draw modal dialogs (settings, presets, etc.)
            if opts.settings_dialog then
                opts.settings_dialog.draw(ctx)
            end
            if opts.preset_dialog then
                opts.preset_dialog.draw(ctx)
            end
        end,
    }

    return callbacks
end

return M
