--- Constants
-- Shared constants for SideFX (icons, etc.)
-- @module constants
-- @author Nomad Monad
-- @license MIT

local M = {}

--------------------------------------------------------------------------------
-- Icons (using OpenMoji font)
--------------------------------------------------------------------------------

M.Icons = {
    folder_open = "1F4C2",      -- 📂
    folder_closed = "1F4C1",    -- 📁
    package = "1F4E6",          -- 📦
    plug = "1F50C",             -- 🔌
    musical_keyboard = "1F3B9", -- 🎹
    wrench = "1F527",           -- 🔧
    speaker_high = "1F50A",     -- 🔊
    speaker_muted = "1F507",    -- 🔇
    arrows_counterclockwise = "1F504", -- 🔄
}

--- Get icon text from EmojImGui
-- @param emojimgui EmojImGui module
-- @param icon_id string Icon ID from Icons table
-- @return string UTF-8 character for the icon
function M.icon_text(emojimgui, icon_id)
    local info = emojimgui.Asset.CharInfo("OpenMoji", icon_id)
    return info and info.utf8 or "?"
end

return M

