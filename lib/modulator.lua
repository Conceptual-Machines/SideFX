--- SideFX Modulator Operations.
-- Functions for managing SideFX_Modulator JSFX and parameter links.
-- @module modulator
-- @author Nomad Monad
-- @license MIT

local r = reaper

local state_module = require('lib.state')

local M = {}

-- Local reference to state singleton
local state = state_module.state

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

M.MODULATOR_JSFX = "JS:SideFX/SideFX_Modulator"
M.MOD_OUTPUT_PARAM = 3  -- slider4 in JSFX (0-indexed)

--------------------------------------------------------------------------------
-- Modulator Discovery
--------------------------------------------------------------------------------

--- Find all modulators on the current track.
-- @return table Array of {fx, fx_idx, name}
function M.find_modulators_on_track()
    if not state.track then return {} end
    local modulators = {}
    for fx in state.track:iter_track_fx_chain() do
        local name = fx:get_name()
        if name and (name:find(M.MODULATOR_JSFX) or name:find("SideFX Modulator")) then
            table.insert(modulators, {
                fx = fx,
                fx_idx = fx.pointer,
                name = "LFO " .. (#modulators + 1),
            })
        end
    end
    return modulators
end

--- Add a new modulator to the track.
-- @return TrackFX|nil The new modulator FX
function M.add_modulator()
    if not state.track then return end
    r.Undo_BeginBlock()
    -- Add at position 0 (before instruments)
    local fx = state.track:add_fx_by_name(M.MODULATOR_JSFX, false, -1000)
    r.Undo_EndBlock("Add SideFX Modulator", -1)
    return fx
end

--- Delete a modulator by FX index.
-- @param fx_idx number FX index
function M.delete_modulator(fx_idx)
    if not state.track then return end
    r.Undo_BeginBlock()
    r.TrackFX_Delete(state.track.pointer, fx_idx)
    r.Undo_EndBlock("Delete SideFX Modulator", -1)
end

--------------------------------------------------------------------------------
-- Linkable FX
--------------------------------------------------------------------------------

--- Get list of FX that can be modulated.
-- Excludes modulators and containers.
-- @return table Array of {fx, fx_idx, name, params}
function M.get_linkable_fx()
    if not state.track then return {} end
    local linkable = {}
    for fx_info in state.track:iter_all_fx_flat() do
        local fx = fx_info.fx
        local name = fx:get_name()
        -- Skip modulators and containers
        if name and not name:find(M.MODULATOR_JSFX) and not name:find("SideFX Modulator") and not name:find("Container") then
            local params = {}
            local param_count = fx:get_num_params()
            for p = 0, param_count - 1 do
                local pname = fx:get_param_name(p)
                table.insert(params, {idx = p, name = pname})
            end
            -- Add depth indicator to name for nested FX
            local display_name = fx_info.depth > 0 and string.rep("  ", fx_info.depth) .. "↳ " .. name or name
            table.insert(linkable, {fx = fx, fx_idx = fx.pointer, name = display_name, params = params})
        end
    end
    return linkable
end

--------------------------------------------------------------------------------
-- Parameter Links
--------------------------------------------------------------------------------

--- Create a parameter modulation link.
-- @param mod_fx TrackFX|number Modulator FX object or index (must be top-level)
-- @param target_fx TrackFX|number Target FX object or index
-- @param target_param_idx number Target parameter index
-- @return boolean Success
function M.create_param_link(mod_fx, target_fx, target_param_idx)
    if not state.track then return false end
    
    -- Support both TrackFX objects and raw indices for backwards compatibility
    local mod_fx_idx = type(mod_fx) == "number" and mod_fx or mod_fx.pointer
    local target_fx_obj = type(target_fx) == "number" and state.track:get_track_fx(target_fx) or target_fx
    
    if not target_fx_obj then return false end
    
    local plink_prefix = string.format("param.%d.plink.", target_param_idx)
    
    -- Use ReaWrap methods
    local ok1 = target_fx_obj:set_named_config_param(plink_prefix .. "active", "1")
    local ok2 = target_fx_obj:set_named_config_param(plink_prefix .. "effect", tostring(mod_fx_idx))
    local ok3 = target_fx_obj:set_named_config_param(plink_prefix .. "param", tostring(M.MOD_OUTPUT_PARAM))
    
    if not (ok1 and ok2 and ok3) then
        r.ShowConsoleMsg(string.format("Plink failed: mod=%d param=%d (ok: %s %s %s)\n", 
            mod_fx_idx, target_param_idx, 
            tostring(ok1), tostring(ok2), tostring(ok3)))
    end
    
    return ok1 and ok2 and ok3
end

--- Remove a parameter modulation link.
-- @param target_fx TrackFX|number Target FX object or index
-- @param target_param_idx number Target parameter index
function M.remove_param_link(target_fx, target_param_idx)
    if not state.track then return end
    
    local target_fx_obj = type(target_fx) == "number" and state.track:get_track_fx(target_fx) or target_fx
    if not target_fx_obj then return end
    
    local plink_prefix = string.format("param.%d.plink.", target_param_idx)
    target_fx_obj:set_named_config_param(plink_prefix .. "active", "0")
end

--- Get all parameters linked to a modulator.
-- @param mod_fx TrackFX|number Modulator FX object or index
-- @return table Array of link info
function M.get_modulator_links(mod_fx)
    if not state.track then return {} end
    local links = {}
    local mod_fx_idx = type(mod_fx) == "number" and mod_fx or mod_fx.pointer
    
    for fx_info in state.track:iter_all_fx_flat() do
        local fx = fx_info.fx
        local fx_name = fx:get_name()
        -- Skip modulators and containers
        if fx_name and not (fx_name:find(M.MODULATOR_JSFX) or fx_name:find("SideFX Modulator") or fx_name:find("Container")) then
            local param_count = fx:get_num_params()
            for param_idx = 0, param_count - 1 do
                local plink_prefix = string.format("param.%d.plink.", param_idx)
                -- Use ReaWrap method
                local active = fx:get_named_config_param(plink_prefix .. "active")
                if active == "1" then
                    local effect = fx:get_named_config_param(plink_prefix .. "effect")
                    local param = fx:get_named_config_param(plink_prefix .. "param")
                    if tonumber(effect) == mod_fx_idx and tonumber(param) == M.MOD_OUTPUT_PARAM then
                        local param_name = fx:get_param_name(param_idx)
                        table.insert(links, {
                            target_fx = fx,
                            target_fx_idx = fx.pointer,  -- Keep for UI compatibility
                            target_fx_name = fx_name,
                            target_param_idx = param_idx,
                            target_param_name = param_name,
                        })
                    end
                end
            end
        end
    end
    return links
end

--- Check if an FX is a modulator.
-- @param fx TrackFX FX object
-- @return boolean
function M.is_modulator_fx(fx)
    if not fx then return false end
    local name = fx:get_name()
    return name and (name:find(M.MODULATOR_JSFX) or name:find("SideFX Modulator"))
end

return M

