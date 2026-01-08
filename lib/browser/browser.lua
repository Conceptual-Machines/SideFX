--- SideFX Plugin Browser.
-- Plugin scanning and filtering for the browser panel.
-- @module browser
-- @author Nomad Monad
-- @license MIT

local Plugins = require('plugins')
local helpers = require('helpers')
local state_mod = require('lib.core.state')

local M = {}

--- Scan all plugins and populate the browser list.
-- Only scans once per session (checks state.browser.scanned flag).
function M.scan_plugins()
    local state = state_mod.state
    if state.browser.scanned then return end

    Plugins.scan()
    state.browser.plugins = {}
    for plugin in Plugins.iter_all() do
        state.browser.plugins[#state.browser.plugins + 1] = plugin
    end
    state.browser.filtered = state.browser.plugins
    state.browser.scanned = true
end

--- Filter plugins based on current search and filter settings.
-- Uses state.browser.search and state.browser.filter to filter.
-- Results are stored in state.browser.filtered.
function M.filter_plugins()
    local state = state_mod.state
    local search = state.browser.search:lower()
    local filter = state.browser.filter
    local results = {}

    local source = state.browser.plugins
    if filter == "instruments" then
        source = {}
        for plugin in Plugins.iter_instruments() do
            source[#source + 1] = plugin
        end
    elseif filter == "effects" then
        source = {}
        for plugin in Plugins.iter_effects() do
            source[#source + 1] = plugin
        end
    end

    for plugin in helpers.iter(source) do
        if search == "" then
            results[#results + 1] = plugin
        else
            local name_lower = plugin.name:lower()
            local mfr_lower = (plugin.manufacturer or ""):lower()
            if name_lower:find(search, 1, true) or mfr_lower:find(search, 1, true) then
                results[#results + 1] = plugin
            end
        end
    end

    state.browser.filtered = results
end

return M
