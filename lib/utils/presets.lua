--- SideFX Presets.
-- Chain preset save/load operations.
-- @module presets
-- @author Nomad Monad
-- @license MIT

local r = reaper
local state_mod = require('lib.core.state')
local modulator_mod = require('lib.modulator.modulator')
local json = require('lib.utils.json')
local fx_utils = require('lib.fx.fx_utils')

-- Load RPP Parser library
local rpp_parser_path = r.GetResourcePath() .. "/Scripts/ReaTeam Scripts/Development/RPP-Parser/Reateam_RPP-Parser.lua"
local ok, err = pcall(function()
    dofile(rpp_parser_path)
end)

if not ok then
    r.ShowMessageBox("Failed to load RPP Parser library.\nPath: " .. rpp_parser_path .. "\nError: " .. tostring(err), "SideFX - Missing Dependency", 0)
    error("RPP Parser not found. Please install it via ReaPack (ReaTeam Scripts > Development > RPP-Parser)")
end

local M = {}

-- Presets folder path (must be set via init before use)
local presets_folder = nil

--- Initialize the presets module.
function M.init()
    -- Save presets to [REAPER Resource Path]/presets/SideFX_Presets/
    presets_folder = r.GetResourcePath() .. "/presets/SideFX_Presets/"
end

--- Ensure the presets folder structure exists.
function M.ensure_folder()
    if not presets_folder then return end
    r.RecursiveCreateDirectory(presets_folder, 0)
    r.RecursiveCreateDirectory(presets_folder .. "chains/", 0)
end

--- Collect SideFX metadata for the current track.
-- @return table Metadata object
local function collect_metadata()
    local state = state_mod.state
    local metadata = {
        version = "1.0",
        display_names = {},
        param_selections = {},
        modulators = {},
    }

    if not state.track then return metadata end

    -- Collect display names (keyed by FX GUID)
    for guid, name in pairs(state.display_names) do
        -- Get FX to find its position/name for matching on load
        local fx = state.track:find_fx_by_guid(guid)
        if fx then
            local ok, fx_name = pcall(function() return fx:get_name() end)
            local ok_idx, fx_idx = pcall(function() return fx.pointer end)
            if ok and ok_idx and fx_name then
                metadata.display_names[guid] = {
                    name = name,
                    fx_name = fx_name,
                    fx_idx = fx_idx,
                }
            end
        end
    end

    -- Collect parameter selections (keyed by plugin name)
    if state.param_selections then
        for plugin_name, params in pairs(state.param_selections) do
            metadata.param_selections[plugin_name] = params
        end
    end

    -- Collect modulator configurations
    local modulators = modulator_mod.find_modulators_on_track()
    for i, mod_info in ipairs(modulators) do
        local mod_fx = mod_info.fx
        local ok_guid, mod_guid = pcall(function() return mod_fx:get_guid() end)
        local ok_name, mod_name = pcall(function() return mod_fx:get_name() end)
        local ok_idx, mod_idx = pcall(function() return mod_fx.pointer end)

        if ok_guid and ok_name and ok_idx and mod_guid and mod_name then
            -- Get links for this modulator
            local links = modulator_mod.get_modulator_links(mod_fx)
            local link_data = {}

            for _, link in ipairs(links) do
                local ok_target_guid, target_guid = pcall(function() return link.target_fx:get_guid() end)
                local ok_target_name, target_name = pcall(function() return link.target_fx:get_name() end)
                local ok_target_idx, target_idx = pcall(function() return link.target_fx.pointer end)

                if ok_target_guid and ok_target_name and ok_target_idx and target_guid and target_name then
                    table.insert(link_data, {
                        target_fx_guid = target_guid,
                        target_fx_name = target_name,
                        target_fx_idx = target_idx,
                        target_param_idx = link.target_param_idx,
                        target_param_name = link.target_param_name,
                    })
                end
            end

            table.insert(metadata.modulators, {
                mod_guid = mod_guid,
                mod_name = mod_name,
                mod_idx = mod_idx,
                links = link_data,
            })
        end
    end

    return metadata
