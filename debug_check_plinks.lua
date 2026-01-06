-- Debug script to check existing parameter links
-- Run this after manually creating a working link in REAPER
-- Actions -> ReaScript -> Load ReaScript -> select this file -> Run

local r = reaper
local track = r.GetSelectedTrack(0, 0)
if not track then
  r.ShowConsoleMsg("No track selected\n")
  return
end

r.ShowConsoleMsg("=== Checking all FX for parameter links ===\n")

-- Function to check an FX for plinks
local function check_fx(fx_idx)
  local _, fx_name = r.TrackFX_GetFXName(track, fx_idx, "")
  if not _ then return end  -- FX doesn't exist

  local param_count = r.TrackFX_GetNumParams(track, fx_idx)

  for p = 0, param_count - 1 do
    local _, active = r.TrackFX_GetNamedConfigParm(track, fx_idx, string.format("param.%d.plink.active", p))
    if active == "1" then
      local _, effect = r.TrackFX_GetNamedConfigParm(track, fx_idx, string.format("param.%d.plink.effect", p))
      local _, param = r.TrackFX_GetNamedConfigParm(track, fx_idx, string.format("param.%d.plink.param", p))
      local _, pname = r.TrackFX_GetParamName(track, fx_idx, p, "")

      r.ShowConsoleMsg(string.format("\nFX %d (%s) param %d (%s):\n", fx_idx, fx_name, p, pname))
      r.ShowConsoleMsg(string.format("  plink.effect=%s\n", effect))
      r.ShowConsoleMsg(string.format("  plink.param=%s\n", param))

      -- Try to get the source FX name
      local source_fx_idx = tonumber(effect)
      if source_fx_idx then
        local _, source_name = r.TrackFX_GetFXName(track, source_fx_idx, "")
        if _ then
          local _, source_pname = r.TrackFX_GetParamName(track, source_fx_idx, tonumber(param) or 0, "")
          r.ShowConsoleMsg(string.format("  Source: FX %d (%s) param %s (%s)\n", source_fx_idx, source_name, param, source_pname or "?"))
        end
      end
    end
  end
end

-- Check top-level FX
local fx_count = r.TrackFX_GetCount(track)
r.ShowConsoleMsg(string.format("Top-level FX count: %d\n", fx_count))

for fx_idx = 0, fx_count - 1 do
  check_fx(fx_idx)
end

-- Check common encoded indices for nested FX
r.ShowConsoleMsg("\n=== Checking encoded indices for nested FX ===\n")
local encoded_to_check = {
  0x02000000 + 0,  -- First container, first child
  0x02000000 + 1,  -- First container, second child
  0x02000000 + 2,  -- First container, third child
  0x02000000 + 3,  -- First container, fourth child
  0x02000000 + 4,  -- First container, fifth child
  0x02000000 + 5,  -- First container, sixth child
}

for _, idx in ipairs(encoded_to_check) do
  check_fx(idx)
end

r.ShowConsoleMsg("\n=== Done ===\n")
