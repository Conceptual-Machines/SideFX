--- Constants
-- Shared constants for SideFX
-- @module constants
-- @author Nomad Monad
-- @license MIT

local M = {}

--------------------------------------------------------------------------------
-- Icons (legacy - use lib.ui.common.icons module instead)
--------------------------------------------------------------------------------

-- These are kept for backwards compatibility but are no longer used.
-- Use the icons module (lib.ui.common.icons) for PNG-based icons.
M.Icons = {
    folder_open = "folder-open",
    folder_closed = "folder-closed",
    plug = "plug",
    musical_keyboard = "keyboard",
    control_knobs = "knobs",
    wrench = "wrench",
    speaker_high = "speaker-on",
    speaker_muted = "speaker-muted",
    arrows_counterclockwise = "refresh",
    floppy_disk = "save",
    gear = "gear",
    lock_closed = "lock-closed",
    lock_open = "lock-open",
}

return M