end

--- Extract FXCHAIN content from track chunk using RPP Parser.
-- @param track_chunk string The track state chunk
-- @return string|nil fxchain_data The extracted FX chain content (just the FX, not FXCHAIN wrapper)
local function extract_fxchain_content(track_chunk)
    -- Parse the track chunk
    local track_root = ReadRPPChunk(track_chunk)
    if not track_root then
        return nil
    end

    -- Find FXCHAIN chunk
    local fxchain = track_root:findFirstChunkByName("FXCHAIN")
    if not fxchain or not fxchain.children then
        return nil
    end

    -- Extract only FX chunks (RChunk type), skip attributes (RNode type)
    local fx_lines = {}
    for _, child in ipairs(fxchain.children) do
        -- RChunk has 'children' property (even if empty), RNode doesn't
        -- FX are RChunks (CONTAINER, VST, JS, etc), attributes are RNodes (WNDRECT, SHOW, etc)
        if child.children then
            -- This is an RChunk (an FX)
            local child_str = StringifyRPPNode(child)
            if child_str and child_str ~= "" then
                table.insert(fx_lines, child_str)
            end
        end
    end
    
    return table.concat(fx_lines, "\n")
end

--- Save the current track's FX chain as a preset.
-- @param preset_name string Name for the preset
-- @return boolean Success
function M.save_chain(preset_name)
    local state = state_mod.state
    if not state.track or not preset_name or preset_name == "" then return false end
    if not presets_folder then return false end

    M.ensure_folder()

    local chain_path = presets_folder .. "chains/" .. preset_name .. ".RfxChain"

    -- Manually serialize FX chain using GetChunk
    local file = io.open(chain_path, "w")
    if not file then
        r.ShowMessageBox("Failed to create preset file: " .. chain_path, "SideFX", 0)
        return false
    end

    -- Get all top-level FX (indices 0 to fx_count-1 are top-level)
    -- Nested FX have encoded indices (0x2000000+) and are included in parent's chunk
    local ok_count, fx_count = pcall(function()
        return state.track:get_track_fx_count()
    end)

    if not ok_count or not fx_count or fx_count == 0 then
        file:close()
        r.ShowMessageBox("No FX found on track to save.", "SideFX", 0)
        return false
    end

    local fx_written = 0
    local track_ptr = state.track.pointer

    -- Verify track pointer is valid
    if not track_ptr then
        file:close()
        r.ShowMessageBox("Invalid track pointer. Cannot save preset.", "SideFX", 0)
        return false
    end

    -- Use GetTrackStateChunk to get the entire track state, then extract FXCHAIN section
    -- In Lua, GetTrackStateChunk might return the chunk as a string or modify buffer
    -- Try both approaches

    local track_chunk = nil

    -- Get track state chunk - in Lua, GetTrackStateChunk returns the chunk as second return value
    local ret, track_chunk = r.GetTrackStateChunk(track_ptr, "", false)

    if not ret or not track_chunk or track_chunk == "" then
        file:close()
        r.ShowMessageBox("Failed to retrieve track state chunk.", "SideFX", 0)
        return false
    end

    -- Extract FXCHAIN content
    local fxchain_data = extract_fxchain_content(track_chunk)

    if not fxchain_data then
        file:close()
        r.ShowMessageBox("Failed to extract FX chain from track.", "SideFX", 0)
        return false
    end

    -- Write to file
    file:write(fxchain_data)
    if not fxchain_data:match("\n$") then
        file:write("\n")
    end
    fx_written = 1

    file:close()

    if fx_written == 0 then
        -- No FX chunks were successfully retrieved
        r.ShowMessageBox("Failed to retrieve FX data from track. The track may have no FX or the FX may be in an invalid state.", "SideFX", 0)
        return false
    end

    -- Collect and save SideFX metadata
    local metadata = collect_metadata()
    local json_str = json.encode(metadata)
    local metadata_path = presets_folder .. "chains/" .. preset_name .. ".sidefx.json"

    -- Write JSON file
    local meta_file = io.open(metadata_path, "w")
    if meta_file then
        meta_file:write(json_str)
        meta_file:close()
        return true
    else
        -- Chain saved but metadata failed - still return true
        return true
    end
