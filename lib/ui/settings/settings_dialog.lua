--- Settings Dialog UI Component
-- Modal dialog for SideFX user preferences
-- @module ui.settings.settings_dialog
-- @author Nomad Monad
-- @license MIT

local r = reaper
local state_mod = require('lib.core.state')
local config = require('lib.core.config')

local M = {}

-- Dialog state
local dialog_state = {
    open = false,
    popup_opened = false,  -- Track if popup has been opened this frame
}

--------------------------------------------------------------------------------
-- Dialog Rendering
--------------------------------------------------------------------------------

--- Draw the settings dialog
-- @param ctx ImGui context wrapper
function M.draw(ctx)
    if not dialog_state.open then
        return
    end

    -- Open the popup on first frame (only once)
    if not dialog_state.popup_opened then
        r.ImGui_OpenPopup(ctx.ctx, "Settings##sidefx_settings")
        dialog_state.popup_opened = true
    end

    local flags = r.ImGui_WindowFlags_AlwaysAutoResize() | r.ImGui_WindowFlags_NoCollapse()
    local visible, p_open = r.ImGui_BeginPopupModal(ctx.ctx, "Settings##sidefx_settings", true, flags)

    if not visible then
        if not p_open then
            dialog_state.open = false
            dialog_state.popup_opened = false
        end
        return
    end

    -- Display Section
    ctx:text("Display")
    ctx:separator()

    -- Show/Hide Track Name
    local show_track_name = config.get('show_track_name')
    if ctx:checkbox("Show Track Name", show_track_name) then
        config.set('show_track_name', not show_track_name)
        state_mod.load_config()  -- Sync to state
    end

    -- Show/Hide Breadcrumbs
    local show_breadcrumbs = config.get('show_breadcrumbs')
    if ctx:checkbox("Show Breadcrumbs", show_breadcrumbs) then
        config.set('show_breadcrumbs', not show_breadcrumbs)
        state_mod.load_config()
    end

    -- Icon Font Size
    ctx:text("Icon Font Size:")
    ctx:same_line()
    local icon_size = config.get('icon_font_size')
    if ctx:radio_button("Small##icon_size", icon_size == 0) then
        config.set('icon_font_size', 0)
        state_mod.load_config()
    end
    ctx:same_line()
    if ctx:radio_button("Medium##icon_size", icon_size == 1) then
        config.set('icon_font_size', 1)
        state_mod.load_config()
    end
    ctx:same_line()
    if ctx:radio_button("Large##icon_size", icon_size == 2) then
        config.set('icon_font_size', 2)
        state_mod.load_config()
    end

    ctx:spacing()

    -- Behavior Section
    ctx:text("Behavior")
    ctx:separator()

    -- Auto-refresh on track change
    local auto_refresh = config.get('auto_refresh')
    if ctx:checkbox("Auto-refresh on Track Change", auto_refresh) then
        config.set('auto_refresh', not auto_refresh)
        state_mod.load_config()
    end

    -- Remember window position
    local remember_pos = config.get('remember_window_pos')
    if ctx:checkbox("Remember Window Position", remember_pos) then
        config.set('remember_window_pos', not remember_pos)
        state_mod.load_config()
    end

    ctx:spacing()

    -- Gain Staging Section
    ctx:text("Gain Staging")
    ctx:separator()

    -- Default target level
    local target_db = config.get('gain_target_db')
    ctx:text(string.format("Default Target Level: %.1f dB", target_db))
    local changed, new_target = ctx:slider_double("##gain_target", target_db, -24.0, 0.0, "%.1f dB")
    if changed then
        config.set('gain_target_db', new_target)
        state_mod.load_config()
    end

    -- Tolerance
    local tolerance_db = config.get('gain_tolerance_db')
    ctx:text(string.format("Tolerance: %.1f dB", tolerance_db))
    local changed_tol, new_tol = ctx:slider_double("##gain_tolerance", tolerance_db, 0.5, 3.0, "%.1f dB")
    if changed_tol then
        config.set('gain_tolerance_db', new_tol)
        state_mod.load_config()
    end

    ctx:spacing()

    -- Paths Section
    ctx:text("Paths")
    ctx:separator()

    -- Presets folder
    local presets_folder = config.get_presets_folder()
    local is_custom = config.has_custom_presets_folder()

    ctx:text("Presets Folder:")

    -- Show current path (truncated if too long)
    local display_path = presets_folder
    if #display_path > 50 then
        display_path = "..." .. display_path:sub(-47)
    end
    r.ImGui_PushStyleColor(ctx.ctx, r.ImGui_Col_Text(), 0x888888FF)
    ctx:text(display_path)
    r.ImGui_PopStyleColor(ctx.ctx)

    -- Browse button
    if ctx:button("Browse...##presets_folder", 80, 0) then
        local retval, folder = r.JS_Dialog_BrowseForFolder("Select Presets Folder", presets_folder)
        if retval == 1 and folder and folder ~= "" then
            config.set('presets_folder', folder)
        end
    end

    ctx:same_line()

    -- Reset to default button (only show if custom path is set)
    if is_custom then
        if ctx:button("Reset##presets_folder", 50, 0) then
            config.reset('presets_folder')
        end
    end

    ctx:spacing()
    ctx:separator()

    -- Close button
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

    -- Close dialog if window was closed
    if not p_open then
        dialog_state.open = false
        dialog_state.popup_opened = false
    end

    r.ImGui_EndPopup(ctx.ctx)
end

--------------------------------------------------------------------------------
-- Dialog Control
--------------------------------------------------------------------------------

--- Open the settings dialog
-- @param ctx ImGui context wrapper
function M.open(ctx)
    dialog_state.open = true
    dialog_state.popup_opened = false  -- Reset so popup opens on next draw
end

--- Check if dialog is open
-- @return boolean
function M.is_open()
    return dialog_state.open
end

return M
