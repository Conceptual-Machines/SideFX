--- SideFX Track Detection Utilities.
-- Pure functions for detecting SideFX tracks from FX names.
-- These functions are stateless and testable standalone.
-- @module track_detection
-- @author Nomad Monad
-- @license MIT

local M = {}

--------------------------------------------------------------------------------
-- FX Name Detection
--------------------------------------------------------------------------------

--- Check if an FX name indicates a SideFX JSFX plugin.
-- @param fx_name string FX name
-- @return boolean True if name contains SideFX JSFX markers
function M.is_sidefx_jsfx(fx_name)
    if not fx_name then return false end
    local name_lower = fx_name:lower()
    return name_lower:find("sidefx_mixer") ~= nil or
           name_lower:find("sidefx_utility") ~= nil or
           name_lower:find("sidefx_modulator") ~= nil
end

--- Check if an FX name matches SideFX container naming patterns.
-- @param fx_name string FX name
-- @return boolean True if name matches R{n}, C{n}, or D{n} patterns
function M.is_sidefx_container_name(fx_name)
    if not fx_name then return false end
    return fx_name:match("^R%d+") ~= nil or
           fx_name:match("^C%d+") ~= nil or
           fx_name:match("^D%d+") ~= nil
end

--- Check if an FX name indicates a SideFX structure.
-- @param fx_name string FX name
-- @return boolean True if name indicates SideFX
function M.is_sidefx_fx_name(fx_name)
    if not fx_name then return false end
    return M.is_sidefx_jsfx(fx_name) or M.is_sidefx_container_name(fx_name)
end

--- Scan a list of FX names to determine if track is SideFX.
-- @param fx_names table Array of FX names (strings)
-- @return boolean True if any FX name indicates SideFX
function M.scan_fx_names_for_sidefx(fx_names)
    if not fx_names or type(fx_names) ~= "table" then
        return false
    end
    
    for _, fx_name in ipairs(fx_names) do
        if M.is_sidefx_fx_name(fx_name) then
            return true
        end
    end
    
    return false
end

return M
