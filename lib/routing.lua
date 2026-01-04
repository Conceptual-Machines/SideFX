--- Smart routing utilities for parallel FX chains and instrument layers.
-- Handles the common gotchas with container channel routing.
-- Uses ReaWrap TrackFX objects.
-- @module routing
-- @author Nomad Monad
-- @license MIT

local r = reaper
local container = require('container')

local M = {}

--------------------------------------------------------------------------------
-- Pin Mapping Helpers (using ReaWrap TrackFX)
--------------------------------------------------------------------------------

--- Get FX pin mappings.
-- @param fx TrackFX ReaWrap FX object
-- @param is_output boolean True for output pins, false for input
-- @param pin number Pin index (0-based)
-- @return number, number Low 32 bits, high 32 bits of channel mapping
function M.get_pin_mapping(fx, is_output, pin)
    local ok, low32, high32 = pcall(function()
        return fx:get_pin_mappings(is_output and 1 or 0, pin)
    end)
    return ok and low32 or 0, ok and high32 or 0
end

--- Set FX pin mappings.
-- @param fx TrackFX ReaWrap FX object
-- @param is_output boolean True for output pins, false for input
-- @param pin number Pin index (0-based)
-- @param low32 number Low 32 bits of channel mapping
-- @param high32 number High 32 bits of channel mapping
-- @return boolean Success
function M.set_pin_mapping(fx, is_output, pin, low32, high32)
    local ok = pcall(function()
        return fx:set_pin_mappings(is_output and 1 or 0, pin, low32, high32 or 0)
    end)
    return ok
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
-- @param fx TrackFX ReaWrap FX object
-- @param input_start number Input start channel (1-based)
-- @param output_start number Output start channel (1-based)
function M.route_fx_to_channels(fx, input_start, output_start)
    local in_mask = M.stereo_mask(input_start)
    local out_mask = M.stereo_mask(output_start)
    
    -- Set input pins (L and R)
    M.set_pin_mapping(fx, false, 0, in_mask, 0)  -- Left in
    M.set_pin_mapping(fx, false, 1, in_mask, 0)  -- Right in
    
    -- Set output pins (L and R)
    M.set_pin_mapping(fx, true, 0, out_mask, 0)  -- Left out
    M.set_pin_mapping(fx, true, 1, out_mask, 0)  -- Right out
end