end

--- Apply SideFX metadata to the loaded chain.
-- @param metadata table Metadata object
local function apply_metadata(metadata)
    local state = state_mod.state
    if not state.track or not metadata then return end

    -- Apply parameter selections
    if metadata.param_selections then
        for plugin_name, params in pairs(metadata.param_selections) do
            if not state.param_selections then
                state.param_selections = {}
            end
            state.param_selections[plugin_name] = params
        end
    end

    -- Apply display names (match by FX name and index)
    if metadata.display_names then
        for old_guid, name_data in pairs(metadata.display_names) do
            -- Find FX by name and approximate position
            local fx = nil
            for fx_info in state.track:iter_all_fx_flat() do
                local ok, fx_name = pcall(function() return fx_info.fx:get_name() end)
                if ok and fx_name == name_data.fx_name then
                    fx = fx_info.fx
                    break
                end
            end

            if fx then
                local ok, new_guid = pcall(function() return fx:get_guid() end)
                if ok and new_guid then
                    state.display_names[new_guid] = name_data.name
                end
            end
        end
    end

    -- Apply modulator links (match by modulator name and target FX name + param)
    if metadata.modulators then
        for _, mod_data in ipairs(metadata.modulators) do
            -- Find modulator by name
            local mod_fx = nil
            for fx_info in state.track:iter_all_fx_flat() do
                local ok, fx_name = pcall(function() return fx_info.fx:get_name() end)
                if ok and fx_name and (fx_name:find(modulator_mod.MODULATOR_JSFX) or fx_name:find("SideFX Modulator")) then
                    mod_fx = fx_info.fx
                    break
                end
            end

            if mod_fx and mod_data.links then
                -- Restore links
                for _, link_data in ipairs(mod_data.links) do
                    -- Find target FX by name
                    local target_fx = nil
                    for fx_info in state.track:iter_all_fx_flat() do
                        local ok, fx_name = pcall(function() return fx_info.fx:get_name() end)
                        if ok and fx_name == link_data.target_fx_name then
                            target_fx = fx_info.fx
                            break
                        end
                    end

                    if target_fx then
                        -- Try to find parameter by name
                        local param_count = target_fx:get_num_params()
                        for param_idx = 0, param_count - 1 do
                            local ok, param_name = pcall(function() return target_fx:get_param_name(param_idx) end)
                            if ok and param_name == link_data.target_param_name then
                                modulator_mod.create_param_link(mod_fx, target_fx, param_idx)
                                break
                            end
                        end
                    end
                end
            end
        end
    end
end

