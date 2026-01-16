-- Debug script to explore all plink parameters
local track = reaper.GetSelectedTrack(0, 0)
if not track then
  reaper.ShowConsoleMsg("No track selected\n")
  return
end

local fx_count = reaper.TrackFX_GetCount(track)
reaper.ShowConsoleMsg(string.format("Track has %d FX\n", fx_count))

for fx = 0, fx_count - 1 do
  local _, fx_name = reaper.TrackFX_GetFXName(track, fx, "")
  local param_count = reaper.TrackFX_GetNumParams(track, fx)

  for p = 0, param_count - 1 do
    -- Check if this param has a plink
    local plink_prefix = string.format("param.%d.plink.", p)
    local _, active = reaper.TrackFX_GetNamedConfigParm(track, fx, plink_prefix .. "active")

    if active == "1" then
      reaper.ShowConsoleMsg(string.format("\n=== %s param %d has plink ===\n", fx_name, p))

      -- Try all possible plink parameters
      local plink_params = {
        "active", "effect", "param", "scale", "offset",
        "bypass", "enable", "disabled", "mute", "on", "enabled",
        "midi_bus", "midi_chan", "midi_msg", "midi_msg2"
      }

      for _, param_name in ipairs(plink_params) do
        local ok, val = reaper.TrackFX_GetNamedConfigParm(track, fx, plink_prefix .. param_name)
        if ok then
          reaper.ShowConsoleMsg(string.format("  %s%s = %s\n", plink_prefix, param_name, val))
        end
      end

      -- Also check mod. prefix
      local mod_prefix = string.format("param.%d.mod.", p)
      local mod_params = {"baseline", "visible", "bypass", "enable", "active"}
      for _, param_name in ipairs(mod_params) do
        local ok, val = reaper.TrackFX_GetNamedConfigParm(track, fx, mod_prefix .. param_name)
        if ok then
          reaper.ShowConsoleMsg(string.format("  %s%s = %s\n", mod_prefix, param_name, val))
        end
      end
    end
  end
end

reaper.ShowConsoleMsg("\nDone.\n")
