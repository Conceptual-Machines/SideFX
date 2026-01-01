--- Smart routing utilities for parallel FX chains and instrument layers.
-- Handles the common gotchas with container channel routing.
-- @module routing
-- @author Nomad Monad
-- @license MIT

local r = reaper
local container = require('container')

local M = {}

--------------------------------------------------------------------------------
-- Pin Mapping Helpers
--------------------------------------------------------------------------------

--- Get FX pin mappings.
-- @param track MediaTrack* Track pointer
-- @param fx_idx number FX index
-- @param is_output boolean True for output pins, false for input
-- @param pin number Pin index (0-based)
-- @return number, number Low 32 bits, high 32 bits of channel mapping
function M.get_pin_mapping(track, fx_idx, is_output, pin)
    return r.TrackFX_GetPinMappings(track, fx_idx, is_output and 1 or 0, pin)
end

--- Set FX pin mappings.
-- @param track MediaTrack* Track pointer
-- @param fx_idx number FX index
-- @param is_output boolean True for output pins, false for input
-- @param pin number Pin index (0-based)
-- @param low32 number Low 32 bits of channel mapping
-- @param high32 number High 32 bits of channel mapping
-- @return boolean Success
function M.set_pin_mapping(track, fx_idx, is_output, pin, low32, high32)
    return r.TrackFX_SetPinMappings(track, fx_idx, is_output and 1 or 0, pin, low32, high32 or 0)
end

--- Create a channel bitmask for stereo on specific channels.
-- @param start_channel number Starting channel (1-based)
-- @return number Bitmask for channels start and start+1
function M.stereo_mask(start_channel)
    -- Channels are 0-indexed in the bitmask
    local ch = start_channel - 1
    return (1 << ch) | (1 << (ch + 1))
end

--- Route an FX to specific stereo channels.
-- @param track MediaTrack* Track pointer
-- @param fx_idx number FX index
-- @param input_start number Input start channel (1-based)
-- @param output_start number Output start channel (1-based)
function M.route_fx_to_channels(track, fx_idx, input_start, output_start)
    local in_mask = M.stereo_mask(input_start)
    local out_mask = M.stereo_mask(output_start)
    
    -- Set input pins (L and R)
    M.set_pin_mapping(track, fx_idx, false, 0, in_mask, 0)  -- Left in
    M.set_pin_mapping(track, fx_idx, false, 1, in_mask, 0)  -- Right in
    
    -- Set output pins (L and R)
    M.set_pin_mapping(track, fx_idx, true, 0, out_mask, 0)  -- Left out
    M.set_pin_mapping(track, fx_idx, true, 1, out_mask, 0)  -- Right out
end

--------------------------------------------------------------------------------
-- Parallel FX Rack
--------------------------------------------------------------------------------

--- Configuration for parallel rack creation.
M.ParallelRackConfig = {
    -- Number of parallel chains (each gets its own stereo pair)
    chain_count = 2,
    -- Whether to add a mixer at the end to sum back to stereo
    add_mixer = true,
    -- Name for the container
    name = "Parallel Rack",
}

