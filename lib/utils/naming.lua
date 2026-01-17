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
    name = name:gsub("^VST3?i?: ", "")  -- VST, VST3, VSTi, VST3i
    name = name:gsub("^AUi?: ", "")     -- AU, AUi
    name = name:gsub("^JS: ", "")
    name = name:gsub("^CLAPi?: ", "")   -- CLAP, CLAPi
    -- Strip path for JS
    name = name:gsub("^.+/", "")
    -- Strip manufacturer info in parentheses at end
    name = name:gsub("%s*%([^)]+%)%s*$", "")
    return name
end

--- Strip SideFX internal prefixes from name for clean UI display.
-- @param name string Name with potential SideFX prefix
-- @return string Clean name without prefix
function M.strip_sidefx_prefixes(name)
    if not name then return "" end
    -- Patterns from most specific to least specific
    name = name:gsub("^R%d+_C%d+_BD%d+:%s*", "")    -- R1_C1_BD1: prefix (bare device in chain)
    name = name:gsub("^R%d+_C%d+_D%d+_FX:%s*", "")  -- R1_C1_D1_FX: prefix
    name = name:gsub("^R%d+_C%d+_D%d+:%s*", "")     -- R1_C1_D1: prefix
    name = name:gsub("^R%d+_C%d+:%s*", "")          -- R1_C1: prefix
    name = name:gsub("^POST%d+:%s*", "")             -- POST1: prefix (post FX device)
    name = name:gsub("^BD%d+:%s*", "")              -- BD1: prefix (bare device)
    name = name:gsub("^D%d+_FX:%s*", "")            -- D1_FX: prefix
    name = name:gsub("^D%d+:%s*", "")               -- D1: prefix
    name = name:gsub("^R%d+:%s*", "")               -- R1: prefix
    -- Also strip plugin format prefixes
    name = name:gsub("^VST3?i?: ", "")  -- VST, VST3, VSTi, VST3i
    name = name:gsub("^AU: ", "")
    name = name:gsub("^AUi: ", "")
    name = name:gsub("^JS: ", "")
    name = name:gsub("^CLAP: ", "")
    name = name:gsub("^CLAPi: ", "")
    -- Strip manufacturer info in parentheses at end (e.g., "Plugin (Manufacturer)")
    name = name:gsub("%s*%([^)]+%)%s*$", "")
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

--- Check if a name indicates a bare device (BD-prefix).
-- @param name string FX name to check
-- @return boolean
function M.is_bare_device_name(name)
    if not name then return false end
    return name:match("^BD%d") ~= nil or name:match("_BD%d") ~= nil
end

--- Check if a name indicates a post FX device (POST-prefix).
-- @param name string FX name to check
-- @return boolean
function M.is_post_device_name(name)
    if not name then return false end
    return name:match("^POST%d") ~= nil
end

--- Check if a name indicates a chain container (R{n}_C{n} pattern, but not device).
-- @param name string FX name to check
-- @return boolean
function M.is_chain_name(name)
    if not name then return false end
    -- Must start with R{n}_C{n} but NOT have _D{n} after
    return name:match("^R%d+_C%d+$") ~= nil or
           (name:match("^R%d+_C%d+:") ~= nil and not name:match("^R%d+_C%d+_D%d+"))
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
    return name:match("SideFX[_ ]Modulator") ~= nil
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

--- Parse bare device index from name (BD{n} or R{n}_C{n}_BD{m}).
-- @param name string Name to parse
-- @return number|nil Bare device index or nil
function M.parse_bare_device_index(name)
    if not name then return nil end
    -- Try R{n}_C{m}_BD{p} pattern first
    local idx = name:match("_BD(%d+)")
    if idx then return tonumber(idx) end
    -- Try BD{n} pattern
    idx = name:match("^BD(%d+)")
    return idx and tonumber(idx) or nil
end

--- Parse post device index from name (POST{n}).
-- @param name string Name to parse
-- @return number|nil Post device index or nil
function M.parse_post_device_index(name)
    if not name then return nil end
    local idx = name:match("^POST(%d+)")
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
-- @param name string Name to parse (e.g., "R1_C2_D3: ReaComp" or "R1_C2")
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

    -- Try R{n}_C{m}: pattern (with colon and fx name)
    r, c, fx = name:match("^R(%d+)_C(%d+):%s*(.*)$")
    if r then
        result.rack_idx = tonumber(r)
        result.chain_idx = tonumber(c)
        result.fx_name = fx
        return result
    end

    -- Try R{n}_C{m} pattern (bare chain name without colon)
    r, c = name:match("^R(%d+)_C(%d+)$")
    if r then
        result.rack_idx = tonumber(r)
        result.chain_idx = tonumber(c)
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
-- Hierarchical Path Building
--------------------------------------------------------------------------------

