--- Preset Dialog UI Component
-- Modal dialog for saving/loading chain presets
-- @module ui.presets.preset_dialog
-- @author Nomad Monad
-- @license MIT

local r = reaper
local imgui = require('imgui')
local state_mod = require('lib.core.state')
local presets_mod = require('lib.utils.presets')

local M = {}

-- Dialog state
local dialog_state = {
    open = false,
    mode = "save",  -- "save" or "load"
    preset_name = "",
    preset_list = {},
    selected_preset = nil,
    popup_opened = false,  -- Track if popup has been opened this frame
}

--------------------------------------------------------------------------------
-- Preset Management
--------------------------------------------------------------------------------

--- Scan for available presets
local function scan_presets()
    dialog_state.preset_list = {}
    local folder = presets_mod.get_folder()
    if not folder then return end
    
    local chains_folder = folder .. "chains/"
    local i = 0
    while true do
        local file = r.EnumerateFiles(chains_folder, i)
        if not file then break end
        if file:match("%.RfxChain$") then
            local name = file:gsub("%.RfxChain$", "")
            table.insert(dialog_state.preset_list, name)
        end
        i = i + 1
    end
    table.sort(dialog_state.preset_list)
end

--------------------------------------------------------------------------------
-- Dialog Rendering
--------------------------------------------------------------------------------

--- Draw the preset dialog
-- @param ctx ImGui context wrapper
function M.draw(ctx)
    if not dialog_state.open then
        return
    end

    -- Open the popup on first frame (only once)
    if not dialog_state.popup_opened then
        r.ImGui_OpenPopup(ctx.ctx, "Presets##sidefx_presets")
        dialog_state.popup_opened = true
    end

    local flags = r.ImGui_WindowFlags_AlwaysAutoResize() | r.ImGui_WindowFlags_NoCollapse()
    local visible, p_open = r.ImGui_BeginPopupModal(ctx.ctx, "Presets##sidefx_presets", true, flags)
    
    if not visible then
        if not p_open then
            dialog_state.open = false
        end
        return
    end

    -- Mode selection (Save/Load)
    if ctx:radio_button("Save", dialog_state.mode == "save") then
        dialog_state.mode = "save"
        dialog_state.selected_preset = nil
    end
    ctx:same_line()
    if ctx:radio_button("Load", dialog_state.mode == "load") then
        dialog_state.mode = "load"
        scan_presets()
    end
    
    ctx:spacing()
    ctx:separator()
    
    if dialog_state.mode == "save" then
        -- Save mode
        ctx:text("Preset Name:")
        ctx:same_line()
        local changed, text = ctx:input_text("##preset_name", dialog_state.preset_name, 256)
        if changed then
            dialog_state.preset_name = text
        end
        
        ctx:spacing()
        
        local state = state_mod.state
        if not state.track then
            ctx:text_disabled("No track selected")
        else
            local avail_w = ctx:get_content_region_avail_width()
            local btn_w = 100
            local btn_x = (avail_w - btn_w) / 2
            if btn_x > 0 then
                ctx:dummy(btn_x, 0)
                ctx:same_line()
            end
            
            if ctx:button("Save Preset", btn_w, 0) then
                if dialog_state.preset_name and dialog_state.preset_name ~= "" then
                    local success = presets_mod.save_chain(dialog_state.preset_name)
                    if success then
                        r.ShowMessageBox("Preset saved successfully.", "SideFX", 0)
                        dialog_state.open = false
                        dialog_state.popup_opened = false
                        r.ImGui_CloseCurrentPopup(ctx.ctx)
                    else
                        r.ShowMessageBox("Failed to save preset.", "SideFX", 0)
                    end
                else
                    r.ShowMessageBox("Please enter a preset name.", "SideFX", 0)
                end
            end
        end
    else
        -- Load mode
        ctx:text("Available Presets:")
        
        if #dialog_state.preset_list == 0 then
            ctx:text_disabled("No presets found")
        else
            -- Preset list (using child window with selectables)
            local list_height = math.min(200, #dialog_state.preset_list * 25)
            ctx:begin_child("##preset_list", 0, list_height, 0)
            for i, name in ipairs(dialog_state.preset_list) do
                local selected = (dialog_state.selected_preset == name)
                if ctx:selectable(name .. "##preset_" .. i, selected) then
                    dialog_state.selected_preset = name
                end
            end
            ctx:end_child()
            
            ctx:spacing()
            
            local avail_w = ctx:get_content_region_avail_width()
            local btn_w = 100
            local btn_x = (avail_w - btn_w) / 2
            if btn_x > 0 then
                ctx:dummy(btn_x, 0)
                ctx:same_line()
            end
            
            if ctx:button("Load Preset", btn_w, 0) then
                if dialog_state.selected_preset then
                    local success = presets_mod.load_chain(dialog_state.selected_preset)
                    if success then
                        r.ShowMessageBox("Preset loaded successfully.", "SideFX", 0)
                        dialog_state.open = false
                        dialog_state.popup_opened = false
                        r.ImGui_CloseCurrentPopup(ctx.ctx)
                    else
                        r.ShowMessageBox("Failed to load preset.", "SideFX", 0)
                    end
                else
                    r.ShowMessageBox("Please select a preset.", "SideFX", 0)
                end
            end
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

--- Open the preset dialog
-- @param ctx ImGui context wrapper
function M.open(ctx)
    dialog_state.open = true
    dialog_state.mode = "save"
    dialog_state.preset_name = ""
    dialog_state.selected_preset = nil
    dialog_state.popup_opened = false  -- Reset so popup opens on next draw
end

--- Check if dialog is open
-- @return boolean
function M.is_open()
    return dialog_state.open
end

return M
