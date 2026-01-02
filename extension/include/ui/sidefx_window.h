#pragma once

#include "reaper_plugin.h"
#include "reaimgui_api.h"
#include <vector>
#include <string>
#include <set>

namespace sidefx {

// Plugin info structure
struct PluginInfo {
    std::string name;
    std::string fullName;     // Full identifier for TrackFX_AddByName
    std::string type;         // "VST", "VST3", "AU", "JS", etc.
    std::string manufacturer;
    bool isInstrument = false;
};

// FX info for display
struct FXInfo {
    int index;
    std::string name;
    std::string displayName;
    bool enabled;
    bool isContainer;
    int containerCount;       // Number of FX in container
    int parentContainer;      // Parent container index (-1 if none)
};

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
    void RenderPluginBrowser();
    void RenderFXChainColumn(int depth, int parentFxIndex);
    void RenderFXItem(MediaTrack* track, int fxIndex, int depth);
    void RenderDetailPanel();
    void RenderModulatorPanel();
    void RenderStatusBar();
    
    // Plugin scanning
    void ScanPlugins();
    void FilterPlugins();
    void AddPluginToTrack(const PluginInfo& plugin);
    
    // FX helpers
    void RefreshFXList();
    std::vector<int> GetContainerChildren(MediaTrack* track, int containerIdx);
    bool IsContainerExpanded(int fxIndex);
    void ToggleContainerExpanded(int fxIndex);
    void CollapseFromDepth(int depth);
    
    // State
    bool m_visible = false;
    bool m_available = false;
    bool m_reaimguiInitialized = false;
    void* m_ctx = nullptr;
    int m_themeColorCount = 0;
    
    // Browser state
    bool m_browserVisible = true;
    char m_searchBuffer[256] = {0};
    int m_filterMode = 0;  // 0=All, 1=Instruments, 2=Effects
    std::vector<PluginInfo> m_allPlugins;
    std::vector<PluginInfo> m_filteredPlugins;
    bool m_pluginsScanned = false;
    
    // FX chain state
    std::vector<int> m_expandedContainers;  // Breadcrumb trail of expanded container indices
    int m_selectedFX = -1;                   // Currently selected FX for detail panel
    std::set<int> m_multiSelect;             // Multi-selected FX indices
    
    // Drag & drop state
    int m_draggingFX = -1;
    std::string m_draggingPlugin;
    
    // Track change detection
    MediaTrack* m_lastTrack = nullptr;
    int m_lastFXCount = 0;

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
