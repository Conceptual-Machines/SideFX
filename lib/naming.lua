--- SideFX Naming and Pattern Utilities.
-- Pure functions for name parsing, pattern matching, and building SideFX identifiers.
-- These functions are stateless and testable standalone.
-- @module naming
-- @author Nomad Monad
-- @license MIT

local M = {}

--------------------------------------------------------------------------------
-- Plugin Name Stripping
--------------------------------------------------------------------------------

--- Get short name from plugin full name (strip format prefixes).
-- @param full_name string Full plugin name (e.g., "VST: ReaComp")
-- @return string Short name without prefix
function M.get_short_plugin_name(full_name)
    if not full_name then return "" end
    local name = full_name
    name = name:gsub("^VST3?: ", "")
    name = name:gsub("^AU: ", "")
    name = name:gsub("^JS: ", "")
    name = name:gsub("^CLAP: ", "")
    name = name:gsub("^VSTi: ", "")
    -- Strip path for JS
    name = name:gsub("^.+/", "")
    return name
end

--- Strip SideFX internal prefixes from name for clean UI display.
-- @param name string Name with potential SideFX prefix
-- @return string Clean name without prefix
function M.strip_sidefx_prefixes(name)
    if not name then return "" end
    -- Patterns from most specific to least specific
    name = name:gsub("^R%d+_C%d+_D%d+_FX:%s*", "")  -- R1_C1_D1_FX: prefix
    name = name:gsub("^R%d+_C%d+_D%d+:%s*", "")     -- R1_C1_D1: prefix
    name = name:gsub("^R%d+_C%d+:%s*", "")          -- R1_C1: prefix
    name = name:gsub("^D%d+_FX:%s*", "")            -- D1_FX: prefix
    name = name:gsub("^D%d+:%s*", "")               -- D1: prefix
    name = name:gsub("^R%d+:%s*", "")               -- R1: prefix
    -- Also strip plugin format prefixes
    name = name:gsub("^VST3?: ", "")
    name = name:gsub("^AU: ", "")
    name = name:gsub("^JS: ", "")
    name = name:gsub("^CLAP: ", "")
    return name
end

--- Extract the SideFX prefix from a name.
-- @param name string Name with potential prefix
-- @return string Prefix (e.g., "D1: ") or empty string
function M.extract_prefix(name)
    if not name then return "" end
    local prefix = name:match("^(R%d+_C%d+:%s*)")
    if prefix then return prefix end
    prefix = name:match("^(D%d+:%s*)")
    if prefix then return prefix end
    prefix = name:match("^(R%d+:%s*)")
    if prefix then return prefix end
    return ""
end

--------------------------------------------------------------------------------
-- Type Detection (by name pattern)
--------------------------------------------------------------------------------

--- Check if a name indicates a device container (D-prefix).
-- @param name string FX name to check
-- @return boolean
function M.is_device_name(name)
    if not name then return false end
    return name:match("^D%d") ~= nil
end

--- Check if a name indicates a chain container (R{n}_C{n} pattern).
-- @param name string FX name to check
-- @return boolean
function M.is_chain_name(name)
    if not name then return false end
    return name:match("^R%d+_C%d+") ~= nil
end

--- Check if a name indicates a rack container (R{n}: but not a chain).
-- @param name string FX name to check
-- @return boolean
function M.is_rack_name(name)
    if not name then return false end
    return name:match("^R%d+:") ~= nil and not name:match("^R%d+_C%d+")
end

--- Check if a name indicates an internal/hidden element (prefixed with _).
-- @param name string FX name to check
-- @return boolean
function M.is_internal_name(name)
    if not name then return false end
    return name:match("^_") ~= nil
end

--- Check if a name indicates a mixer element.
-- @param name string FX name to check
-- @return boolean
function M.is_mixer_name(name)
    if not name then return false end
    return name:match("^_R%d+_M$") ~= nil 
        or (name:find("SideFX") ~= nil and name:find("Mixer") ~= nil)
end

--- Check if a name indicates a utility FX.
-- @param name string FX name to check
-- @return boolean
function M.is_utility_name(name)
    if not name then return false end
    return name:find("SideFX_Utility") ~= nil 
        or name:find("SideFX Utility") ~= nil
        or name:match("^D%d+_Util$") ~= nil 
        or name:match("_Util$") ~= nil
end

--- Check if a name indicates a modulator FX.
-- @param name string FX name to check
-- @return boolean
function M.is_modulator_name(name)
    if not name then return false end
    return name:find("SideFX_Modulator") ~= nil
        or name:find("SideFX Modulator") ~= nil
end

--------------------------------------------------------------------------------
-- Index Parsing
--------------------------------------------------------------------------------

--- Parse device index from name (D{n}).
-- @param name string Name to parse
-- @return number|nil Device index or nil
function M.parse_device_index(name)
    if not name then return nil end
    local idx = name:match("^D(%d+)")
    return idx and tonumber(idx) or nil
end

--- Parse rack index from name (R{n}).
-- @param name string Name to parse
-- @return number|nil Rack index or nil
function M.parse_rack_index(name)
    if not name then return nil end
    local idx = name:match("^R(%d+)")
    return idx and tonumber(idx) or nil
