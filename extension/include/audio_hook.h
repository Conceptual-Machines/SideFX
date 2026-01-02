#pragma once

namespace sidefx {

// Initialize the audio hook (call on plugin load)
void initAudioHook();

// Cleanup the audio hook (call on plugin unload)
void cleanupAudioHook();

// Check if audio hook is running
bool isAudioHookActive();

} // namespace sidefx