--- Extract hierarchical path from an FX by walking up parent containers.
-- Returns path components like {rack_idx=1, chain_idx=2, device_idx=3}.
-- @param fx TrackFX FX object
-- @return table|nil Path components, or nil if not in hierarchy
function M.extract_hierarchical_path(fx)
    if not fx then return nil end

    local path = {}
    local current = fx
    local depth = 0
    local max_depth = 10  -- Prevent infinite loops

    -- Walk up the parent chain
    while current and depth < max_depth do
        local name = current:get_name()
        if not name then break end

        -- Check what type of container this is
        local rack_idx = name:match("^R(%d+)")
        local chain_match = name:match("^R%d+_C(%d+)")
        local device_match = name:match("^R%d+_C%d+_D(%d+)")
        local standalone_device = name:match("^D(%d+)")

        if device_match then
            -- This is a device in a rack chain: R1_C1_D1
            path.device_idx = tonumber(device_match)
            path.chain_idx = tonumber(chain_match)
            path.rack_idx = tonumber(rack_idx)
        elseif chain_match then
            -- This is a chain in a rack: R1_C1
            path.chain_idx = tonumber(chain_match)
            path.rack_idx = tonumber(rack_idx)
        elseif rack_idx then
            -- This is a rack: R1
            path.rack_idx = tonumber(rack_idx)
        elseif standalone_device then
            -- This is a standalone device: D1
            path.device_idx = tonumber(standalone_device)
        end

        -- Move to parent
        if not current.get_parent_container then break end
        local parent = current:get_parent_container()
        if not parent then break end
        current = parent
        depth = depth + 1
    end

    return next(path) and path or nil
end

--- Build hierarchical path string from path components.
-- @param path table Path components {rack_idx, chain_idx, device_idx}
-- @return string Path string (e.g., "R1_C1_D1" or "D1")
function M.build_hierarchical_path_string(path)
    if not path then return "" end

    if path.device_idx and path.chain_idx and path.rack_idx then
        return string.format("R%d_C%d_D%d", path.rack_idx, path.chain_idx, path.device_idx)
    elseif path.chain_idx and path.rack_idx then
        return string.format("R%d_C%d", path.rack_idx, path.chain_idx)
    elseif path.rack_idx then
        return string.format("R%d", path.rack_idx)
    elseif path.device_idx then
        return string.format("D%d", path.device_idx)
    end

    return ""
end

--- Build full hierarchical name for an FX component.
-- @param path table|string Path components or path string
-- @param component_type string Component type: "device", "fx", "util", "modulator", "mixer"
-- @param component_idx number|nil Component index (e.g., modulator index)
-- @param display_name string|nil Display name for the component
-- @return string Full hierarchical name
function M.build_hierarchical_name(path, component_type, component_idx, display_name)
    local path_str = type(path) == "string" and path or M.build_hierarchical_path_string(path)
    if path_str == "" then return display_name or "" end

    if component_type == "device" then
        return string.format("%s: %s", path_str, display_name or "Device")
    elseif component_type == "fx" then
        return string.format("%s_FX: %s", path_str, display_name or "FX")
    elseif component_type == "util" then
        return string.format("%s_Util", path_str)
    elseif component_type == "modulator" then
        return string.format("%s_M%d: %s", path_str, component_idx or 1, display_name or "SideFX Modulator")
    elseif component_type == "mixer" then
        return string.format("_%s_M", path_str)
    elseif component_type == "rack" then
        return string.format("%s: %s", path_str, display_name or "Rack")
    elseif component_type == "chain" then
        return path_str
    end

    return display_name or path_str
end

--- Extract hierarchical path from FX name.
-- @param name string FX name (e.g., "R1_C1_D1: Plugin" or "D1_M2: Modulator")
-- @return string|nil Path string (e.g., "R1_C1_D1" or "D1")
function M.extract_path_from_name(name)
    if not name then return nil end

    -- Try to match various patterns
    local path = name:match("^(R%d+_C%d+_D%d+)")
    if path then return path end

    path = name:match("^(R%d+_C%d+)")
    if path then return path end

    path = name:match("^(R%d+)")
    if path then return path end

    path = name:match("^(D%d+)")
    if path then return path end

    return nil
end

--------------------------------------------------------------------------------
-- Name Building (Legacy - consider using build_hierarchical_name instead)
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

--- Build bare device name (raw plugin without container).
-- @param bare_idx number Bare device index
-- @param fx_name string FX display name
-- @return string Full bare device name (e.g., "BD1: ReaComp")
function M.build_bare_device_name(bare_idx, fx_name)
    return string.format("BD%d: %s", bare_idx, fx_name)
end

--- Build post FX device name (always bare, at end of chain).
-- @param post_idx number Post device index
-- @param fx_name string FX display name
-- @return string Full post device name (e.g., "POST1: ReaComp")
function M.build_post_device_name(post_idx, fx_name)
    return string.format("POST%d: %s", post_idx, fx_name)
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

--- Build chain bare device name (raw plugin in chain without D-container).
-- @param rack_idx number Rack index
-- @param chain_idx number Chain index
-- @param bare_idx number Bare device index within chain
-- @param fx_name string FX display name
-- @return string Full hierarchical bare device name (e.g., "R1_C1_BD1: ReaComp")
function M.build_chain_bare_device_name(rack_idx, chain_idx, bare_idx, fx_name)
    return string.format("R%d_C%d_BD%d: %s", rack_idx, chain_idx, bare_idx, fx_name)
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

--- Build modulator name for a device.
-- @param device_path string Device hierarchical path (e.g., "R1_C1_D1" or "D1")
-- @param mod_idx number Modulator index within device
-- @return string Modulator name (e.g., "R1_C1_D1_M1: SideFX Modulator" or "D1_M1: SideFX Modulator")
function M.build_device_modulator_name(device_path, mod_idx)
    return string.format("%s_M%d: SideFX Modulator", device_path, mod_idx)
end

--- Parse modulator index from name (M{n}).
-- @param name string Name to parse
-- @return number|nil Modulator index or nil
function M.parse_modulator_index(name)
    if not name then return nil end
    local idx = name:match("_M(%d+)")
    return idx and tonumber(idx) or nil
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
