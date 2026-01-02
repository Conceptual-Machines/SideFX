#include "ui/sidefx_window.h"
#include "reaimgui_api.h"
#include "modulator.h"
#include <cstdio>
#include <cstring>
#include <vector>
#include <string>

namespace sidefx {

// Global instance
SideFXWindow* g_sideFXWindow = nullptr;

// Store rec for lazy initialization
static reaper_plugin_info_t* s_rec = nullptr;

// Additional REAPER API function pointers
static bool (*TrackFX_SetEnabled)(MediaTrack* track, int fx, bool enabled) = nullptr;
static double (*TrackFX_GetParamNormalized)(MediaTrack* track, int fx, int param) = nullptr;
static bool (*TrackFX_SetParamNormalized)(MediaTrack* track, int fx, int param, double value) = nullptr;
static int (*TrackFX_GetNumParams)(MediaTrack* track, int fx) = nullptr;
static bool (*TrackFX_GetParamName)(MediaTrack* track, int fx, int param, char* buf, int buf_sz) = nullptr;
static int (*TrackFX_GetParamFromIdent)(MediaTrack* track, int fx, const char* ident) = nullptr;
static void (*TrackFX_Show)(MediaTrack* track, int index, int showFlag) = nullptr;
static bool (*TrackFX_GetNamedConfigParm)(MediaTrack* track, int fx, const char* parmname, char* buf, int buf_sz) = nullptr;

// Layout constants
static const double COLUMN_WIDTH = 280.0;
static const double BROWSER_WIDTH = 260.0;
static const double ITEM_HEIGHT = 24.0;

SideFXWindow::SideFXWindow() {}

SideFXWindow::~SideFXWindow() {
    if (m_ctx && ImGui_DestroyContext) {
        ImGui_DestroyContext(m_ctx);
        m_ctx = nullptr;
    }
}

bool SideFXWindow::Initialize(reaper_plugin_info_t* rec) {
    if (!rec || !rec->GetFunc) {
        return false;
    }

    // Store rec for lazy initialization of ReaImGui
    s_rec = rec;

    // Load REAPER API functions we need
    m_GetSelectedTrack = (MediaTrack* (*)(ReaProject*, int))rec->GetFunc("GetSelectedTrack");
    m_GetTrackName = (bool (*)(MediaTrack*, char*, int))rec->GetFunc("GetTrackName");
    m_GetMediaTrackInfo_Value = (int (*)(MediaTrack*, const char*))rec->GetFunc("GetMediaTrackInfo_Value");
    m_TrackFX_GetCount = (int (*)(MediaTrack*))rec->GetFunc("TrackFX_GetCount");
    m_TrackFX_GetFXName = (bool (*)(MediaTrack*, int, char*, int))rec->GetFunc("TrackFX_GetFXName");
    m_TrackFX_GetEnabled = (bool (*)(MediaTrack*, int))rec->GetFunc("TrackFX_GetEnabled");
    m_ShowConsoleMsg = (void (*)(const char*))rec->GetFunc("ShowConsoleMsg");
    
    // Load additional FX APIs
    TrackFX_SetEnabled = (bool (*)(MediaTrack*, int, bool))rec->GetFunc("TrackFX_SetEnabled");
    TrackFX_GetParamNormalized = (double (*)(MediaTrack*, int, int))rec->GetFunc("TrackFX_GetParamNormalized");
    TrackFX_SetParamNormalized = (bool (*)(MediaTrack*, int, int, double))rec->GetFunc("TrackFX_SetParamNormalized");
    TrackFX_GetNumParams = (int (*)(MediaTrack*, int))rec->GetFunc("TrackFX_GetNumParams");
    TrackFX_GetParamName = (bool (*)(MediaTrack*, int, int, char*, int))rec->GetFunc("TrackFX_GetParamName");
    TrackFX_GetParamFromIdent = (int (*)(MediaTrack*, int, const char*))rec->GetFunc("TrackFX_GetParamFromIdent");
    TrackFX_Show = (void (*)(MediaTrack*, int, int))rec->GetFunc("TrackFX_Show");
    TrackFX_GetNamedConfigParm = (bool (*)(MediaTrack*, int, const char*, char*, int))rec->GetFunc("TrackFX_GetNamedConfigParm");

    // Don't try to initialize ReaImGui yet - it might not be loaded
    // We'll try lazily when Show() is called
    m_available = true;  // Assume available, will check on first use
    return true;
}

// Try to initialize ReaImGui (called lazily)
bool SideFXWindow::TryInitReaImGui() {
    if (m_reaimguiInitialized) {
        return IsReaImGuiAvailable();
    }
    
    m_reaimguiInitialized = true;
    
    if (!s_rec) {
        if (m_ShowConsoleMsg) {
            m_ShowConsoleMsg("[SideFX Mod] ERROR: rec not stored\n");
        }
        return false;
    }
    
    if (m_ShowConsoleMsg) {
        m_ShowConsoleMsg("[SideFX Mod] Lazy-initializing ReaImGui...\n");
    }
    
    if (InitializeReaImGui(s_rec)) {
        if (m_ShowConsoleMsg) {
            m_ShowConsoleMsg("[SideFX Mod] ReaImGui initialized successfully!\n");
        }
        return true;
    }
    
    if (m_ShowConsoleMsg) {
        m_ShowConsoleMsg("[SideFX Mod] ReaImGui still not available\n");
    }
    return false;
}

void SideFXWindow::Show() {
    // Try to initialize ReaImGui lazily if not done yet
    if (!m_reaimguiInitialized) {
        TryInitReaImGui();
    }
    
    if (!IsReaImGuiAvailable()) {
        if (m_ShowConsoleMsg) {
            m_ShowConsoleMsg("[SideFX Mod] Cannot show window - ReaImGui not available\n");
        }
        return;
    }
    
    m_visible = true;
    if (!m_ctx && ImGui_CreateContext) {
        m_ctx = ImGui_CreateContext("SideFX", nullptr);
        if (m_ShowConsoleMsg) {
            char buf[128];
            snprintf(buf, sizeof(buf), "[SideFX Mod] Created ImGui context: %p\n", m_ctx);
            m_ShowConsoleMsg(buf);
        }
    }
}

void SideFXWindow::Hide() {
    m_visible = false;
}

void SideFXWindow::Toggle() {
    if (m_visible) {
        Hide();
    } else {
        Show();
    }
}

void SideFXWindow::ApplyTheme() {
    if (!ImGui_PushStyleColor) return;

    m_themeColorCount = 0;

    // Dark theme matching Lua version
    ImGui_PushStyleColor(m_ctx, ImGuiCol::WindowBg, Theme::WindowBg);
    m_themeColorCount++;
    ImGui_PushStyleColor(m_ctx, ImGuiCol::ChildBg, Theme::ChildBg);
    m_themeColorCount++;
    ImGui_PushStyleColor(m_ctx, ImGuiCol::PopupBg, Theme::PopupBg);
    m_themeColorCount++;
    ImGui_PushStyleColor(m_ctx, ImGuiCol::TitleBg, Theme::TitleBg);
    m_themeColorCount++;
    ImGui_PushStyleColor(m_ctx, ImGuiCol::TitleBgActive, Theme::TitleBgActive);
    m_themeColorCount++;
    ImGui_PushStyleColor(m_ctx, ImGuiCol::TitleBgCollapsed, Theme::TitleBg);
    m_themeColorCount++;
    ImGui_PushStyleColor(m_ctx, ImGuiCol::FrameBg, Theme::FrameBg);
    m_themeColorCount++;
    ImGui_PushStyleColor(m_ctx, ImGuiCol::FrameBgHovered, Theme::FrameBgHovered);
    m_themeColorCount++;
    ImGui_PushStyleColor(m_ctx, ImGuiCol::FrameBgActive, Theme::FrameBgActive);
    m_themeColorCount++;
    ImGui_PushStyleColor(m_ctx, ImGuiCol::Text, Theme::Text);
    m_themeColorCount++;
    ImGui_PushStyleColor(m_ctx, ImGuiCol::TextDisabled, Theme::TextDisabled);
    m_themeColorCount++;
    ImGui_PushStyleColor(m_ctx, ImGuiCol::Button, Theme::Button);
    m_themeColorCount++;
    ImGui_PushStyleColor(m_ctx, ImGuiCol::ButtonHovered, Theme::ButtonHovered);
    m_themeColorCount++;
    ImGui_PushStyleColor(m_ctx, ImGuiCol::ButtonActive, Theme::ButtonActive);
    m_themeColorCount++;
    ImGui_PushStyleColor(m_ctx, ImGuiCol::Header, Theme::Header);
    m_themeColorCount++;
    ImGui_PushStyleColor(m_ctx, ImGuiCol::HeaderHovered, Theme::HeaderHovered);
    m_themeColorCount++;
    ImGui_PushStyleColor(m_ctx, ImGuiCol::HeaderActive, Theme::HeaderActive);
    m_themeColorCount++;
    ImGui_PushStyleColor(m_ctx, ImGuiCol::Border, Theme::Border);
    m_themeColorCount++;
    ImGui_PushStyleColor(m_ctx, ImGuiCol::Separator, Theme::Border);
    m_themeColorCount++;
    ImGui_PushStyleColor(m_ctx, ImGuiCol::CheckMark, Theme::Accent);
    m_themeColorCount++;
    ImGui_PushStyleColor(m_ctx, ImGuiCol::SliderGrab, Theme::Accent);
    m_themeColorCount++;
    ImGui_PushStyleColor(m_ctx, ImGuiCol::SliderGrabActive, Theme::AccentActive);
    m_themeColorCount++;
}

void SideFXWindow::PopTheme() {
    if (ImGui_PopStyleColor && m_themeColorCount > 0) {
        ImGui_PopStyleColor(m_ctx, &m_themeColorCount);
    }
    m_themeColorCount = 0;
}

void SideFXWindow::RenderToolbar() {
    if (!m_GetSelectedTrack) {
        if (ImGui_Text) {
            ImGui_Text(m_ctx, "REAPER API not available");
        }
        return;
    }

    MediaTrack* track = m_GetSelectedTrack(nullptr, 0);
    
    // Track name
    char trackName[256] = "No track selected";
    if (track && m_GetTrackName) {
        m_GetTrackName(track, trackName, sizeof(trackName));
    }
    
    // SideFX label
    if (ImGui_TextColored) {
        ImGui_TextColored(m_ctx, Theme::Accent, "SideFX");
    }
    
    if (ImGui_SameLine) {
        ImGui_SameLine(m_ctx, nullptr, nullptr);
    }
    
    if (ImGui_Text) {
        ImGui_Text(m_ctx, "|");
    }
    
    if (ImGui_SameLine) {
        ImGui_SameLine(m_ctx, nullptr, nullptr);
    }
    
    // Track name
    if (track) {
        if (ImGui_Text) {
            ImGui_Text(m_ctx, trackName);
        }
    } else {
        if (ImGui_TextColored) {
            ImGui_TextColored(m_ctx, Theme::TextDim, trackName);
        }
    }
    
    if (ImGui_Separator) {
        ImGui_Separator(m_ctx);
    }
}

void SideFXWindow::RenderFXItem(MediaTrack* track, int fxIndex) {
    if (!track || !m_TrackFX_GetFXName || !m_TrackFX_GetEnabled) return;
    
    char fxName[256] = "Unknown FX";
    m_TrackFX_GetFXName(track, fxIndex, fxName, sizeof(fxName));
    
    bool enabled = m_TrackFX_GetEnabled(track, fxIndex);
    
    // Check if it's a container
    bool isContainer = false;
    if (TrackFX_GetNamedConfigParm) {
        char buf[64] = {0};
        if (TrackFX_GetNamedConfigParm(track, fxIndex, "container_count", buf, sizeof(buf))) {
            isContainer = atoi(buf) > 0;
        }
    }
    
    // Push unique ID
    if (ImGui_PushID) {
        char idStr[32];
        snprintf(idStr, sizeof(idStr), "fx_%d", fxIndex);
        ImGui_PushID(m_ctx, idStr);
    }
    
    // Icon (text-based for now)
    const char* icon = isContainer ? "[+]" : "  *";
    if (ImGui_TextColored) {
        ImGui_TextColored(m_ctx, isContainer ? Theme::SecondaryAccent : Theme::TextDim, icon);
    }
    
    if (ImGui_SameLine) {
        ImGui_SameLine(m_ctx, nullptr, nullptr);
    }
    
    // FX Name (truncated if needed)
    char displayName[64];
    int maxLen = 25;
    if ((int)strlen(fxName) > maxLen) {
        snprintf(displayName, sizeof(displayName), "%.*s..", maxLen - 2, fxName);
    } else {
        snprintf(displayName, sizeof(displayName), "%s", fxName);
    }
    
    // Selectable name
    int textColor = enabled ? Theme::Text : Theme::TextDisabled;
    if (ImGui_TextColored) {
        ImGui_TextColored(m_ctx, textColor, displayName);
    }
    
    // Double-click to open FX window
    if (ImGui_IsItemHovered && ImGui_IsMouseDoubleClicked && TrackFX_Show) {
        if (ImGui_IsItemHovered(m_ctx, nullptr) && ImGui_IsMouseDoubleClicked(m_ctx, 0)) {
            TrackFX_Show(track, fxIndex, 3);  // 3 = toggle floating window
        }
    }
    
    // Wet/Dry slider
    int wetIdx = -1;
    if (TrackFX_GetParamFromIdent) {
        wetIdx = TrackFX_GetParamFromIdent(track, fxIndex, ":wet");
    }
    
    if (wetIdx >= 0 && TrackFX_GetParamNormalized && TrackFX_SetParamNormalized && ImGui_SliderDouble) {
        if (ImGui_SameLine) {
            ImGui_SameLine(m_ctx, nullptr, nullptr);
        }
        
        double wetVal = TrackFX_GetParamNormalized(track, fxIndex, wetIdx);
        
        if (ImGui_PushItemWidth) {
            ImGui_PushItemWidth(m_ctx, 50);
        }
        
        char sliderLabel[32];
        snprintf(sliderLabel, sizeof(sliderLabel), "##wet%d", fxIndex);
        
        double newWet = wetVal;
        if (ImGui_SliderDouble(m_ctx, sliderLabel, &newWet, 0.0, 1.0, "%.0f%%", nullptr)) {
            TrackFX_SetParamNormalized(track, fxIndex, wetIdx, newWet);
        }
        
        if (ImGui_PopItemWidth) {
            ImGui_PopItemWidth(m_ctx);
        }
    }
    
    // ON/OFF button
    if (ImGui_SameLine) {
        ImGui_SameLine(m_ctx, nullptr, nullptr);
    }
    
    // Color the button based on state
    if (ImGui_PushStyleColor) {
        if (enabled) {
            ImGui_PushStyleColor(m_ctx, ImGuiCol::Button, Theme::FxEnabled);
        } else {
            ImGui_PushStyleColor(m_ctx, ImGuiCol::Button, Theme::FxBypassed);
        }
    }
    
    char btnLabel[32];
    snprintf(btnLabel, sizeof(btnLabel), "%s##btn%d", enabled ? "ON" : "OFF", fxIndex);
    
    if (ImGui_SmallButton && TrackFX_SetEnabled) {
        if (ImGui_SmallButton(m_ctx, btnLabel)) {
            TrackFX_SetEnabled(track, fxIndex, !enabled);
        }
    }
    
    if (ImGui_PopStyleColor) {
        int one = 1;
        ImGui_PopStyleColor(m_ctx, &one);
    }
    
    if (ImGui_PopID) {
        ImGui_PopID(m_ctx);
    }
}

void SideFXWindow::RenderFXChain() {
    if (!m_GetSelectedTrack || !m_TrackFX_GetCount) {
        return;
    }

    MediaTrack* track = m_GetSelectedTrack(nullptr, 0);
    if (!track) {
        if (ImGui_TextColored) {
            ImGui_TextColored(m_ctx, Theme::TextDim, "Select a track to view FX chain");
        }
        return;
    }

    int fxCount = m_TrackFX_GetCount(track);
    
    // Column header
    if (ImGui_Text) {
        ImGui_Text(m_ctx, "FX Chain");
    }
    if (ImGui_Separator) {
        ImGui_Separator(m_ctx);
    }
    
    if (fxCount == 0) {
        if (ImGui_TextColored) {
            ImGui_TextColored(m_ctx, Theme::TextDim, "No FX on this track");
        }
        if (ImGui_TextColored) {
            ImGui_TextColored(m_ctx, Theme::TextDim, "Drag plugins here to add");
        }
        return;
    }

    // Draw each FX
    for (int i = 0; i < fxCount; i++) {
        RenderFXItem(track, i);
    }
}

void SideFXWindow::RenderModulatorPanel() {
    if (ImGui_Spacing) {
        ImGui_Spacing(m_ctx);
    }

    // Get modulator count
    auto& manager = ModulatorManager::instance();
    auto modulators = manager.getActiveModulators();

    char headerText[64];
    snprintf(headerText, sizeof(headerText), "Modulators (%zu)", modulators.size());
    
    if (ImGui_Text) {
        ImGui_Text(m_ctx, headerText);
    }
    if (ImGui_Separator) {
        ImGui_Separator(m_ctx);
    }

    if (modulators.empty()) {
        if (ImGui_TextColored) {
            ImGui_TextColored(m_ctx, Theme::TextDim, "No active modulators");
        }
    } else {
        for (Modulator* mod : modulators) {
            if (!mod) continue;

            if (ImGui_PushID) {
                char idStr[32];
                snprintf(idStr, sizeof(idStr), "mod_%d", mod->id);
                ImGui_PushID(m_ctx, idStr);
            }

            bool enabled = mod->enabled.load();
            bool playing = mod->playing.load();
            double phase = mod->phase.load();

            int statusColor = playing ? Theme::ModulatorActive : 
                             (enabled ? Theme::Accent : Theme::ModulatorIdle);

            char modLabel[256];
            snprintf(modLabel, sizeof(modLabel), "%s %s (%.0f%%)",
                     playing ? ">" : (enabled ? "*" : "o"),
                     mod->name.empty() ? "Unnamed" : mod->name.c_str(),
                     phase * 100.0);

            if (ImGui_TextColored) {
                ImGui_TextColored(m_ctx, statusColor, modLabel);
            }

            if (ImGui_PopID) {
                ImGui_PopID(m_ctx);
            }
        }
    }
}

void SideFXWindow::RenderStatusBar() {
    if (ImGui_Spacing) {
        ImGui_Spacing(m_ctx);
    }
    if (ImGui_Separator) {
        ImGui_Separator(m_ctx);
    }

    extern bool isAudioHookActive();
    bool hookActive = isAudioHookActive();

    char statusText[128];
    snprintf(statusText, sizeof(statusText), "Audio Hook: %s",
             hookActive ? "Active" : "Inactive");

    int statusColor = hookActive ? Theme::Success : Theme::Error;
    if (ImGui_TextColored) {
        ImGui_TextColored(m_ctx, statusColor, statusText);
    }
}

void SideFXWindow::Render() {
    if (!m_visible) {
        return;
    }
    
    // Make sure ReaImGui is initialized
    if (!IsReaImGuiAvailable()) {
        return;
    }

    // Create context if needed
    if (!m_ctx) {
        if (ImGui_CreateContext) {
            m_ctx = ImGui_CreateContext("SideFX", nullptr);
        }
        if (!m_ctx) {
            return;
        }
    }

    // Apply theme
    ApplyTheme();

    // Set initial window size
    int cond = ImGuiCond::FirstUseEver;
    if (ImGui_SetNextWindowSize) {
        ImGui_SetNextWindowSize(m_ctx, 900, 500, &cond);
    }

    // Begin window
    int flags = ImGuiWindowFlags::None;
    bool open = true;
    if (!ImGui_Begin(m_ctx, "SideFX##main", &open, &flags)) {
        ImGui_End(m_ctx);
        PopTheme();
        if (!open) {
            m_visible = false;
            if (ImGui_DestroyContext) {
                ImGui_DestroyContext(m_ctx);
            }
            m_ctx = nullptr;
        }
        return;
    }

    // Window was closed via X button
    if (!open) {
        m_visible = false;
        ImGui_End(m_ctx);
        PopTheme();
        if (ImGui_DestroyContext) {
            ImGui_DestroyContext(m_ctx);
        }
        m_ctx = nullptr;
        return;
    }

    // Toolbar
    RenderToolbar();
    
    // FX Chain Column (in a child window with border)
    if (ImGui_BeginChild) {
        double childW = COLUMN_WIDTH;
        double childH = 0;  // Auto height
        int childFlags = 1;  // Border flag
        
        if (ImGui_BeginChild(m_ctx, "FXChainCol", &childW, &childH, &childFlags, nullptr)) {
            RenderFXChain();
        }
        if (ImGui_EndChild) {
            ImGui_EndChild(m_ctx);
        }
    }
    
    // Modulator panel (to the right)
    if (ImGui_SameLine) {
        ImGui_SameLine(m_ctx, nullptr, nullptr);
    }
    
    if (ImGui_BeginChild) {
        double childW = COLUMN_WIDTH;
        double childH = 0;
        int childFlags = 1;  // Border
        
        if (ImGui_BeginChild(m_ctx, "ModulatorCol", &childW, &childH, &childFlags, nullptr)) {
            RenderModulatorPanel();
        }
        if (ImGui_EndChild) {
            ImGui_EndChild(m_ctx);
        }
    }
    
    // Status bar at bottom
    RenderStatusBar();

    ImGui_End(m_ctx);
    PopTheme();
}

} // namespace sidefx
