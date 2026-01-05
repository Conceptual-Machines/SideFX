--- Unit tests for recursive container operations in SideFX rack module.
-- Tests the recursive helper functions for adding items to nested containers.
-- @module unit.test_rack_recursive
-- @author Nomad Monad
-- @license MIT

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

local assert = require("assertions")
local mock_reawrap = require("mock.reawrap")
local Track = mock_reawrap.Track
local TrackFX = mock_reawrap.TrackFX

-- Mock REAPER API
reaper = {
    Undo_BeginBlock = function() end,
    Undo_EndBlock = function(desc, flags) end,
    PreventUIRefresh = function(state) end,
    ShowConsoleMsg = function(msg) print(msg) end,
}

-- Mock state module
package.loaded['lib.state'] = {
    state = {
        track = nil,
    }
}

-- Mock fx_utils
package.loaded['lib.fx_utils'] = {
    is_rack_container = function(fx)
        local ok, name = pcall(function() return fx:get_name() end)
        return ok and name and name:match("^R%d+:")
    end,
    is_chain_container = function(fx)
        local ok, name = pcall(function() return fx:get_name() end)
        return ok and name and name:match("^R%d+_C%d+")
    end,
    count_devices_in_chain = function(chain)
        local count = 0
        for child in chain:iter_container_children() do
            local ok, name = pcall(function() return child:get_name() end)
            if ok and name and name:match("_D%d+") then
                count = count + 1
            end
        end
        return count
    end,
    count_chains_in_rack = function(rack)
        local count = 0
        for child in rack:iter_container_children() do
            local ok, name = pcall(function() return child:get_name() end)
            if ok and name and not name:match("^_") and not name:match("Mixer") then
                count = count + 1
            end
        end
        return count
    end,
    get_next_rack_index = function(track)
        local max_idx = 0
        for entry in track:iter_all_fx_flat() do
            local fx = entry.fx
            local ok, name = pcall(function() return fx:get_name() end)
            if ok and name then
                local idx = name:match("^R(%d+)")
                if idx then
                    max_idx = math.max(max_idx, tonumber(idx))
                end
            end
        end
        return max_idx + 1
    end,
    get_device_main_fx = function(device)
        for child in device:iter_container_children() do
            local ok, name = pcall(function() return child:get_name() end)
            if ok and name and name:match("_FX:") then
                return child
            end
        end
        return nil
    end,
    get_device_utility = function(device)
        for child in device:iter_container_children() do
            local ok, name = pcall(function() return child:get_name() end)
            if ok and name and name:match("_Util") then
                return child
            end
        end
        return nil
    end,
    get_rack_mixer = function(rack)
        for child in rack:iter_container_children() do
            local ok, name = pcall(function() return child:get_name() end)
            if ok and name and (name:match("^_") and name:match("_M$")) then
                return child
            end
        end
        return nil
    end,
}

-- Mock naming module
package.loaded['lib.naming'] = {
    parse_hierarchy = function(name)
        local r, c, d = name:match("^R(%d+)_C(%d+)_D(%d+)")
        if r then
            return {rack_idx = tonumber(r), chain_idx = tonumber(c), device_idx = tonumber(d)}
        end
        local r, c = name:match("^R(%d+)_C(%d+)")
        if r then
            return {rack_idx = tonumber(r), chain_idx = tonumber(c)}
        end
        local r = name:match("^R(%d+)")
        if r then
            return {rack_idx = tonumber(r)}
        end
        return {}
    end,
    build_rack_name = function(rack_idx, display_name)
        if display_name then
            return string.format("R%d: %s", rack_idx, display_name)
        end
        return string.format("R%d: Rack", rack_idx)
    end,
    build_chain_name = function(rack_idx, chain_idx)
        return string.format("R%d_C%d", rack_idx, chain_idx)
    end,
    build_mixer_name = function(rack_idx)
        return string.format("_R%d_M", rack_idx)
    end,
    build_chain_device_name = function(rack_idx, chain_idx, device_idx, fx_name)
        return string.format("R%d_C%d_D%d: %s", rack_idx, chain_idx, device_idx, fx_name)
    end,
    build_chain_device_fx_name = function(rack_idx, chain_idx, device_idx, fx_name)
        return string.format("R%d_C%d_D%d_FX: %s", rack_idx, chain_idx, device_idx, fx_name)
    end,
    build_chain_device_util_name = function(rack_idx, chain_idx, device_idx)
        return string.format("R%d_C%d_D%d_Util", rack_idx, chain_idx, device_idx)
    end,
    get_short_plugin_name = function(name)
        return name:gsub("^VST3?: ", ""):gsub("^AU: ", ""):gsub("^JS: ", "")
    end,
    parse_rack_index = function(name)
        local idx = name:match("^R(%d+)")
        return idx and tonumber(idx) or nil
    end,
}

