#pragma once

#include "reaper_plugin.h"
#include <string>

namespace sidefx {

//------------------------------------------------------------------------------
// SideFX Main Window
// ImGui-based window for FX chain management and modulation
//------------------------------------------------------------------------------

class SideFXWindow {
public:
    SideFXWindow();
    ~SideFXWindow();

    // Initialize ReaImGui function pointers
    bool Initialize(reaper_plugin_info_t* rec);

    // Check if ReaImGui is available
    bool IsAvailable() const { return m_available; }

    // Show/hide window
    void Show();
    void Hide();
    bool IsVisible() const { return m_visible; }
    void Toggle();

    // Main render loop - call from timer callback
    void Render();

private:
    // Try to initialize ReaImGui (lazy initialization)
    bool TryInitReaImGui();
    
    // Apply theme colors
    void ApplyTheme();
    void PopTheme();

    // Render sections
    void RenderHeader();
    void RenderTrackInfo();
    void RenderFXChain();
    void RenderModulatorPanel();
    void RenderStatusBar();

    // State
    bool m_available = false;
    bool m_visible = false;
    bool m_reaimguiInitialized = false;
    void* m_ctx = nullptr;
    int m_themeColorCount = 0;

    // REAPER function pointers we need
    MediaTrack* (*m_GetSelectedTrack)(ReaProject* proj, int seltrackidx) = nullptr;
    bool (*m_GetTrackName)(MediaTrack* track, char* buf, int buf_sz) = nullptr;
    int (*m_GetMediaTrackInfo_Value)(MediaTrack* tr, const char* parmname) = nullptr;
    int (*m_TrackFX_GetCount)(MediaTrack* track) = nullptr;
    bool (*m_TrackFX_GetFXName)(MediaTrack* track, int fx, char* buf, int buf_sz) = nullptr;
    bool (*m_TrackFX_GetEnabled)(MediaTrack* track, int fx) = nullptr;
    void (*m_ShowConsoleMsg)(const char* msg) = nullptr;
};

// Global instance
extern SideFXWindow* g_sideFXWindow;

} // namespace sidefx

