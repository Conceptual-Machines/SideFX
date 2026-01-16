--- Icon Loader
-- Loads and caches PNG icons for use with ReaImGui
-- @module ui.icons
-- @author Nomad Monad
-- @license MIT

local r = reaper

local M = {}

-- Icon cache: { [icon_name] = ImGui_Image }
local icon_cache = {}

-- Context the icons are attached to (for lifecycle management)
local attached_ctx = nil

-- Path to icons directory (relative to script)
local icons_path = nil

--------------------------------------------------------------------------------
-- Icon Names
--------------------------------------------------------------------------------

--- Available icon names (matches PNG filenames without extension)
M.Names = {
    -- Device/FX
    wrench = "wrench",
    gear = "gear",
    plug = "plug",
    keyboard = "keyboard",
    knobs = "knobs",
    rack = "rack",
    chain = "chain",

    -- Files/Folders
    save = "save",
    folder_open = "folder-open",
    folder_closed = "folder-closed",

    -- Playback/Transport
    refresh = "refresh",
    loop = "loop",
    oneshot = "oneshot",
    pause = "pause",
    popout = "pop-out",

    -- Audio
    speaker_on = "speaker-on",
    speaker_muted = "speaker-muted",
    spectrum = "spectrum",
    oscilloscope = "oscilloscope",
    multiband = "multiband",

    -- LFO/Modulation
    sync = "sync",
    free = "free",
    curve = "curve",

    -- State
    lock_closed = "lock-closed",
    lock_open = "lock-open",
    on = "on",
    cancel = "cancel",

    -- Modulation
    matrix = "matrix",
}

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

--- Initialize the icon loader with the script path
-- Must be called once before using icons
-- @param script_path string Path to the SideFX script directory
function M.init(script_path)
    icons_path = script_path .. "assets/icons/"
end

--------------------------------------------------------------------------------
-- Icon Loading
--------------------------------------------------------------------------------

--- Load an icon by name
-- @param name string Icon name (from M.Names or raw filename without .png)
-- @return ImGui_Image|nil The loaded image, or nil if failed
local function load_icon(name)
    if not icons_path then
        error("Icons not initialized. Call icons.init(script_path) first.")
    end

    local path = icons_path .. name .. ".png"
    local img = r.ImGui_CreateImage(path)
    if img then
        return img
    else
        return nil
    end
end

--- Get an icon, loading it if necessary
-- @param name string Icon name (from M.Names or raw filename without .png)
-- @return ImGui_Image|nil The image, or nil if not found
function M.get(name)
    -- Check cache first
    if icon_cache[name] then
        return icon_cache[name]
    end

    -- Load and cache
    local img = load_icon(name)
    if img then
        icon_cache[name] = img
    end
    return img
end

--- Attach all loaded icons to a context for lifecycle management
-- Call this once per context to prevent icons from being garbage collected
-- @param ctx ImGui_Context The context to attach icons to
function M.attach(ctx)
    if attached_ctx == ctx then
        return -- Already attached to this context
    end

    for name, img in pairs(icon_cache) do
        r.ImGui_Attach(ctx, img)
    end
    attached_ctx = ctx
end

--- Preload all icons and attach to context
-- Call this during initialization for best performance
-- @param ctx ImGui_Context The context to attach icons to
function M.preload_all(ctx)
    for _, name in pairs(M.Names) do
        local img = M.get(name)
        if img then
            r.ImGui_Attach(ctx, img)
        end
    end
    attached_ctx = ctx
end

--------------------------------------------------------------------------------
-- Icon Button Helpers
--------------------------------------------------------------------------------

--- Draw an icon button
-- @param ctx ImGui context (ReaWrap wrapper)
-- @param str_id string Unique ID for the button
-- @param icon_name string Icon name (from M.Names)
-- @param size number Icon size (default: 16)
-- @param tint_color number|nil Optional RGBA tint color (default: 0xCCCCCCFF)
-- @return boolean True if clicked
function M.button(ctx, str_id, icon_name, size, tint_color)
    size = size or 16
    tint_color = tint_color or 0xCCCCCCFF

    local img = M.get(icon_name)
    if not img then
        -- Fallback to text button if icon not found
        return ctx:button("?" .. "##" .. str_id, size, size)
    end

    -- Use raw ReaImGui API (ctx.ctx is the raw context)
    local raw_ctx = ctx.ctx or ctx

    -- Fully transparent background - push all relevant color styles
    r.ImGui_PushStyleVar(raw_ctx, r.ImGui_StyleVar_FramePadding(), 0, 0)
    r.ImGui_PushStyleVar(raw_ctx, r.ImGui_StyleVar_FrameBorderSize(), 0)
    r.ImGui_PushStyleColor(raw_ctx, r.ImGui_Col_Button(), 0x00000000)
    r.ImGui_PushStyleColor(raw_ctx, r.ImGui_Col_ButtonHovered(), 0xFFFFFF22)
    r.ImGui_PushStyleColor(raw_ctx, r.ImGui_Col_ButtonActive(), 0xFFFFFF44)
    r.ImGui_PushStyleColor(raw_ctx, r.ImGui_Col_FrameBg(), 0x00000000)
    r.ImGui_PushStyleColor(raw_ctx, r.ImGui_Col_Border(), 0x00000000)
    local clicked = r.ImGui_ImageButton(raw_ctx, str_id, img, size, size, 0, 0, 1, 1, 0x00000000, tint_color)
    r.ImGui_PopStyleColor(raw_ctx, 5)
    r.ImGui_PopStyleVar(raw_ctx, 2)

    return clicked