--------------------------------------------------------------------------------
-- Parallel FX Rack (using ReaWrap)
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
-- @param track Track ReaWrap Track object
-- @param fx_list table Array of TrackFX objects to make parallel
-- @param config table|nil Optional ParallelRackConfig overrides
-- @return TrackFX|nil Container object, or nil on failure
function M.create_parallel_rack(track, fx_list, config)
    config = config or {}
    local chain_count = #fx_list
    
    if chain_count < 2 then
        r.ShowConsoleMsg("SideFX: Need at least 2 FX for parallel rack\n")
        return nil
    end
    
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
    -- Create container
    local rack = container.create(track)
    if not rack then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Create parallel rack (failed)", -1)
        return nil
    end
    
    -- Set up container channels: 2 stereo pairs per chain
    local total_channels = chain_count * 2
    container.set_channel_count(rack, total_channels)
    container.set_input_pins(rack, 2)  -- Stereo in
    container.set_output_pins(rack, 2) -- Stereo out
    
    -- Sort FX by index descending to avoid index shifting issues
    local sorted_fx = {}
    for _, fx in ipairs(fx_list) do
        sorted_fx[#sorted_fx + 1] = fx
    end
    table.sort(sorted_fx, function(a, b) return a.pointer > b.pointer end)
    
    -- Move FX into container (highest index first)
    for _, fx in ipairs(sorted_fx) do
        container.move_fx_to_container(fx, rack)
    end
    
    -- Now route each FX in the container to its own stereo pair
    local children = container.get_children(rack)
    for i, child in ipairs(children) do
        local channel_start = ((i - 1) * 2) + 1
        M.route_fx_to_channels(child, channel_start, channel_start)
    end
    
    -- TODO: Add a JS mixer/utility at the end to sum channels back to stereo
    
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("SideFX: Create parallel rack", -1)
    
    return rack
end

--------------------------------------------------------------------------------
-- Instrument Layer (using ReaWrap)
--------------------------------------------------------------------------------

--- Create an instrument layer container.
-- Routes MIDI to all instruments, sums audio outputs.
-- @param track Track ReaWrap Track object
-- @param instruments table Array of instrument TrackFX objects
-- @return TrackFX|nil Container object, or nil on failure
function M.create_instrument_layer(track, instruments)
    local inst_count = #instruments
    
    if inst_count < 2 then
        r.ShowConsoleMsg("SideFX: Need at least 2 instruments for layer\n")
        return nil
    end
    
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
    -- Create container
    local layer = container.create(track)
    if not layer then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Create instrument layer (failed)", -1)
        return nil
    end
    
    -- Set up container channels for all instruments
    local total_channels = inst_count * 2
    container.set_channel_count(layer, total_channels)
    container.set_input_pins(layer, 2)
    container.set_output_pins(layer, 2)
    
    -- Sort descending by index
    local sorted = {}
    for _, inst in ipairs(instruments) do
        sorted[#sorted + 1] = inst
    end
    table.sort(sorted, function(a, b) return a.pointer > b.pointer end)
    
    -- Move instruments to container
    for _, inst in ipairs(sorted) do
        container.move_fx_to_container(inst, layer)
    end
    
    -- Route each instrument:
    -- - All receive MIDI (default behavior)
    -- - Each outputs to different stereo pair
    local children = container.get_children(layer)
    for i, child in ipairs(children) do
        local channel_start = ((i - 1) * 2) + 1
        M.route_fx_to_channels(child, 1, channel_start)
    end
    
    -- TODO: Add summing at the end
    
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("SideFX: Create instrument layer", -1)
    
    return layer
end

--------------------------------------------------------------------------------
-- Serial Chain (simple grouping, using ReaWrap)
--------------------------------------------------------------------------------

--- Create a serial chain container from FX.
-- Simple grouping without parallel routing.
-- @param track Track ReaWrap Track object
-- @param fx_list table Array of TrackFX objects
-- @return TrackFX|nil Container object, or nil on failure
function M.create_serial_chain(track, fx_list)
    if #fx_list < 1 then
        return nil
    end
    
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
    local chain = container.create(track)
    if not chain then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Create chain (failed)", -1)
        return nil
    end
    
    -- Sort descending and move
    local sorted = {}
    for _, fx in ipairs(fx_list) do
        sorted[#sorted + 1] = fx
    end
    table.sort(sorted, function(a, b) return a.pointer > b.pointer end)
    
    for _, fx in ipairs(sorted) do
        container.move_fx_to_container(fx, chain)
    end
    
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("SideFX: Create chain", -1)
    
    return chain
end

--------------------------------------------------------------------------------
-- Diagnostic / Fix Functions
--------------------------------------------------------------------------------

--- Detect potential routing issues in a container.
-- @param rack TrackFX Container FX object
-- @return table Array of issue descriptions
function M.diagnose_container(rack)
    local issues = {}
    local children = container.get_children(rack)
    
    if #children == 0 then
        return issues
    end
    
    -- Check for multiple instruments
    local instrument_count = 0
    for _, child in ipairs(children) do
        -- Simple heuristic: check if FX name contains common instrument identifiers
        local name = container.get_fx_name(child)
        if name and (name:find("VSTi") or name:find("Synth") or name:find("Kontakt")) then
            instrument_count = instrument_count + 1
        end
    end
    
    if instrument_count > 1 then
        local nch = container.get_channel_count(rack)
        local needed = instrument_count * 2
        if nch < needed then
            issues[#issues + 1] = {
                type = "insufficient_channels",
                message = string.format(
                    "Container has %d instruments but only %d channels. Need at least %d.",
                    instrument_count, nch, needed
                ),
                fix = function()
                    container.set_channel_count(rack, needed)
                end
            }
        end
    end
    
    return issues
end

--- Auto-fix common routing issues in a container.
-- @param rack TrackFX Container FX object
-- @return number Number of issues fixed
function M.auto_fix_container(rack)
    local issues = M.diagnose_container(rack)
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
