-- FX Naming Utilities Module
-- Functions for managing FX display names and internal names

local M = {}

--- Get the internal REAPER name (with prefix)
-- @param fx FX object
-- @return string Internal name with prefix
function M.get_internal_name(fx)
    if not fx then return "" end
    local ok, renamed = pcall(function() return fx:get_named_config_param("renamed_name") end)
    if ok and renamed and renamed ~= "" then
        return renamed
    end
    local ok2, name = pcall(function() return fx:get_name() end)
    return ok2 and name or ""
end

--- Extract the SideFX prefix from a name (R1_C1:, D1:, R1:)
-- @param name string FX name
-- @return string Extracted prefix or empty string
function M.extract_prefix(name)
    local prefix = name:match("^(R%d+_C%d+:%s*)")
    if prefix then return prefix end
    prefix = name:match("^(D%d+:%s*)")
    if prefix then return prefix end
    prefix = name:match("^(R%d+:%s*)")
    if prefix then return prefix end
    return ""
end

--- Get display name for FX (custom name or stripped internal name)
-- @param fx FX object
-- @return string Display name
function M.get_display_name(fx)
    if not fx then return "Unknown" end

    -- Check for custom display name first (SideFX-only renaming)
    local ok_guid, guid = pcall(function() return fx:get_guid() end)
    if ok_guid and guid then
        local state_module = require('lib.core.state')
        local state = state_module.state
        if state.display_names[guid] then
            return state.display_names[guid]
        end
    end

    -- Fall back to internal name with prefixes stripped
    local name = M.get_internal_name(fx)

    -- Strip SideFX internal prefixes for clean UI display
    -- Patterns from most specific to least specific
    name = name:gsub("^R%d+_C%d+_D%d+_FX:%s*", "")  -- R1_C1_D1_FX: prefix
    name = name:gsub("^R%d+_C%d+_D%d+:%s*", "")     -- R1_C1_D1: prefix
    name = name:gsub("^R%d+_C%d+:%s*", "")          -- R1_C1: prefix
    name = name:gsub("^D%d+_FX:%s*", "")            -- D1_FX: prefix
    name = name:gsub("^D%d+:%s*", "")               -- D1: prefix
    name = name:gsub("^R%d+:%s*", "")               -- R1: prefix

    -- Strip common plugin format prefixes
    name = name:gsub("^VST3?: ", "")
    name = name:gsub("^AU: ", "")
    name = name:gsub("^JS: ", "")
    name = name:gsub("^CLAP: ", "")

    return name
end

--- Rename an FX while preserving its internal prefix
-- @param fx FX object
-- @param new_display_name string New display name
-- @return boolean Success
function M.rename_fx(fx, new_display_name)
    if not fx or not new_display_name then return false end
    local internal_name = M.get_internal_name(fx)
    local prefix = M.extract_prefix(internal_name)
    local new_internal_name = prefix .. new_display_name
    local ok = pcall(function()
        fx:set_named_config_param("renamed_name", new_internal_name)
    end)
    return ok
end

--- Truncate string to max length with ellipsis
-- @param str string Input string
-- @param max_len number Maximum length
-- @return string Truncated string
function M.truncate(str, max_len)
    if #str <= max_len then return str end
    return str:sub(1, max_len - 2) .. ".."
end

--- Get short display name for path identifiers (UI only, strips parent prefix)
-- Converts hierarchical path names to local names for cleaner UI display
-- Examples: R1_C1 -> C1, R1_C1_D1 -> D1, R2 -> R2
-- Backend naming unchanged - this is purely for display
-- @param full_path string Full hierarchical path (e.g., "R1_C1", "R1_C1_D1")
-- @return string Short display path (e.g., "C1", "D1")
function M.get_short_path(full_path)
    if not full_path or full_path == "" then return "" end

    -- Match patterns to extract the last component:
    -- R\d+_C\d+_D\d+ -> D\d+ (device in chain)
    -- R\d+_C\d+_M\d+ -> M\d+ (modulator in chain)
    -- R\d+_C\d+ -> C\d+ (chain in rack)
    -- R\d+_D\d+ -> D\d+ (device in top-level rack - shouldn't happen but handle it)
    -- R\d+ -> R\d+ (rack itself - no change)

    -- Try to extract the last component after underscore
    local last_component = full_path:match("_([DCMR]%d+)$")
    if last_component then
        return last_component
    end

    -- No underscore means it's already a top-level name (R1, R2, etc.)
    return full_path
end

return M