--- Create a parallel FX rack from selected FX.
-- Takes FX and routes them in parallel within a container.
-- @param track MediaTrack* Track pointer  
-- @param fx_indices table Array of FX indices to make parallel
-- @param config table|nil Optional ParallelRackConfig overrides
-- @return number Container index, or -1 on failure
function M.create_parallel_rack(track, fx_indices, config)
    config = config or {}
    local chain_count = #fx_indices
    
    if chain_count < 2 then
        reaper.ShowConsoleMsg("SideFX: Need at least 2 FX for parallel rack\n")
        return -1
    end
    
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
    -- Create container
    local container_idx = container.create(track)
    if container_idx < 0 then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Create parallel rack (failed)", -1)
        return -1
    end
    
    -- Set up container channels: 2 stereo pairs per chain
    local total_channels = chain_count * 2
    container.set_channel_count(track, container_idx, total_channels)
    container.set_input_pins(track, container_idx, 2)  -- Stereo in
    container.set_output_pins(track, container_idx, 2) -- Stereo out
    
    -- Move FX into container and route each to different channel pairs
    -- We need to sort indices descending to avoid index shifting issues
    local sorted_indices = {}
    for _, idx in ipairs(fx_indices) do
        sorted_indices[#sorted_indices + 1] = idx
    end
    table.sort(sorted_indices, function(a, b) return a > b end)
    
    -- Move FX (highest index first to preserve lower indices)
    local moved_fx = {}
    for i, fx_idx in ipairs(sorted_indices) do
        if container.move_fx_to_container(track, fx_idx, container_idx) then
            moved_fx[#moved_fx + 1] = fx_idx
        end
    end
    
    -- Now route each FX in the container to its own stereo pair
    -- Get the actual child indices after moving
    local children = container.get_children(track, container_idx)
    for i, child_idx in ipairs(children) do
        local channel_start = ((i - 1) * 2) + 1
        M.route_fx_to_channels(track, child_idx, channel_start, channel_start)
    end
    
    -- TODO: Add a JS mixer/utility at the end to sum channels back to stereo
    -- For now, user needs to handle the summing
    
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("SideFX: Create parallel rack", -1)
    
    return container_idx
end

--------------------------------------------------------------------------------
-- Instrument Layer
--------------------------------------------------------------------------------

--- Create an instrument layer container.
-- Routes MIDI to all instruments, sums audio outputs.
-- @param track MediaTrack* Track pointer
-- @param instrument_indices table Array of instrument FX indices
-- @return number Container index, or -1 on failure
function M.create_instrument_layer(track, instrument_indices)
    local inst_count = #instrument_indices
    
    if inst_count < 2 then
        reaper.ShowConsoleMsg("SideFX: Need at least 2 instruments for layer\n")
        return -1
    end
    
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
    -- Create container
    local container_idx = container.create(track)
    if container_idx < 0 then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Create instrument layer (failed)", -1)
        return -1
    end
    
    -- Set up container channels for all instruments
    -- Each instrument needs its own stereo output pair
    local total_channels = inst_count * 2
    container.set_channel_count(track, container_idx, total_channels)
    container.set_input_pins(track, container_idx, 2)
    container.set_output_pins(track, container_idx, 2)
    
    -- Sort indices descending
    local sorted_indices = {}
    for _, idx in ipairs(instrument_indices) do
        sorted_indices[#sorted_indices + 1] = idx
    end
    table.sort(sorted_indices, function(a, b) return a > b end)
    
    -- Move instruments to container
    for _, fx_idx in ipairs(sorted_indices) do
        container.move_fx_to_container(track, fx_idx, container_idx)
    end
    
    -- Route each instrument:
    -- - All receive MIDI (default behavior)
    -- - Each outputs to different stereo pair
    local children = container.get_children(track, container_idx)
    for i, child_idx in ipairs(children) do
        local channel_start = ((i - 1) * 2) + 1
        -- Instruments generate audio, so we only set output routing
        -- Input routing for instruments is typically MIDI, not audio
        M.route_fx_to_channels(track, child_idx, 1, channel_start)
    end
    
    -- TODO: Add summing at the end
    
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("SideFX: Create instrument layer", -1)
    
    return container_idx
end

--------------------------------------------------------------------------------
-- Serial Chain (simple grouping)
--------------------------------------------------------------------------------

--- Create a serial chain container from FX.
-- Simple grouping without parallel routing.
-- @param track MediaTrack* Track pointer
-- @param fx_indices table Array of FX indices
-- @return number Container index, or -1 on failure
function M.create_serial_chain(track, fx_indices)
    if #fx_indices < 1 then
        return -1
    end
    
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
    local container_idx = container.create(track)
    if container_idx < 0 then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Create chain (failed)", -1)
        return -1
    end
    
    -- Sort descending and move
    local sorted_indices = {}
    for _, idx in ipairs(fx_indices) do
        sorted_indices[#sorted_indices + 1] = idx
    end
    table.sort(sorted_indices, function(a, b) return a > b end)
    
    for _, fx_idx in ipairs(sorted_indices) do
        container.move_fx_to_container(track, fx_idx, container_idx)
    end
    
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("SideFX: Create chain", -1)
    
    return container_idx
end

--------------------------------------------------------------------------------
-- Diagnostic / Fix Functions
--------------------------------------------------------------------------------

--- Detect potential routing issues in a container.
-- @param track MediaTrack* Track pointer
-- @param container_idx number Container FX index
-- @return table Array of issue descriptions
function M.diagnose_container(track, container_idx)
    local issues = {}
    local children = container.get_children(track, container_idx)
    
    if #children == 0 then
        return issues
    end
    
    -- Check for multiple instruments
    local instrument_count = 0
    for _, child_idx in ipairs(children) do
        if container.is_instrument(track, child_idx) then
            instrument_count = instrument_count + 1
        end
    end
    
    if instrument_count > 1 then
        local nch = container.get_channel_count(track, container_idx)
        local needed = instrument_count * 2
        if nch < needed then
            issues[#issues + 1] = {
                type = "insufficient_channels",
                message = string.format(
                    "Container has %d instruments but only %d channels. Need at least %d.",
                    instrument_count, nch, needed
                ),
                fix = function()
                    container.set_channel_count(track, container_idx, needed)
                end
            }
        end
    end
    
    -- TODO: Add more diagnostic checks
    -- - Overlapping output channels
    -- - Missing summing
    -- - etc.
    
    return issues
end

--- Auto-fix common routing issues in a container.
-- @param track MediaTrack* Track pointer
-- @param container_idx number Container FX index
-- @return number Number of issues fixed
function M.auto_fix_container(track, container_idx)
    local issues = M.diagnose_container(track, container_idx)
    local fixed = 0
    
    for _, issue in ipairs(issues) do
        if issue.fix then
            issue.fix()
            fixed = fixed + 1
        end
    end
    
    return fixed
end

return M