end

--- Parse chain index from name (R{n}_C{m}).
-- @param name string Name to parse
-- @return number|nil Chain index or nil
function M.parse_chain_index(name)
    if not name then return nil end
    local _, chain = name:match("^R(%d+)_C(%d+)")
    return chain and tonumber(chain) or nil
end

--- Parse full hierarchy from name.
-- @param name string Name to parse (e.g., "R1_C2_D3: ReaComp")
-- @return table {rack_idx, chain_idx, device_idx, fx_name}
function M.parse_hierarchy(name)
    if not name then return {} end
    
    local result = {}
    
    -- Try R{n}_C{m}_D{p}: pattern first
    local r, c, d, fx = name:match("^R(%d+)_C(%d+)_D(%d+):%s*(.*)$")
    if r then
        result.rack_idx = tonumber(r)
        result.chain_idx = tonumber(c)
        result.device_idx = tonumber(d)
        result.fx_name = fx
        return result
    end
    
    -- Try R{n}_C{m}: pattern
    r, c, fx = name:match("^R(%d+)_C(%d+):%s*(.*)$")
    if r then
        result.rack_idx = tonumber(r)
        result.chain_idx = tonumber(c)
        result.fx_name = fx
        return result
    end
    
    -- Try R{n}: pattern
    r, fx = name:match("^R(%d+):%s*(.*)$")
    if r then
        result.rack_idx = tonumber(r)
        result.fx_name = fx
        return result
    end
    
    -- Try D{n}: pattern
    d, fx = name:match("^D(%d+):%s*(.*)$")
    if d then
        result.device_idx = tonumber(d)
        result.fx_name = fx
        return result
    end
    
    return result
end

--------------------------------------------------------------------------------
-- Name Building
--------------------------------------------------------------------------------

--- Build device container name.
-- @param device_idx number Device index
-- @param fx_name string FX display name
-- @return string Full device container name (e.g., "D1: ReaComp")
function M.build_device_name(device_idx, fx_name)
    return string.format("D%d: %s", device_idx, fx_name)
end

--- Build device internal FX name.
-- @param device_idx number Device index
-- @param fx_name string FX display name
-- @return string Full FX name with _FX suffix (e.g., "D1_FX: ReaComp")
function M.build_device_fx_name(device_idx, fx_name)
    return string.format("D%d_FX: %s", device_idx, fx_name)
end

--- Build device utility name.
-- @param device_idx number Device index
-- @return string Utility name (e.g., "D1_Util")
function M.build_device_util_name(device_idx)
    return string.format("D%d_Util", device_idx)
end

--- Build chain container name.
-- @param rack_idx number Rack index
-- @param chain_idx number Chain index
-- @return string Chain name (e.g., "R1_C1")
function M.build_chain_name(rack_idx, chain_idx)
    return string.format("R%d_C%d", rack_idx, chain_idx)
end

--- Build chain device name.
-- @param rack_idx number Rack index
-- @param chain_idx number Chain index
-- @param device_idx number Device index within chain
-- @param fx_name string FX display name
-- @return string Full hierarchical name (e.g., "R1_C1_D1: ReaComp")
function M.build_chain_device_name(rack_idx, chain_idx, device_idx, fx_name)
    return string.format("R%d_C%d_D%d: %s", rack_idx, chain_idx, device_idx, fx_name)
end

--- Build chain device internal FX name.
-- @param rack_idx number Rack index
-- @param chain_idx number Chain index
-- @param device_idx number Device index within chain
-- @param fx_name string FX display name
-- @return string Full hierarchical FX name
function M.build_chain_device_fx_name(rack_idx, chain_idx, device_idx, fx_name)
    return string.format("R%d_C%d_D%d_FX: %s", rack_idx, chain_idx, device_idx, fx_name)
end

--- Build chain device utility name.
-- @param rack_idx number Rack index
-- @param chain_idx number Chain index
-- @param device_idx number Device index within chain
-- @return string Hierarchical utility name
function M.build_chain_device_util_name(rack_idx, chain_idx, device_idx)
    return string.format("R%d_C%d_D%d_Util", rack_idx, chain_idx, device_idx)
end

--- Build rack container name.
-- @param rack_idx number Rack index
-- @param display_name string|nil Optional display name (default: "Rack")
-- @return string Rack name (e.g., "R1: Rack")
function M.build_rack_name(rack_idx, display_name)
    return string.format("R%d: %s", rack_idx, display_name or "Rack")
end

--- Build mixer name.
-- @param rack_idx number Rack index
-- @return string Mixer name (e.g., "_R1_M")
function M.build_mixer_name(rack_idx)
    return string.format("_R%d_M", rack_idx)
end

--------------------------------------------------------------------------------
-- Truncation
--------------------------------------------------------------------------------

--- Truncate a string to max length with ellipsis.
-- @param str string String to truncate
-- @param max_len number Maximum length
-- @return string Truncated string
function M.truncate(str, max_len)
    if not str then return "" end
    if #str <= max_len then return str end
    return str:sub(1, max_len - 2) .. ".."
end

return M

