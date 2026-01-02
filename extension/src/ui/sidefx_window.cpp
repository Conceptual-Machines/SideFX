#include "ui/sidefx_window.h"
#include "reaimgui_api.h"
#include "modulator.h"
#include <cstdio>
#include <cstring>

namespace sidefx {

// Global instance
SideFXWindow* g_sideFXWindow = nullptr;

// Store rec for lazy initialization
static reaper_plugin_info_t* s_rec = nullptr;

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

    // Window background
    ImGui_PushStyleColor(m_ctx, ImGuiCol::WindowBg, Theme::WindowBg);
    m_themeColorCount++;
    ImGui_PushStyleColor(m_ctx, ImGuiCol::ChildBg, Theme::ChildBg);
    m_themeColorCount++;
    ImGui_PushStyleColor(m_ctx, ImGuiCol::PopupBg, Theme::PopupBg);
    m_themeColorCount++;

    // Title bar
    ImGui_PushStyleColor(m_ctx, ImGuiCol::TitleBg, Theme::TitleBg);
    m_themeColorCount++;
    ImGui_PushStyleColor(m_ctx, ImGuiCol::TitleBgActive, Theme::TitleBgActive);
    m_themeColorCount++;
    ImGui_PushStyleColor(m_ctx, ImGuiCol::TitleBgCollapsed, Theme::TitleBg);
    m_themeColorCount++;

    // Frame
    ImGui_PushStyleColor(m_ctx, ImGuiCol::FrameBg, Theme::FrameBg);
    m_themeColorCount++;
    ImGui_PushStyleColor(m_ctx, ImGuiCol::FrameBgHovered, Theme::FrameBgHovered);
    m_themeColorCount++;
    ImGui_PushStyleColor(m_ctx, ImGuiCol::FrameBgActive, Theme::FrameBgActive);
    m_themeColorCount++;

    // Text
    ImGui_PushStyleColor(m_ctx, ImGuiCol::Text, Theme::Text);
    m_themeColorCount++;
    ImGui_PushStyleColor(m_ctx, ImGuiCol::TextDisabled, Theme::TextDisabled);
    m_themeColorCount++;

    // Button
    ImGui_PushStyleColor(m_ctx, ImGuiCol::Button, Theme::Button);
    m_themeColorCount++;
    ImGui_PushStyleColor(m_ctx, ImGuiCol::ButtonHovered, Theme::ButtonHovered);
    m_themeColorCount++;
    ImGui_PushStyleColor(m_ctx, ImGuiCol::ButtonActive, Theme::ButtonActive);
    m_themeColorCount++;

    // Header
    ImGui_PushStyleColor(m_ctx, ImGuiCol::Header, Theme::Header);
    m_themeColorCount++;
    ImGui_PushStyleColor(m_ctx, ImGuiCol::HeaderHovered, Theme::HeaderHovered);
    m_themeColorCount++;
    ImGui_PushStyleColor(m_ctx, ImGuiCol::HeaderActive, Theme::HeaderActive);
    m_themeColorCount++;

    // Border
    ImGui_PushStyleColor(m_ctx, ImGuiCol::Border, Theme::Border);
    m_themeColorCount++;

    // Separator
    ImGui_PushStyleColor(m_ctx, ImGuiCol::Separator, Theme::Border);
    m_themeColorCount++;

