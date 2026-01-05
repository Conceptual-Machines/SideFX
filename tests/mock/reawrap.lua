--- Mock ReaWrap classes for SideFX standalone testing.
-- Provides mock implementations of ReaWrap's OOP classes.
-- @module mock.reawrap
-- @author Nomad Monad
-- @license MIT

local M = {}

--------------------------------------------------------------------------------
-- Mock State
--------------------------------------------------------------------------------

local mock_state = {
    tracks = {},
    selected_tracks = {},
    project_name = "Mock Project",
}

--- Reset mock state between tests.
function M.reset()
    mock_state = {
        tracks = {},
        selected_tracks = {},
        project_name = "Mock Project",
    }
end

--- Get mock state for test setup/assertions.
function M.get_state()
    return mock_state
end

--------------------------------------------------------------------------------
-- Mock TrackFX Class
--------------------------------------------------------------------------------

local TrackFX = {}
TrackFX.__index = TrackFX

function TrackFX:new(track, fx_idx, data)
    local obj = {
        track = track,
        pointer = fx_idx,
        _data = data or {},
    }
    setmetatable(obj, self)
    return obj
end

function TrackFX:get_name()
    return self._data.name or "Unknown FX"
end

function TrackFX:get_guid()
    return self._data.guid or ("{mock-" .. tostring(self.pointer) .. "}")
end

function TrackFX:get_enabled()
    return self._data.enabled ~= false
end

function TrackFX:set_enabled(enabled)
    self._data.enabled = enabled
end

function TrackFX:get_num_params()
    return self._data.num_params or 0
end

function TrackFX:get_param_name(idx)
    if self._data.params and self._data.params[idx] then
        return self._data.params[idx].name or ("Param " .. (idx + 1))
    end
    return "Param " .. (idx + 1)
end

function TrackFX:get_param_normalized(idx)
    if self._data.params and self._data.params[idx] then
        return self._data.params[idx].value or 0
    end
    return 0
end

function TrackFX:set_param_normalized(idx, value)
    self._data.params = self._data.params or {}
    self._data.params[idx] = self._data.params[idx] or {}
    self._data.params[idx].value = value
    return true
end

function TrackFX:get_param_from_ident(ident)
    if ident == ":wet" then return 0 end
    if ident == ":bypass" then return 1 end
    if ident == ":delta" then return 2 end
    return -1
end

function TrackFX:get_named_config_param(param_name)
    if self._data.named_params and self._data.named_params[param_name] then
        return self._data.named_params[param_name]
    end
    error("Failed to get named config param: " .. param_name)
end

function TrackFX:set_named_config_param(param_name, value)
    self._data.named_params = self._data.named_params or {}
    self._data.named_params[param_name] = value
    return true
end

function TrackFX:is_container()
    return self._data.is_container == true
end

function TrackFX:get_container_child_count()
    if self._data.children then
        return #self._data.children
    end
    return 0
end

function TrackFX:get_container_children()
    local children = {}
    if self._data.children then
        for i, child_data in ipairs(self._data.children) do
            children[i] = TrackFX:new(self.track, child_data.pointer or (i - 1), child_data)
        end
    end
    return children
end

function TrackFX:iter_container_children()
    local children = self:get_container_children()
    local i = 0
    return function()
        i = i + 1
        return children[i]
    end
end

function TrackFX:get_parent_container()
    if self._data.parent then
        return TrackFX:new(self.track, self._data.parent.pointer or 0, self._data.parent)
    end
    return nil
end

function TrackFX:get_container_channels()
    return self._data.container_channels or 2
end

function TrackFX:set_container_channels(channels)
    self._data.container_channels = channels
    return true
end

function TrackFX:set_pin_mappings(is_output, pin, low32, high32)
    return true
end

function TrackFX:add_fx_to_container(fx, position)
    self._data.children = self._data.children or {}
    
    -- Remove from track level if present
    if self.track._data.fx_chain then
        for i, fx_data in ipairs(self.track._data.fx_chain) do
            if fx_data == fx._data then
                table.remove(self.track._data.fx_chain, i)
                break
            end
        end
    end
    
    -- Remove from old parent if present
    if fx._data.parent then
        local old_parent_children = fx._data.parent.children or {}
        for i, child in ipairs(old_parent_children) do
            if child == fx._data then
                table.remove(old_parent_children, i)
                break
            end
        end
    end
    
    -- Set new parent
    fx._data.parent = self._data
    
    -- Insert at position or append
    if position and position >= 0 and position <= #self._data.children then
        table.insert(self._data.children, position + 1, fx._data)
    else
        table.insert(self._data.children, fx._data)
    end
    
    return true
end

function TrackFX:move_to_container(container, position)
    return container:add_fx_to_container(self, position)
end

function TrackFX:move_out_of_container(position)
    -- Remove from parent's children list
    if self._data.parent then
        local parent_children = self._data.parent.children or {}
        for i, child in ipairs(parent_children) do
            if child == self._data then
                table.remove(parent_children, i)
                break
            end
        end
        -- Add to track level
        if not self.track._data.fx_chain then
            self.track._data.fx_chain = {}
        end
        table.insert(self.track._data.fx_chain, self._data)
        -- Clear parent reference
        self._data.parent = nil
        return true
    end
    return true
end

function TrackFX:delete()
    return true
end

