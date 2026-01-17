-- Debug script to check MIDI item loop properties
local item = reaper.GetSelectedMediaItem(0, 0)
if item then
  local take = reaper.GetActiveTake(item)
  if take and reaper.TakeIsMIDI(take) then
    local source = reaper.GetMediaItemTake_Source(take)
    local src_len = reaper.GetMediaSourceLength(source)
    local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local loop_src = reaper.GetMediaItemInfo_Value(item, "B_LOOPSRC")
    local start_offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")

    reaper.ShowConsoleMsg("=== MIDI Item Loop Debug ===\n")
    reaper.ShowConsoleMsg(string.format("  item_pos=%.3f\n", item_pos))
    reaper.ShowConsoleMsg(string.format("  item_len=%.3f\n", item_len))
    reaper.ShowConsoleMsg(string.format("  src_len=%.3f\n", src_len))
    reaper.ShowConsoleMsg(string.format("  loop_enabled=%d\n", loop_src))
    reaper.ShowConsoleMsg(string.format("  start_offs=%.3f\n", start_offs))

    -- Check MIDI note count and positions
    local _, note_count = reaper.MIDI_CountEvts(take)
    reaper.ShowConsoleMsg(string.format("  note_count=%d\n", note_count))

    if note_count > 0 then
      reaper.ShowConsoleMsg("  Notes:\n")
      for n = 0, math.min(note_count - 1, 10) do  -- Show first 10 notes max
        local _, _, _, note_start_ppq, note_end_ppq, _, _, _ = reaper.MIDI_GetNote(take, n)
        local note_start_time = reaper.MIDI_GetProjTimeFromPPQPos(take, note_start_ppq)
        local note_end_time = reaper.MIDI_GetProjTimeFromPPQPos(take, note_end_ppq)
        reaper.ShowConsoleMsg(string.format("    Note %d: ppq=%.0f-%.0f time=%.3f-%.3f\n",
          n, note_start_ppq, note_end_ppq, note_start_time, note_end_time))
      end
    end
  else
    reaper.ShowConsoleMsg("Selected item is not a MIDI item\n")
  end
else
  reaper.ShowConsoleMsg("No item selected\n")
end
