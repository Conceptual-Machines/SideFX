--[[
Parameter Selector Dialog - Allows users to select which parameters to display
for a plugin before adding it to the track.
--]]

local r = reaper
local imgui = require('imgui')

local M = {}

-- Dialog state (per plugin)
local dialog_state = {
    open = false,
    plugin_name = nil,
    plugin_full_name = nil,
    all_params = {},  -- {idx, name, formatted}
    selected = {},  -- {[param_idx] = true}
    search_text = "",
    popup_opened = false,  -- Track if popup has been opened
}

--------------------------------------------------------------------------------
-- Parameter Scanning
--------------------------------------------------------------------------------

--- Scan parameters from a plugin by creating a temporary FX instance
-- @param plugin_full_name string Full plugin name
-- @return table Array of {idx, name, formatted} parameter info
local function scan_plugin_params(plugin_full_name)
    local params = {}
    
    -- Prevent UI updates during track creation/deletion
    r.PreventUIRefresh(1)
    
    -- Create a temporary track to scan the plugin
    r.InsertTrackAtIndex(0, false)
    local temp_track = r.GetTrack(0, 0)
    if not temp_track then
        r.PreventUIRefresh(-1)
        return params
    end
    
    -- Hide the track immediately (user should never see it)
    r.SetMediaTrackInfo_Value(temp_track, "B_SHOWINMIXER", 0)
    r.SetMediaTrackInfo_Value(temp_track, "B_SHOWINTCP", 0)
    
    local fx = r.TrackFX_AddByName(temp_track, plugin_full_name, false, -1)
    if fx < 0 then
        r.DeleteTrack(temp_track)
        r.PreventUIRefresh(-1)
        return params
    end
    
    -- Scan parameters
    local param_count = r.TrackFX_GetNumParams(temp_track, fx)
    for i = 0, param_count - 1 do
        local ok_name, ret_val, name = pcall(function()
            return r.TrackFX_GetParamName(temp_track, fx, i)
        end)
        local ok_val, val = pcall(function()
            return r.TrackFX_GetParamNormalized(temp_track, fx, i)
        end)
        local ok_fmt, ret_fmt, formatted = pcall(function()
            return r.TrackFX_GetFormattedParamValue(temp_track, fx, i)
        end)
        
        if ok_name and ret_val and name then
            local lower = name:lower()
            -- Skip sidebar controls
            if lower ~= "wet" and lower ~= "delta" and lower ~= "bypass" then
                table.insert(params, {
                    idx = i,
                    name = name,
                    formatted = (ok_fmt and ret_fmt and formatted) or "",
                })
            end
        end
    end
    
    -- Clean up - delete track immediately
    r.DeleteTrack(temp_track)
    r.PreventUIRefresh(-1)
    
    return params
end

--------------------------------------------------------------------------------
-- Dialog Rendering
--------------------------------------------------------------------------------