function TrackFX:show(flag)
    return true
end

M.TrackFX = TrackFX

--------------------------------------------------------------------------------
-- Mock Track Class
--------------------------------------------------------------------------------

local Track = {}
Track.__index = Track

function Track:new(data)
    local obj = {
        pointer = data and data.pointer or 0,
        _data = data or {},
    }
    setmetatable(obj, self)
    return obj
end

function Track:get_name()
    return self._data.name or "Track"
end

function Track:get_track_fx_count()
    if self._data.fx_chain then
        return #self._data.fx_chain
    end
    return 0
end

function Track:get_track_fx(idx)
    if self._data.fx_chain and self._data.fx_chain[idx + 1] then
        return TrackFX:new(self, idx, self._data.fx_chain[idx + 1])
    end
    return nil
end

function Track:iter_track_fx_chain()
    local i = -1
    local count = self:get_track_fx_count()
    return function()
        i = i + 1
        if i < count then
            return self:get_track_fx(i)
        end
    end
end

function Track:find_fx_by_guid(guid)
    -- Recursive search helper
    local function search_recursive(fx_data, depth)
        if depth > 50 then return nil end  -- Prevent infinite recursion
        
        if fx_data.guid == guid then
            return fx_data
        end
        
        -- Search in children
        if fx_data.children then
            for _, child_data in ipairs(fx_data.children) do
                local found = search_recursive(child_data, depth + 1)
                if found then return found end
            end
        end
        
        return nil
    end
    
    -- Search in track-level FX chain
    if self._data.fx_chain then
        for idx, fx_data in ipairs(self._data.fx_chain) do
            local found = search_recursive(fx_data, 0)
            if found then
                -- Calculate approximate pointer based on depth and position
                local pointer = idx - 1
                if found ~= fx_data then
                    -- It's nested, use a unique pointer
                    pointer = (idx - 1) * 1000 + (found._nested_index or 0)
                end
                return TrackFX:new(self, pointer, found)
            end
        end
    end
    
    return nil
end

function Track:add_fx_by_name(name, rec_fx, position)
    self._data.fx_chain = self._data.fx_chain or {}
    local idx = #self._data.fx_chain
    local fx_data = {
        name = name,
        guid = "{mock-" .. idx .. "-" .. os.time() .. "}",
        enabled = true,
        is_container = name == "Container",
    }
    table.insert(self._data.fx_chain, fx_data)
    return TrackFX:new(self, idx, fx_data)
end

function Track:add_fx_to_new_container(fx_list)
    local container = self:add_fx_by_name("Container", false, -1)
    for _, fx in ipairs(fx_list) do
        container:add_fx_to_container(fx)
    end
    return container
end

function Track:iter_all_fx_flat()
    local result = {}
    
    local function add_fx(fx_data, depth, pointer)
        local fx = TrackFX:new(self, pointer, fx_data)
        table.insert(result, { fx = fx, depth = depth })
        
        if fx_data.children then
            for i, child_data in ipairs(fx_data.children) do
                add_fx(child_data, depth + 1, child_data.pointer or (pointer * 100 + i))
            end
        end
    end
    
    if self._data.fx_chain then
        for idx, fx_data in ipairs(self._data.fx_chain) do
            add_fx(fx_data, 0, idx - 1)
        end
    end
    
    local i = 0
    return function()
        i = i + 1
        return result[i]
    end
end

M.Track = Track

--------------------------------------------------------------------------------
-- Mock Project Class
--------------------------------------------------------------------------------

local Project = {}
Project.__index = Project

function Project:new()
    local obj = {}
    setmetatable(obj, self)
    return obj
end

function Project:get_name()
    return mock_state.project_name
end

function Project:get_track_count()
    return #mock_state.tracks
end

function Project:get_track(idx)
    if mock_state.tracks[idx + 1] then
        return Track:new(mock_state.tracks[idx + 1])
    end
    return nil
end

function Project:iter_tracks()
    local i = -1
    return function()
        i = i + 1
        return self:get_track(i)
    end
end

function Project:has_selected_tracks()
    return #mock_state.selected_tracks > 0
end

function Project:get_selected_track(idx)
    if mock_state.selected_tracks[idx + 1] then
        return Track:new(mock_state.selected_tracks[idx + 1])
    end
    return nil
end

function Project:iter_selected_tracks()
    local i = -1
    return function()
        i = i + 1
        if mock_state.selected_tracks[i + 1] then
            return Track:new(mock_state.selected_tracks[i + 1])
        end
    end
end

M.Project = Project

--------------------------------------------------------------------------------
-- Mock Helpers
--------------------------------------------------------------------------------

local helpers = {}

function helpers.iter(tbl)
    local i = 0
    return function()
        i = i + 1
        return tbl[i]
    end
end

M.helpers = helpers

--------------------------------------------------------------------------------
-- Mock Setup Helpers
--------------------------------------------------------------------------------

--- Add a mock track to the project.
-- @param data table Track data {name, fx_chain = {...}}
-- @return Track Mock track object
function M.add_track(data)
    data = data or {}
    data.pointer = #mock_state.tracks
    table.insert(mock_state.tracks, data)
    return Track:new(data)
end

--- Set selected tracks.
-- @param tracks table Array of track data
function M.set_selected_tracks(tracks)
    mock_state.selected_tracks = tracks or {}
end

return M