    // Check mark and slider
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

void SideFXWindow::RenderHeader() {
    if (ImGui_TextColored) {
        ImGui_TextColored(m_ctx, Theme::Accent, "SideFX");
    } else if (ImGui_Text) {
        ImGui_Text(m_ctx, "SideFX");
    }

    if (ImGui_SameLine) {
        ImGui_SameLine(m_ctx, nullptr, nullptr);
    }

    if (ImGui_TextColored) {
        ImGui_TextColored(m_ctx, Theme::TextDim, "v0.1.0");
    }

    if (ImGui_Separator) {
        ImGui_Separator(m_ctx);
    }
}

void SideFXWindow::RenderTrackInfo() {
    if (!m_GetSelectedTrack) {
        if (ImGui_Text) {
            ImGui_Text(m_ctx, "REAPER API not available");
        }
        return;
    }

    MediaTrack* track = m_GetSelectedTrack(nullptr, 0);
    
    if (!track) {
        if (ImGui_TextColored) {
            ImGui_TextColored(m_ctx, Theme::TextDim, "No track selected");
        } else if (ImGui_Text) {
            ImGui_Text(m_ctx, "No track selected");
        }
        return;
    }

    // Get track name
    char trackName[256] = "Untitled";
    if (m_GetTrackName) {
        m_GetTrackName(track, trackName, sizeof(trackName));
    }

    // Get track number
    int trackNum = 0;
    if (m_GetMediaTrackInfo_Value) {
        trackNum = (int)(size_t)m_GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER");
    }

    // Display track info
    char trackInfo[512];
    snprintf(trackInfo, sizeof(trackInfo), "Track %d: %s", trackNum, trackName);
    
    if (ImGui_TextColored) {
        ImGui_TextColored(m_ctx, Theme::Text, trackInfo);
    } else if (ImGui_Text) {
        ImGui_Text(m_ctx, trackInfo);
    }

    // Get FX count
    int fxCount = 0;
    if (m_TrackFX_GetCount) {
        fxCount = m_TrackFX_GetCount(track);
    }

    char fxInfo[128];
    snprintf(fxInfo, sizeof(fxInfo), "%d FX", fxCount);
    
    if (ImGui_SameLine) {
        ImGui_SameLine(m_ctx, nullptr, nullptr);
    }
    if (ImGui_TextColored) {
        ImGui_TextColored(m_ctx, Theme::TextDim, fxInfo);
    }

    if (ImGui_Spacing) {
        ImGui_Spacing(m_ctx);
    }
}

void SideFXWindow::RenderFXChain() {
    if (!m_GetSelectedTrack || !m_TrackFX_GetCount || !m_TrackFX_GetFXName) {
        return;
    }

    MediaTrack* track = m_GetSelectedTrack(nullptr, 0);
    if (!track) {
        return;
    }

    int fxCount = m_TrackFX_GetCount(track);
    if (fxCount == 0) {
        if (ImGui_TextColored) {
            ImGui_TextColored(m_ctx, Theme::TextDim, "No FX on this track");
        }
        return;
    }

    // Draw FX list header
    if (ImGui_TextColored) {
        ImGui_TextColored(m_ctx, Theme::SecondaryAccent, "FX Chain");
    }
    if (ImGui_Separator) {
        ImGui_Separator(m_ctx);
    }

    // Draw each FX
    for (int i = 0; i < fxCount; i++) {
        char fxName[256] = "Unknown FX";
        m_TrackFX_GetFXName(track, i, fxName, sizeof(fxName));

        // Check if enabled
        bool enabled = true;
        if (m_TrackFX_GetEnabled) {
            enabled = m_TrackFX_GetEnabled(track, i);
        }

        // Push unique ID for this FX
        if (ImGui_PushID) {
            char idStr[32];
            snprintf(idStr, sizeof(idStr), "fx_%d", i);
            ImGui_PushID(m_ctx, idStr);
        }

        // Draw FX slot
        int textColor = enabled ? Theme::FxEnabled : Theme::FxBypassed;
        if (ImGui_TextColored) {
            char fxLabel[300];
            snprintf(fxLabel, sizeof(fxLabel), "%s %s", enabled ? "●" : "○", fxName);
            ImGui_TextColored(m_ctx, textColor, fxLabel);
        }

        // Tooltip on hover
        if (ImGui_IsItemHovered && ImGui_BeginTooltip && ImGui_EndTooltip) {
            if (ImGui_IsItemHovered(m_ctx, nullptr)) {
                if (ImGui_BeginTooltip(m_ctx)) {
                    if (ImGui_Text) {
                        ImGui_Text(m_ctx, fxName);
                    }
                    ImGui_EndTooltip(m_ctx);
                }
            }
        }

        if (ImGui_PopID) {
            ImGui_PopID(m_ctx);
        }
    }
}

void SideFXWindow::RenderModulatorPanel() {
    if (ImGui_Spacing) {
        ImGui_Spacing(m_ctx);
    }
    if (ImGui_Separator) {
        ImGui_Separator(m_ctx);
    }

    // Get modulator count
    auto& manager = ModulatorManager::instance();
    auto modulators = manager.getActiveModulators();

    char headerText[64];
    snprintf(headerText, sizeof(headerText), "Modulators (%zu)", modulators.size());
    
    if (ImGui_TextColored) {
        ImGui_TextColored(m_ctx, Theme::SecondaryAccent, headerText);
    }

    if (ImGui_Spacing) {
        ImGui_Spacing(m_ctx);
    }

    // List modulators
    if (modulators.empty()) {
        if (ImGui_TextColored) {
            ImGui_TextColored(m_ctx, Theme::TextDim, "No modulators");
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
                     playing ? "▶" : (enabled ? "●" : "○"),
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

    // Check audio hook status
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
        ImGui_SetNextWindowSize(m_ctx, 350, 500, &cond);
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

    // Render content
    RenderHeader();
    RenderTrackInfo();
    RenderFXChain();
    RenderModulatorPanel();
    RenderStatusBar();

    ImGui_End(m_ctx);
    PopTheme();
}

} // namespace sidefx