--- Draw the parameter selector dialog
-- @param ctx ImGui context
-- @param state table Global state object
-- @return boolean True if dialog should remain open
function M.draw(ctx, state)
    if not dialog_state.open then
        return false
    end
    
    local r = reaper
    local imgui = require('imgui')
    
    -- Open the popup on first frame (only once)
    if dialog_state.open and #dialog_state.all_params > 0 and not dialog_state.popup_opened then
        r.ImGui_OpenPopup(ctx.ctx, "Select Parameters##param_selector")
        dialog_state.popup_opened = true
    end
    
    -- Dialog flags
    local flags = r.ImGui_WindowFlags_AlwaysAutoResize() | r.ImGui_WindowFlags_NoCollapse()
    
    -- Open dialog as a modal popup
    -- In Lua, BeginPopupModal returns (retval, p_open) where p_open is a boolean
    local visible, p_open = r.ImGui_BeginPopupModal(ctx.ctx, "Select Parameters##param_selector", true, flags)
    if visible then
        -- Header
        ctx:text("Plugin: " .. (dialog_state.plugin_name or "Unknown"))
        ctx:separator()
        
        -- Search box
        ctx:set_next_item_width(300)
        local changed, search = ctx:input_text("##search", dialog_state.search_text)
        if changed then
            dialog_state.search_text = search
        end
        if ctx:is_item_hovered() then
            ctx:set_tooltip("Search parameters...")
        end
        
        ctx:spacing()
        
        -- Parameter list in a scrollable child
        if ctx:begin_child("ParamList", 0, 300, imgui.ChildFlags.Border()) then
            local filtered_params = {}
            local search_lower = dialog_state.search_text:lower()
            
            -- Filter parameters
            for _, param in ipairs(dialog_state.all_params) do
                if search_lower == "" or param.name:lower():find(search_lower, 1, true) then
                    table.insert(filtered_params, param)
                end
            end
            
            -- Select all / Deselect all buttons
            ctx:same_line()
            if ctx:small_button("Select All") then
                local state_mod = require('lib.core.state')
                local max_params = state_mod.get_max_visible_params()
                local count = 0
                for _, param in ipairs(filtered_params) do
                    if count < max_params then
                        dialog_state.selected[param.idx] = true
                        count = count + 1
                    end
                end
                if #filtered_params > max_params then
                    r.ShowConsoleMsg(string.format("SideFX: Limited selection to %d parameters (maximum allowed).\n", max_params))
                end
            end
            ctx:same_line()
            if ctx:small_button("Deselect All") then
                for _, param in ipairs(filtered_params) do
                    dialog_state.selected[param.idx] = nil
                end
            end
            
            -- Show selection count and limit
            ctx:same_line()
            local state_mod = require('lib.core.state')
            local max_params = state_mod.get_max_visible_params()
            local selected_count = 0
            for _ in pairs(dialog_state.selected) do
                selected_count = selected_count + 1
            end
            local count_text = string.format("%d / %d selected", selected_count, max_params)
            if selected_count > max_params then
                ctx:push_style_color(imgui.Col.Text(), 0xFF0000FF)  -- Red
                count_text = count_text .. " (OVER LIMIT)"
            elseif selected_count == max_params then
                ctx:push_style_color(imgui.Col.Text(), 0xFFFF00FF)  -- Yellow
            else
                ctx:push_style_color(imgui.Col.Text(), 0x888888FF)  -- Gray
            end
            ctx:text(count_text)
            ctx:pop_style_color()
            
            ctx:spacing()
            ctx:separator()
            ctx:spacing()
            
            -- Parameter checkboxes
            
            -- Count current selections before rendering
            local function count_selections()
                local count = 0
                for _ in pairs(dialog_state.selected) do
                    count = count + 1
                end
                return count
            end
            
            for _, param in ipairs(filtered_params) do
                local is_selected = dialog_state.selected[param.idx] == true
                local changed, new_val = ctx:checkbox(param.name .. "##" .. param.idx, is_selected)
                if changed then
                    if new_val then
                        -- Check if we're at the limit
                        local current_count = count_selections()
                        if current_count >= max_params then
                            -- Don't allow selection if at limit
                            r.ShowConsoleMsg(string.format("SideFX: Maximum of %d parameters allowed. Deselect some first.\n", max_params))
                        else
                            dialog_state.selected[param.idx] = true
                        end
                    else
                        dialog_state.selected[param.idx] = nil
                    end
                end
            end
            
            ctx:end_child()
        end
        
        ctx:spacing()
        ctx:separator()
        
        -- Buttons
        local button_width = 100
        local avail_w = ctx:get_content_region_avail_width()
        r.ImGui_SetCursorPosX(ctx.ctx, r.ImGui_GetCursorPosX(ctx.ctx) + avail_w - button_width * 2 - 20)
        
        if ctx:button("Cancel", button_width, 0) then
            dialog_state.open = false
            dialog_state.plugin_name = nil
            dialog_state.plugin_full_name = nil
            dialog_state.all_params = {}
            dialog_state.selected = {}
            dialog_state.search_text = ""
            dialog_state.popup_opened = false
        end
        
        ctx:same_line()
        
        if ctx:button("OK", button_width, 0) then
            -- Save selections to state (enforce max limit)
            if dialog_state.plugin_full_name then
                local selected_list = {}
                for idx in pairs(dialog_state.selected) do
                    table.insert(selected_list, idx)
                end
                table.sort(selected_list)
                
                -- Enforce maximum parameter limit
                local state_mod = require('lib.core.state')
                local max_params = state_mod.get_max_visible_params()
                if #selected_list > max_params then
                    -- Truncate to max
                    local truncated = {}
                    for i = 1, max_params do
                        table.insert(truncated, selected_list[i])
                    end
                    selected_list = truncated
                    -- Show notification (optional - could use a message box)
                    r.ShowConsoleMsg(string.format("SideFX: Limited to %d parameters (maximum allowed).\n", max_params))
                end
                
                -- Store in state (keyed by plugin full name)
                if not state.param_selections then
                    state.param_selections = {}
                end
                state.param_selections[dialog_state.plugin_full_name] = selected_list

                -- Persist to ExtState
                local state_mod = require('lib.core.state')
                state_mod.save_param_selections()
            end

            -- Close dialog
            dialog_state.open = false
            dialog_state.plugin_name = nil
            dialog_state.plugin_full_name = nil
            dialog_state.all_params = {}
            dialog_state.selected = {}
            dialog_state.search_text = ""
            dialog_state.popup_opened = false
        end
        
        r.ImGui_EndPopup(ctx.ctx)
    end
    
    -- Close dialog if window was closed
    if not p_open then
        dialog_state.open = false
        dialog_state.plugin_name = nil
        dialog_state.plugin_full_name = nil
        dialog_state.all_params = {}
        dialog_state.selected = {}
        dialog_state.search_text = ""
        dialog_state.popup_opened = false
    end
    
    return dialog_state.open
end

--------------------------------------------------------------------------------
-- Dialog Control
--------------------------------------------------------------------------------

--- Open the parameter selector for a plugin
-- @param plugin_name string Plugin display name
-- @param plugin_full_name string Full plugin name (for storage key)
function M.open(plugin_name, plugin_full_name)
    dialog_state.open = true
    dialog_state.plugin_name = plugin_name
    dialog_state.plugin_full_name = plugin_full_name
    dialog_state.search_text = ""
    dialog_state.popup_opened = false
    
    -- Scan parameters
    dialog_state.all_params = scan_plugin_params(plugin_full_name)
    
    -- Initialize selections: check if we have saved selections, otherwise default to first 32
    local r = reaper
    local state_mod = require('lib.core.state')
    local state = state_mod.state
    
    dialog_state.selected = {}
    
    if state.param_selections and state.param_selections[plugin_full_name] then
        -- Use saved selections
        for _, idx in ipairs(state.param_selections[plugin_full_name]) do
            dialog_state.selected[idx] = true
        end
    else
        -- Default: first 32 parameters
        for i = 1, math.min(32, #dialog_state.all_params) do
            local param = dialog_state.all_params[i]
            if param then
                dialog_state.selected[param.idx] = true
            end
        end
    end
end

--- Check if dialog is open
-- @return boolean
function M.is_open()
    return dialog_state.open
end

return M
