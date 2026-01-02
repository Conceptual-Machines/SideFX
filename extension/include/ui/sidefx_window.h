#pragma once

#include "reaper_plugin.h"
#include "reaimgui_api.h"

namespace sidefx {

class SideFXWindow {
public:
    SideFXWindow();
    ~SideFXWindow();

    // Initialize with REAPER API
    bool Initialize(reaper_plugin_info_t* rec);

    // Try to init ReaImGui (lazy)
    bool TryInitReaImGui();

    // Window visibility control
    void Show();
    void Hide();
    void Toggle();
    bool IsVisible() const { return m_visible; }
    bool IsAvailable() const { return m_available; }

    // Main render function (call from timer)
    void Render();

private:
    // Theming
    void ApplyTheme();
    void PopTheme();
    
    // UI Panels
    void RenderToolbar();
    void RenderFXChain();
    void RenderFXItem(MediaTrack* track, int fxIndex);
    void RenderModulatorPanel();
    void RenderStatusBar();

    // State
    bool m_visible = false;
    bool m_available = false;
    bool m_reaimguiInitialized = false;
    void* m_ctx = nullptr;
    int m_themeColorCount = 0;

    // REAPER API function pointers
    MediaTrack* (*m_GetSelectedTrack)(ReaProject*, int) = nullptr;
    bool (*m_GetTrackName)(MediaTrack*, char*, int) = nullptr;
    int (*m_GetMediaTrackInfo_Value)(MediaTrack*, const char*) = nullptr;
    int (*m_TrackFX_GetCount)(MediaTrack*) = nullptr;
    bool (*m_TrackFX_GetFXName)(MediaTrack*, int, char*, int) = nullptr;
    bool (*m_TrackFX_GetEnabled)(MediaTrack*, int) = nullptr;
    void (*m_ShowConsoleMsg)(const char*) = nullptr;
};

// Global instance
extern SideFXWindow* g_sideFXWindow;

} // namespace sidefx
