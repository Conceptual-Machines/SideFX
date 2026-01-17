-- Debug script to explore ALL MIDI source/loop APIs
local item = reaper.GetSelectedMediaItem(0, 0)
if not item then
  reaper.ShowConsoleMsg("No item selected\n")
  return
end

local take = reaper.GetActiveTake(item)
if not take or not reaper.TakeIsMIDI(take) then
  reaper.ShowConsoleMsg("Not a MIDI item\n")
  return
end

local source = reaper.GetMediaItemTake_Source(take)
local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

reaper.ShowConsoleMsg("=== MIDI Source Properties ===\n")

-- GetMediaSourceLength with different lengthIsQN values
local src_len_sec = reaper.GetMediaSourceLength(source)
local src_len_qn, is_qn = reaper.GetMediaSourceLength(source)  -- Second return is whether it's in QN
reaper.ShowConsoleMsg(string.format("GetMediaSourceLength: %.3f (isQN=%s)\n", src_len_sec, tostring(is_qn)))

-- Try GetMediaSourceType
local src_type = reaper.GetMediaSourceType(source, "")
reaper.ShowConsoleMsg(string.format("GetMediaSourceType: %s\n", src_type or "nil"))

-- Try GetMediaSourceNumChannels
local num_ch = reaper.GetMediaSourceNumChannels(source)
reaper.ShowConsoleMsg(string.format("GetMediaSourceNumChannels: %d\n", num_ch or 0))

-- Try PCM_Source_GetSectionInfo (might work for MIDI sections)
local is_section, ofs, len, rev = reaper.PCM_Source_GetSectionInfo(source)
reaper.ShowConsoleMsg(string.format("PCM_Source_GetSectionInfo: section=%s ofs=%.3f len=%.3f rev=%s\n",
  tostring(is_section), ofs or 0, len or 0, tostring(rev)))

-- Item info values
reaper.ShowConsoleMsg("\n=== Item Info Values ===\n")
local item_props = {"D_POSITION", "D_LENGTH", "D_SNAPOFFSET", "B_LOOPSRC", "D_FADEINLEN", "D_FADEOUTLEN"}
for _, prop in ipairs(item_props) do
  local val = reaper.GetMediaItemInfo_Value(item, prop)
  reaper.ShowConsoleMsg(string.format("  %s = %.4f\n", prop, val))
end

-- Take info values
reaper.ShowConsoleMsg("\n=== Take Info Values ===\n")
local take_props = {"D_STARTOFFS", "D_VOL", "D_PAN", "D_PLAYRATE", "D_PITCH", "I_PITCHMODE"}
for _, prop in ipairs(take_props) do
  local val = reaper.GetMediaItemTakeInfo_Value(take, prop)
  reaper.ShowConsoleMsg(string.format("  %s = %.4f\n", prop, val))
end

-- MIDI specific
reaper.ShowConsoleMsg("\n=== MIDI Info ===\n")
local _, note_count, cc_count, text_count = reaper.MIDI_CountEvts(take)
reaper.ShowConsoleMsg(string.format("Events: notes=%d cc=%d text=%d\n", note_count, cc_count, text_count))

-- Get PPQ info
local ppq_per_qn = reaper.MIDI_GetPPQPosFromProjQN(take, 1) - reaper.MIDI_GetPPQPosFromProjQN(take, 0)
reaper.ShowConsoleMsg(string.format("PPQ per QN: %.0f\n", ppq_per_qn))

-- Get the PPQ range of all events
local all_ok, midi_str = reaper.MIDI_GetAllEvts(take)
if all_ok then
  local str_len = #midi_str
  reaper.ShowConsoleMsg(string.format("MIDI data length: %d bytes\n", str_len))
end

-- Check MIDI hash (changes when content changes)
local hash_ok, hash = reaper.MIDI_GetHash(take, false, "")
reaper.ShowConsoleMsg(string.format("MIDI hash: %s\n", hash or "nil"))

-- Try to find the end PPQ from the raw events
local max_ppq = 0
for n = 0, note_count - 1 do
  local _, _, _, start_ppq, end_ppq = reaper.MIDI_GetNote(take, n)
  if end_ppq > max_ppq then max_ppq = end_ppq end
end
for c = 0, cc_count - 1 do
  local _, _, _, cc_ppq = reaper.MIDI_GetCC(take, c)
  if cc_ppq > max_ppq then max_ppq = cc_ppq end
end

reaper.ShowConsoleMsg(string.format("\nMax event PPQ: %.0f\n", max_ppq))
local max_qn = reaper.MIDI_GetProjQNFromPPQPos(take, max_ppq)
reaper.ShowConsoleMsg(string.format("Max event QN: %.3f (= %.3f bars at 4/4)\n", max_qn, max_qn / 4))

-- Convert to time
local max_time = reaper.MIDI_GetProjTimeFromPPQPos(take, max_ppq) - item_pos
reaper.ShowConsoleMsg(string.format("Max event time (relative): %.3f sec\n", max_time))

-- Check if there's a MIDI source section
reaper.ShowConsoleMsg("\n=== Named Config Params (Take) ===\n")
-- Try some common named params
local named_params = {"GUID", "POOLEDEVTS"}
for _, param in ipairs(named_params) do
  local ok, val = reaper.GetSetMediaItemTakeInfo_String(take, "P_" .. param, "", false)
  if ok then
    reaper.ShowConsoleMsg(string.format("  P_%s = %s\n", param, val:sub(1, 50)))
  end
end