--- Read a preset file.
-- @param path string File path
-- @return string|nil content File content or nil on error
local function read_preset_file(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end

    local content = file:read("*all")
    file:close()

    if not content or content == "" then
        return nil
    end

    return content
end

--- Replace FXCHAIN content in track chunk using RPP Parser.
-- @param track_chunk string Original track chunk
-- @param new_content string New FXCHAIN content (just the FX)
-- @return string|nil new_track_chunk Modified track chunk or nil on error
local function replace_fxchain_content(track_chunk, new_content)
    -- Parse the track chunk
    local track_root = ReadRPPChunk(track_chunk)
    if not track_root then
        return nil
    end
    
    -- Find FXCHAIN chunk, create if doesn't exist
    local fxchain = track_root:findFirstChunkByName("FXCHAIN")
    if not fxchain then
        -- Create new FXCHAIN chunk
        fxchain = AddRChunk(track_root, {"FXCHAIN"})
        if not fxchain then
            return nil
        end
    end

    -- Parse the preset content
    -- In SideFX, presets are ALWAYS containers (D, R, or C)
    -- ReadRPPChunk only returns the first chunk, so we need to wrap content in a dummy root
    -- Split by top-level container boundaries and parse each separately
    -- Find all <CONTAINER positions
    local container_starts = {}
    local pos = 1
    
    -- Find first CONTAINER (at start of file)
    if new_content:sub(1, 10) == "<CONTAINER" then
        table.insert(container_starts, 1)
        pos = 2
    end
    
    -- Find subsequent CONTAINERs (preceded by >\n)
    while true do
        local found = new_content:find("\n<CONTAINER", pos, true)
        if not found then break end
        table.insert(container_starts, found + 1)  -- +1 to skip the newline
        pos = found + 1
    end
    
    -- Parse each container separately
    local fx_chunks = {}
    for i, start_pos in ipairs(container_starts) do
        local end_pos = container_starts[i + 1] and (container_starts[i + 1] - 2) or #new_content
        local container_chunk = new_content:sub(start_pos, end_pos)
        
        local parsed_container = ReadRPPChunk(container_chunk)
        if parsed_container then
            table.insert(fx_chunks, parsed_container)
        end
    end
    
    -- Replace FXCHAIN children with new containers
    fxchain.children = fx_chunks
    
    -- Update parent references
    for _, child in ipairs(fxchain.children) do
        child.parent = fxchain
    end
    
    -- Stringify back to track chunk
    return StringifyRPPNode(track_root)
end

--- Apply track chunk to track.
-- @param track_ptr userdata Track pointer
-- @param new_chunk string New track chunk
-- @return boolean success
local function apply_track_chunk(track_ptr, new_chunk)
    return r.SetTrackStateChunk(track_ptr, new_chunk, false)
end

--- Load a chain preset onto the current track.
-- @param preset_name string Name of the preset to load
-- @return boolean Success
function M.load_chain(preset_name)
    local state = state_mod.state
    if not state.track or not preset_name then return false end
    if not presets_folder then return false end

    local chain_path = presets_folder .. "chains/" .. preset_name .. ".RfxChain"
    local metadata_path = presets_folder .. "chains/" .. preset_name .. ".sidefx.json"

    -- Read preset file
    local fxchain_content = read_preset_file(chain_path)
    if not fxchain_content then
        r.ShowMessageBox("Failed to read preset file: " .. chain_path, "SideFX", 0)
        return false
    end

    r.Undo_BeginBlock()

    -- Get current track state
    local ret, track_chunk = r.GetTrackStateChunk(state.track.pointer, "", false)
    if not ret or not track_chunk then
        r.Undo_EndBlock("Load FX Chain Preset (failed)", -1)
        r.ShowMessageBox("Failed to get track state.", "SideFX", 0)
        return false
    end

    -- Replace FXCHAIN in track chunk
    local new_track_chunk = replace_fxchain_content(track_chunk, fxchain_content)

    if not new_track_chunk then
        r.Undo_EndBlock("Load FX Chain Preset (failed)", -1)
        r.ShowMessageBox("Failed to replace FX chain in track.", "SideFX", 0)
        return false
    end

    -- Apply to track
    if not apply_track_chunk(state.track.pointer, new_track_chunk) then
        r.Undo_EndBlock("Load FX Chain Preset (failed)", -1)
        r.ShowMessageBox("Failed to set track state.", "SideFX", 0)
        return false
    end

    -- Refresh FX list to get new GUIDs
    state_mod.refresh_fx_list()

    -- Load and apply metadata if available
    local file = io.open(metadata_path, "r")
    if file then
        local json_str = file:read("*all")
        file:close()

        if json_str and json_str ~= "" then
            local metadata = json.decode(json_str)
            if metadata then
                apply_metadata(metadata)
            end
        end
    end

    r.Undo_EndBlock("Load FX Chain Preset", -1)
    return true
end

--- Get the presets folder path.
-- @return string|nil Presets folder path or nil if not initialized
function M.get_folder()
    return presets_folder
end

return M
