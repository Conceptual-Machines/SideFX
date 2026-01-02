-- Quick API existence test
reaper.ShowConsoleMsg("\n=== API Existence Test ===\n")

-- Check if function exists directly
if reaper.SideFX_Mod_Create then
    reaper.ShowConsoleMsg("FOUND: reaper.SideFX_Mod_Create\n")
else
    reaper.ShowConsoleMsg("NOT FOUND: reaper.SideFX_Mod_Create\n")
end

-- Also try APIExists
local exists = reaper.APIExists("SideFX_Mod_Create")
reaper.ShowConsoleMsg("APIExists('SideFX_Mod_Create'): " .. tostring(exists) .. "\n")

-- List all SideFX functions if any
reaper.ShowConsoleMsg("\nSearching for any SideFX functions...\n")
local count = 0
for k, v in pairs(reaper) do
    if type(k) == "string" and k:find("SideFX") then
        reaper.ShowConsoleMsg("  Found: reaper." .. k .. "\n")
        count = count + 1
    end
end
reaper.ShowConsoleMsg("Total SideFX functions found: " .. count .. "\n")