end

--- Draw an icon button with a subtle border/background
-- @param ctx ImGui context (ReaWrap wrapper)
-- @param str_id string Unique ID for the button
-- @param icon_name string Icon name (from M.Names)
-- @param size number Total button size including padding (default: 22)
-- @param tint_color number|nil Optional RGBA tint color (default: 0xCCCCCCFF)
-- @param bg_color number|nil Optional RGBA background color (default: 0x333333FF)
-- @return boolean True if clicked
function M.button_bordered(ctx, str_id, icon_name, size, tint_color, bg_color)
    size = size or 22
    tint_color = tint_color or 0xCCCCCCFF
    bg_color = bg_color or 0x333333FF

    local padding = 2
    local icon_size = size - (padding * 2)  -- Icon size = total size minus padding

    local img = M.get(icon_name)
    if not img then
        return ctx:button("?" .. "##" .. str_id, size, size)
    end

    local raw_ctx = ctx.ctx or ctx

    -- Subtle background with border
    r.ImGui_PushStyleVar(raw_ctx, r.ImGui_StyleVar_FramePadding(), padding, padding)
    r.ImGui_PushStyleVar(raw_ctx, r.ImGui_StyleVar_FrameRounding(), 3)
    r.ImGui_PushStyleVar(raw_ctx, r.ImGui_StyleVar_FrameBorderSize(), 1)
    r.ImGui_PushStyleColor(raw_ctx, r.ImGui_Col_Button(), bg_color)
    r.ImGui_PushStyleColor(raw_ctx, r.ImGui_Col_ButtonHovered(), 0x444444FF)
    r.ImGui_PushStyleColor(raw_ctx, r.ImGui_Col_ButtonActive(), 0x555555FF)
    r.ImGui_PushStyleColor(raw_ctx, r.ImGui_Col_Border(), 0x555555FF)
    local clicked = r.ImGui_ImageButton(raw_ctx, str_id, img, icon_size, icon_size, 0, 0, 1, 1, 0x00000000, tint_color)
    r.ImGui_PopStyleColor(raw_ctx, 4)
    r.ImGui_PopStyleVar(raw_ctx, 3)

    return clicked
end

-- Counter for unique image IDs
local image_counter = 0

--- Draw an icon (non-interactive, but uses ImageButton for tinting support)
-- @param ctx ImGui context (ReaWrap wrapper)
-- @param icon_name string Icon name (from M.Names)
-- @param size number Icon size (default: 16)
-- @param tint_color number|nil Optional RGBA tint color (default: 0xCCCCCCFF)
function M.image(ctx, icon_name, size, tint_color)
    size = size or 16
    tint_color = tint_color or 0xCCCCCCFF

    local img = M.get(icon_name)
    if not img then
        ctx:text("?")
        return
    end

    -- Use ImageButton with transparent background for tinting support
    -- The click result is ignored since this is meant for display only
    local raw_ctx = ctx.ctx or ctx

    -- Generate unique ID for each image
    image_counter = image_counter + 1
    local unique_id = "##img_" .. icon_name .. "_" .. image_counter

    -- Remove all padding/border for display-only icons
    r.ImGui_PushStyleVar(raw_ctx, r.ImGui_StyleVar_FramePadding(), 0, 0)
    r.ImGui_PushStyleColor(raw_ctx, r.ImGui_Col_Button(), 0x00000000)
    r.ImGui_PushStyleColor(raw_ctx, r.ImGui_Col_ButtonHovered(), 0x00000000)
    r.ImGui_PushStyleColor(raw_ctx, r.ImGui_Col_ButtonActive(), 0x00000000)
    r.ImGui_ImageButton(raw_ctx, unique_id, img, size, size, 0, 0, 1, 1, 0x00000000, tint_color)
    r.ImGui_PopStyleColor(raw_ctx, 3)
    r.ImGui_PopStyleVar(raw_ctx)
end

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------

--- Clear the icon cache
-- Call this if you need to reload icons (e.g., after changing icon files)
function M.clear_cache()
    icon_cache = {}
    attached_ctx = nil
end

return M
