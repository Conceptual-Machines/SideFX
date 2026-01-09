local r = reaper
local track = r.GetSelectedTrack(0, 0)
if not track then print("No track selected") return end

-- Find first modulator
local fx_count = r.TrackFX_GetCount(track)
for i = 0, fx_count - 1 do
    local _, name = r.TrackFX_GetFXName(track, i, "")
    if name:match("SideFX_Modulator") then
        print("Found modulator at index: " .. i)
        print("Slider 1 (Tempo Mode - param 0): " .. r.TrackFX_GetParam(track, i, 0))
        print("Slider 2 (Rate Hz - param 1): " .. r.TrackFX_GetParam(track, i, 1))
        print("Slider 3 (Sync Rate - param 2): " .. r.TrackFX_GetParam(track, i, 2))
        print("Normalized param 1: " .. r.TrackFX_GetParamNormalized(track, i, 1))
        break
    end
end