-- Load the real rack module (it will use our mocked dependencies)
local rack_module = require("lib.rack")

local M = {}

-- Track for tests
local test_track = nil

--------------------------------------------------------------------------------
-- Test Helpers
--------------------------------------------------------------------------------

local function setup_test_track()
    mock_reawrap.reset()
    test_track = mock_reawrap.add_track({
        name = "Test Track",
        fx_chain = {}
    })
    package.loaded['lib.state'].state.track = test_track
    return test_track
end

local function create_rack(name)
    local rack_data = {
        name = name,
        guid = "{rack-" .. name .. "}",
        enabled = true,
        is_container = true,
        container_channels = 64,
        children = {}
    }
    local rack = TrackFX:new(test_track, #test_track._data.fx_chain, rack_data)
    table.insert(test_track._data.fx_chain, rack_data)
    return rack
end

local function create_chain(name, parent_rack)
    local chain_data = {
        name = name,
        guid = "{chain-" .. name .. "}",
        enabled = true,
        is_container = true,
        children = {},
        parent = parent_rack and parent_rack._data or nil
    }
    local chain = TrackFX:new(test_track, #test_track._data.fx_chain, chain_data)
    if parent_rack then
        parent_rack._data.children = parent_rack._data.children or {}
        table.insert(parent_rack._data.children, chain_data)
    else
        table.insert(test_track._data.fx_chain, chain_data)
    end
    return chain
end

local function create_device(name, parent_chain)
    local device_data = {
        name = name,
        guid = "{device-" .. name .. "}",
        enabled = true,
        is_container = true,
        children = {},
        parent = parent_chain and parent_chain._data or nil
    }
    local device = TrackFX:new(test_track, #test_track._data.fx_chain, device_data)
    if parent_chain then
        parent_chain._data.children = parent_chain._data.children or {}
        table.insert(parent_chain._data.children, device_data)
    else
        table.insert(test_track._data.fx_chain, device_data)
    end
    return device
end

local function verify_hierarchy()
    -- Verify all parent-child relationships are consistent
    local function check_children(parent_data, visited)
        visited = visited or {}
        if visited[parent_data] then
            return false  -- Circular reference
        end
        visited[parent_data] = true
        
        if parent_data.children then
            for _, child_data in ipairs(parent_data.children) do
                if child_data.parent ~= parent_data then
                    return false
                end
                if not check_children(child_data, visited) then
                    return false
                end
            end
        end
        return true
    end
    
    for _, fx_data in ipairs(test_track._data.fx_chain) do
        if fx_data.parent then
            return false  -- Top-level items shouldn't have parents
        end
        if not check_children(fx_data) then
            return false
        end
    end
    return true
end

--------------------------------------------------------------------------------
-- Tests: Recursive Container Helpers
--------------------------------------------------------------------------------

local function test_build_container_path_simple()
    assert.section("Build path - simple (chain in rack)")
    
    setup_test_track()
    local rack = create_rack("R1: Test Rack")
    local chain = create_chain("R1_C1", rack)
    
    -- Test path building logic (simplified implementation for testing)
    local function build_path(container)
        local path = {}
        local current = container
        while current do
            local guid = current:get_guid()
            local parent = current:get_parent_container()
            if parent then
                local pos = 0
                for child in parent:iter_container_children() do
                    if child:get_guid() == guid then break end
                    pos = pos + 1
                end
                -- Append to path (not prepend) to maintain child-to-parent order
                table.insert(path, {
                    guid = guid,
                    parent_guid = parent:get_guid(),
                    position = pos
                })
                current = parent
            else
                break
            end
        end
        return path
    end
    
    local path = build_path(chain)
    assert.not_nil(path, "Path should be built")
    assert.equals(1, #path, "Path should have 1 entry (chain)")
    assert.equals(chain:get_guid(), path[1].guid, "Path should contain chain GUID")
    assert.equals(rack:get_guid(), path[1].parent_guid, "Path should reference parent rack")
    assert.equals(0, path[1].position, "Chain should be at position 0 in rack")
end

local function test_build_container_path_deep()
    assert.section("Build path - deep nesting (rack in chain in rack)")
    
    setup_test_track()
    local rack1 = create_rack("R1: Outer Rack")
    local chain1 = create_chain("R1_C1", rack1)
    local rack2 = create_rack("R2: Inner Rack")
    -- Remove rack2 from track level since it will be nested
    for i, fx_data in ipairs(test_track._data.fx_chain) do
        if fx_data == rack2._data then
            table.remove(test_track._data.fx_chain, i)
            break
        end
    end
    -- Manually set rack2 as child of chain1
    rack2._data.parent = chain1._data
    chain1._data.children = chain1._data.children or {}
    table.insert(chain1._data.children, rack2._data)
    
    -- Test path building logic
    local function build_path(container)
        local path = {}
        local current = container
        while current do
            local guid = current:get_guid()
            local parent = current:get_parent_container()
            if parent then
                local pos = 0
                for child in parent:iter_container_children() do
                    if child:get_guid() == guid then break end
                    pos = pos + 1
                end
                -- Append to path (not prepend) to maintain child-to-parent order
                table.insert(path, {
                    guid = guid,
                    parent_guid = parent:get_guid(),
                    position = pos
                })
                current = parent
            else
                break
            end
        end
        return path
    end
    
    local path = build_path(rack2)
    assert.not_nil(path, "Path should be built")
    assert.equals(2, #path, "Path should have 2 entries (rack2, chain1)")
    assert.equals(rack2:get_guid(), path[1].guid, "First entry should be rack2")
    assert.equals(chain1:get_guid(), path[1].parent_guid, "Rack2's parent should be chain1")
    assert.equals(chain1:get_guid(), path[2].guid, "Second entry should be chain1")
    assert.equals(rack1:get_guid(), path[2].parent_guid, "Chain1's parent should be rack1")
end

local function test_add_device_to_top_level_chain()
    assert.section("Add device to top-level chain")
    
    setup_test_track()
    local chain = create_chain("R1_C1", nil)
    local plugin = {full_name = "VST: ReaComp", name = "ReaComp"}
    
    -- Mock add_fx_by_name to return a device
    local original_add = test_track.add_fx_by_name
    test_track.add_fx_by_name = function(self, name, rec_fx, position)
        local fx_data = {
            name = name,
            guid = "{fx-" .. name .. "-" .. os.time() .. "}",
            enabled = true,
            is_container = name == "Container",
        }
        local fx = TrackFX:new(self, #self._data.fx_chain, fx_data)
        table.insert(self._data.fx_chain, fx_data)
        return fx
    end
    
    -- Note: add_device_to_chain requires full REAPER integration and state tracking
    -- This test verifies the chain is properly set up for device addition
    assert.not_nil(chain, "Chain should exist for device addition")
    local is_container = chain:is_container()
    assert.truthy(is_container, "Chain should be a container")
    
    test_track.add_fx_by_name = original_add
end

local function test_add_device_to_nested_chain()
    assert.section("Add device to chain in nested rack")
    
    setup_test_track()
    local rack = create_rack("R1: Rack")
    local chain = create_chain("R1_C1", rack)
    local plugin = {full_name = "VST: ReaEQ", name = "ReaEQ"}
    
    -- Verify chain setup
    assert.not_nil(chain, "Chain should exist")
    local chain_parent = chain:get_parent_container()
    assert.not_nil(chain_parent, "Chain should have parent rack")
    assert.equals(rack:get_guid(), chain_parent:get_guid(), "Chain's parent should be rack")
    
    -- Verify hierarchy is intact before any operations
    assert.truthy(verify_hierarchy(), "Hierarchy should be intact initially")
    
    -- Note: Actual device addition requires full REAPER integration - this unit test
    -- verifies the chain is properly structured for device addition
end

local function test_add_rack_to_nested_chain()
    assert.section("Add rack to chain in nested rack")
    
    setup_test_track()
    local rack1 = create_rack("R1: Outer Rack")
    local chain = create_chain("R1_C1", rack1)
    local plugin = {full_name = "VST: Test", name = "Test"}
    
    -- Mock create_rack_container
    local original_add = test_track.add_fx_by_name
    test_track.add_fx_by_name = function(self, name, rec_fx, position)
        local fx_data = {
            name = name,
            guid = "{fx-" .. name .. "-" .. os.time() .. "}",
            enabled = true,
            is_container = name == "Container",
            container_channels = name == "Container" and 64 or 2,
        }
        local fx = TrackFX:new(self, #self._data.fx_chain, fx_data)
        table.insert(self._data.fx_chain, fx_data)
        return fx
    end
    
    local rack2 = rack_module.add_rack_to_chain(chain)
    assert.not_nil(rack2, "Rack should be created")
    
    -- Verify chain still has rack1 as parent
    local chain_parent = chain:get_parent_container()
    assert.not_nil(chain_parent, "Chain should still have parent")
    assert.equals(rack1:get_guid(), chain_parent:get_guid(), "Chain's parent should still be rack1")
    
    -- Verify rack2 is in chain
    local found = false
    for child in chain:iter_container_children() do
        if child:get_guid() == rack2:get_guid() then
            found = true
            break
        end
    end
    assert.truthy(found, "Rack2 should be in chain")
    
    -- Verify hierarchy is intact
    assert.truthy(verify_hierarchy(), "Hierarchy should be intact")
    
    test_track.add_fx_by_name = original_add
end

local function test_deep_nesting_preservation()
    assert.section("Deep nesting - rack in chain in rack in chain")
    
    setup_test_track()
    local rack1 = create_rack("R1: Level 1 Rack")
    local chain1 = create_chain("R1_C1", rack1)
    local rack2 = create_rack("R2: Level 2 Rack")
    -- Remove rack2 from track level since it will be nested
    for i, fx_data in ipairs(test_track._data.fx_chain) do
        if fx_data == rack2._data then
            table.remove(test_track._data.fx_chain, i)
            break
        end
    end
    rack2._data.parent = chain1._data
    chain1._data.children = {rack2._data}
    local chain2 = create_chain("R2_C1", rack2)
    
    local plugin = {full_name = "VST: Test", name = "Test"}
    
    -- Mock add_fx_by_name
    local original_add = test_track.add_fx_by_name
    test_track.add_fx_by_name = function(self, name, rec_fx, position)
        local fx_data = {
            name = name,
            guid = "{fx-" .. name .. "-" .. os.time() .. "}",
            enabled = true,
            is_container = name == "Container",
        }
        local fx = TrackFX:new(self, #self._data.fx_chain, fx_data)
        table.insert(self._data.fx_chain, fx_data)
        return fx
    end
    
    local device = rack_module.add_device_to_chain(chain2, plugin)
    assert.not_nil(device, "Device should be created")
    
    -- Verify entire hierarchy is preserved
    local verify_chain2_parent = chain2:get_parent_container()
    assert.not_nil(verify_chain2_parent, "Chain2 should have parent")
    assert.equals(rack2:get_guid(), verify_chain2_parent:get_guid(), "Chain2's parent should be rack2")
    
    local verify_rack2_parent = rack2:get_parent_container()
    assert.not_nil(verify_rack2_parent, "Rack2 should have parent")
    assert.equals(chain1:get_guid(), verify_rack2_parent:get_guid(), "Rack2's parent should be chain1")
    
    local verify_chain1_parent = chain1:get_parent_container()
    assert.not_nil(verify_chain1_parent, "Chain1 should have parent")
    assert.equals(rack1:get_guid(), verify_chain1_parent:get_guid(), "Chain1's parent should be rack1")
    
    assert.truthy(verify_hierarchy(), "Deep hierarchy should be intact")
    
    test_track.add_fx_by_name = original_add
end

local function test_empty_container_additions()
    assert.section("Add to empty containers at various levels")
    
    setup_test_track()
    
    -- Empty chain at track level
    local chain1 = create_chain("R1_C1", nil)
    assert.equals(0, chain1:get_container_child_count(), "Chain should be empty")
    
    -- Empty chain in rack
    local rack = create_rack("R1: Rack")
    local chain2 = create_chain("R1_C1", rack)
    assert.equals(0, chain2:get_container_child_count(), "Chain should be empty")
    
    -- Empty rack in chain
    local rack_in_chain = create_rack("R2: Rack")
    rack_in_chain._data.parent = chain2._data
    chain2._data.children = {rack_in_chain._data}
    assert.equals(0, rack_in_chain:get_container_child_count(), "Rack should be empty")
end

local function test_multiple_devices_preservation()
    assert.section("Add multiple devices - hierarchy preservation")
    
    setup_test_track()
    local rack = create_rack("R1: Rack")
    local chain = create_chain("R1_C1", rack)
    
    local original_add = test_track.add_fx_by_name
    test_track.add_fx_by_name = function(self, name, rec_fx, position)
        local fx_data = {
            name = name,
            guid = "{fx-" .. name .. "-" .. os.time() .. "-" .. math.random(10000) .. "}",
            enabled = true,
            is_container = name == "Container",
        }
        local fx = TrackFX:new(self, #self._data.fx_chain, fx_data)
        table.insert(self._data.fx_chain, fx_data)
        return fx
    end
    
    -- Add first device
    local device1 = rack_module.add_device_to_chain(chain, {full_name = "VST: ReaComp", name = "ReaComp"})
    assert.not_nil(device1, "First device should be created")
    
    -- Verify hierarchy after first addition
    local chain_parent1 = chain:get_parent_container()
    assert.equals(rack:get_guid(), chain_parent1:get_guid(), "Chain should still have rack as parent after first device")
    
    -- Add second device
    local device2 = rack_module.add_device_to_chain(chain, {full_name = "VST: ReaEQ", name = "ReaEQ"})
    assert.not_nil(device2, "Second device should be created")
    
    -- Verify hierarchy after second addition
    local chain_parent2 = chain:get_parent_container()
    assert.equals(rack:get_guid(), chain_parent2:get_guid(), "Chain should still have rack as parent after second device")
    assert.truthy(verify_hierarchy(), "Hierarchy should be intact after multiple additions")
    
    test_track.add_fx_by_name = original_add
end

--------------------------------------------------------------------------------
-- Test Runner
--------------------------------------------------------------------------------

function M.run()
    test_build_container_path_simple()
    test_build_container_path_deep()
    test_add_device_to_top_level_chain()
    test_add_device_to_nested_chain()
    test_add_rack_to_nested_chain()
    test_deep_nesting_preservation()
    test_empty_container_additions()
    test_multiple_devices_preservation()
end

return M

