--- Configuration Management
-- Global persistent configuration for SideFX
-- Uses JSON storage via REAPER ExtState (global, not per-project)
-- @module core.config
-- @author Nomad Monad
-- @license MIT

local r = reaper
local json = require('lib.utils.json')

local M = {}

-- Config version for future migrations
local CONFIG_VERSION = 1

-- ExtState section name
local EXT_STATE_SECTION = "SideFX"
local EXT_STATE_KEY = "GlobalConfig"

--- Default configuration values
local defaults = {
    version = CONFIG_VERSION,

    -- Display settings
    show_track_name = true,
    show_breadcrumbs = true,
    show_mix_delta = true,  -- Show mix knob and delta button together
    show_phase_controls = true,
    icon_font_size = 1,  -- 0=Small, 1=Medium, 2=Large
    max_visible_params = 64,

    -- Behavior settings
    auto_refresh = true,
    remember_window_pos = true,

    -- Gain staging settings
    gain_target_db = -12.0,
    gain_tolerance_db = 1.0,

    -- Bake settings
    bake_disable_link_after = true,   -- Disable link (set scale=0) after baking
    bake_default_range_mode = 2,      -- Default range: 1=Project, 2=Track, 3=Time Sel, 4=Selected Item
    bake_show_range_picker = true,    -- Show range picker modal (false = use default directly)

    -- Paths (nil = use defaults)
    presets_folder = nil,  -- nil = [Resource Path]/presets/SideFX_Presets/
}

-- Current config (loaded from storage or defaults)
local config = {}

--------------------------------------------------------------------------------
-- Getters
--------------------------------------------------------------------------------

--- Get a config value with fallback to default
-- @param key string Config key
-- @return any Config value or default
function M.get(key)
    if config[key] ~= nil then
        return config[key]
    end
    return defaults[key]
end

--- Get all config as table (copy)
-- @return table Copy of current config merged with defaults
function M.get_all()
    local result = {}
    for k, v in pairs(defaults) do
        result[k] = v
    end
    for k, v in pairs(config) do
        result[k] = v
    end
    return result
end

--- Get the user's home directory (cross-platform)
-- @return string Home directory path
local function get_home_dir()
    -- Try HOME (macOS/Linux) first, then USERPROFILE (Windows)
    local home = os.getenv("HOME") or os.getenv("USERPROFILE")
    if home then
        return home
    end
    -- Fallback to REAPER resource path if no home found
    return r.GetResourcePath()
end

--- Get the presets folder path
-- Returns configured path or default (user's Documents/SideFX_Presets)
-- @return string Presets folder path (with trailing slash)
function M.get_presets_folder()
    local folder = config.presets_folder
    if folder and folder ~= "" then
        -- Ensure trailing slash
        if not folder:match("[/\\]$") then
            folder = folder .. "/"
        end
        return folder
    end
    -- Default path in user's Documents folder
    local home = get_home_dir()
    local sep = package.config:sub(1, 1)  -- "/" on Unix, "\" on Windows
    return home .. sep .. "Documents" .. sep .. "SideFX_Presets" .. sep
end

--------------------------------------------------------------------------------
-- Setters
--------------------------------------------------------------------------------

--- Set a config value and save
-- @param key string Config key
-- @param value any Config value
function M.set(key, value)
    config[key] = value
    M.save()
end

--- Set multiple config values and save once
-- @param values table Key-value pairs to set
function M.set_many(values)
    for k, v in pairs(values) do
        config[k] = v
    end
    M.save()
end

--- Reset a config value to default
-- @param key string Config key
function M.reset(key)
    config[key] = nil
    M.save()
end

--- Reset all config to defaults
function M.reset_all()
    config = {}
    M.save()
end

--------------------------------------------------------------------------------
-- Persistence
--------------------------------------------------------------------------------

--- Save config to ExtState
function M.save()
    -- Merge with defaults for complete config
    local to_save = {}
    for k, v in pairs(defaults) do
        to_save[k] = v
    end
    for k, v in pairs(config) do
        to_save[k] = v
    end
    to_save.version = CONFIG_VERSION

    local json_str = json.encode(to_save)
    -- Use SetExtState with persist=true for global storage
    r.SetExtState(EXT_STATE_SECTION, EXT_STATE_KEY, json_str, true)
end

--- Load config from ExtState
function M.load()
    local json_str = r.GetExtState(EXT_STATE_SECTION, EXT_STATE_KEY)
    if json_str and json_str ~= "" then
        local parsed = json.decode(json_str)
        if parsed then
            -- Handle version migrations here if needed (placeholder for future use)
            -- local version = parsed.version or 0
            config = parsed
        end
    end
end

--- Initialize config system (call once at startup)
function M.init()
    M.load()
end

--------------------------------------------------------------------------------
-- Utilities
--------------------------------------------------------------------------------

--- Check if a custom presets folder is set
-- @return boolean True if custom folder is configured
function M.has_custom_presets_folder()
    return config.presets_folder ~= nil and config.presets_folder ~= ""
end

--- Get default presets folder path
-- @return string Default presets folder path
function M.get_default_presets_folder()
    local home = get_home_dir()
    local sep = package.config:sub(1, 1)
    return home .. sep .. "Documents" .. sep .. "SideFX_Presets" .. sep
end

return M
