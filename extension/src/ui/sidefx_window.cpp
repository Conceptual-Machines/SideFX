#include "ui/sidefx_window.h"
#include "reaimgui_api.h"
#include "modulator.h"
#include <cstdio>
#include <cstring>
#include <algorithm>

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
static int (*TrackFX_AddByName)(MediaTrack* track, const char* fxname, bool recFX, int instantiate) = nullptr;
static bool (*TrackFX_CopyToTrack)(MediaTrack* srcTrack, int srcFX, MediaTrack* destTrack, int destFX, bool is_move) = nullptr;
static int (*TrackFX_GetRecCount)(MediaTrack* track) = nullptr;
static int (*EnumInstalledFX)(int index, const char** nameOut, const char** identOut) = nullptr;

// Layout constants
static const double COLUMN_WIDTH = 280.0;
static const double BROWSER_WIDTH = 240.0;
static const double DETAIL_WIDTH = 300.0;
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

    s_rec = rec;

    // Load REAPER API functions
    m_GetSelectedTrack = (MediaTrack* (*)(ReaProject*, int))rec->GetFunc("GetSelectedTrack");
    m_GetTrackName = (bool (*)(MediaTrack*, char*, int))rec->GetFunc("GetTrackName");
    m_GetMediaTrackInfo_Value = (int (*)(MediaTrack*, const char*))rec->GetFunc("GetMediaTrackInfo_Value");
    m_TrackFX_GetCount = (int (*)(MediaTrack*))rec->GetFunc("TrackFX_GetCount");
    m_TrackFX_GetFXName = (bool (*)(MediaTrack*, int, char*, int))rec->GetFunc("TrackFX_GetFXName");
    m_TrackFX_GetEnabled = (bool (*)(MediaTrack*, int))rec->GetFunc("TrackFX_GetEnabled");
    m_ShowConsoleMsg = (void (*)(const char*))rec->GetFunc("ShowConsoleMsg");
    
    // Additional FX APIs
    TrackFX_SetEnabled = (bool (*)(MediaTrack*, int, bool))rec->GetFunc("TrackFX_SetEnabled");
    TrackFX_GetParamNormalized = (double (*)(MediaTrack*, int, int))rec->GetFunc("TrackFX_GetParamNormalized");
    TrackFX_SetParamNormalized = (bool (*)(MediaTrack*, int, int, double))rec->GetFunc("TrackFX_SetParamNormalized");
    TrackFX_GetNumParams = (int (*)(MediaTrack*, int))rec->GetFunc("TrackFX_GetNumParams");
    TrackFX_GetParamName = (bool (*)(MediaTrack*, int, int, char*, int))rec->GetFunc("TrackFX_GetParamName");
    TrackFX_GetParamFromIdent = (int (*)(MediaTrack*, int, const char*))rec->GetFunc("TrackFX_GetParamFromIdent");
    TrackFX_Show = (void (*)(MediaTrack*, int, int))rec->GetFunc("TrackFX_Show");
    TrackFX_GetNamedConfigParm = (bool (*)(MediaTrack*, int, const char*, char*, int))rec->GetFunc("TrackFX_GetNamedConfigParm");
    TrackFX_AddByName = (int (*)(MediaTrack*, const char*, bool, int))rec->GetFunc("TrackFX_AddByName");
    TrackFX_CopyToTrack = (bool (*)(MediaTrack*, int, MediaTrack*, int, bool))rec->GetFunc("TrackFX_CopyToTrack");
    TrackFX_GetRecCount = (int (*)(MediaTrack*))rec->GetFunc("TrackFX_GetRecCount");
    EnumInstalledFX = (int (*)(int, const char**, const char**))rec->GetFunc("EnumInstalledFX");

    m_available = true;
    return true;
}

bool SideFXWindow::TryInitReaImGui() {
    if (m_reaimguiInitialized) {
        return IsReaImGuiAvailable();
    }
    
    m_reaimguiInitialized = true;
    
    if (!s_rec) {
        return false;
    }
    
    if (InitializeReaImGui(s_rec)) {
        if (m_ShowConsoleMsg) {
            m_ShowConsoleMsg("[SideFX Mod] ReaImGui initialized!\n");
        }
        return true;
    }
    
    return false;
}

void SideFXWindow::Show() {
    if (!m_reaimguiInitialized) {
        TryInitReaImGui();
    }
    
    if (!IsReaImGuiAvailable()) {
        if (m_ShowConsoleMsg) {
            m_ShowConsoleMsg("[SideFX Mod] ReaImGui not available\n");
        }
        return;
    }
    
    m_visible = true;
    if (!m_ctx && ImGui_CreateContext) {
        m_ctx = ImGui_CreateContext("SideFX", nullptr);
    }
    
    // Scan plugins on first show
    if (!m_pluginsScanned) {
        ScanPlugins();
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

//------------------------------------------------------------------------------
// Plugin Scanning
//------------------------------------------------------------------------------

void SideFXWindow::ScanPlugins() {
    if (!EnumInstalledFX) return;
    
    m_allPlugins.clear();
    
    const char* name = nullptr;
    const char* ident = nullptr;
    int idx = 0;
    
    while (EnumInstalledFX(idx++, &name, &ident)) {
        if (!name) continue;
        
        PluginInfo info;
        info.fullName = ident ? ident : name;
        
        // Parse plugin name and type
        // Format is typically: "VST: PluginName (Manufacturer)" or "VST3: ..." or "AU: ..." or "JS: ..."
        std::string s = name;
        
        // Determine type
        if (s.find("VST3:") == 0 || s.find("VST3i:") == 0) {
            info.type = "VST3";
            info.isInstrument = s.find("VST3i:") == 0;
        } else if (s.find("VSTi:") == 0 || s.find("VST:") == 0) {
            info.type = "VST";
            info.isInstrument = s.find("VSTi:") == 0;
        } else if (s.find("AU:") == 0 || s.find("AUi:") == 0) {
            info.type = "AU";
            info.isInstrument = s.find("AUi:") == 0;
        } else if (s.find("JS:") == 0) {
            info.type = "JS";
        } else if (s.find("CLAP:") == 0 || s.find("CLAPi:") == 0) {
            info.type = "CLAP";
            info.isInstrument = s.find("CLAPi:") == 0;
        } else {
            info.type = "Other";
        }
        
        // Extract name (after the colon and space)
        size_t colonPos = s.find(": ");
        if (colonPos != std::string::npos) {
            info.name = s.substr(colonPos + 2);
        } else {
            info.name = s;
        }
        
        // Extract manufacturer from parentheses if present
        size_t parenPos = info.name.rfind(" (");
        if (parenPos != std::string::npos && info.name.back() == ')') {
            info.manufacturer = info.name.substr(parenPos + 2, info.name.length() - parenPos - 3);
            info.name = info.name.substr(0, parenPos);
        }
        
        m_allPlugins.push_back(info);
    }
    
    // Sort by name
    std::sort(m_allPlugins.begin(), m_allPlugins.end(), 
        [](const PluginInfo& a, const PluginInfo& b) {
            return a.name < b.name;
        });
    
    m_pluginsScanned = true;
    FilterPlugins();
}

void SideFXWindow::FilterPlugins() {
    m_filteredPlugins.clear();
    
    std::string search = m_searchBuffer;
    // Convert to lowercase for case-insensitive search
    std::transform(search.begin(), search.end(), search.begin(), ::tolower);
    
    for (const auto& plugin : m_allPlugins) {
        // Filter by type
        if (m_filterMode == 1 && !plugin.isInstrument) continue;
        if (m_filterMode == 2 && plugin.isInstrument) continue;
        
        // Filter by search
        if (!search.empty()) {
            std::string nameLower = plugin.name;
            std::transform(nameLower.begin(), nameLower.end(), nameLower.begin(), ::tolower);
            std::string mfrLower = plugin.manufacturer;
            std::transform(mfrLower.begin(), mfrLower.end(), mfrLower.begin(), ::tolower);
            
            if (nameLower.find(search) == std::string::npos && 
                mfrLower.find(search) == std::string::npos) {
                continue;
            }
        }
        
        m_filteredPlugins.push_back(plugin);
    }
}

void SideFXWindow::AddPluginToTrack(const PluginInfo& plugin) {
    if (!m_GetSelectedTrack || !TrackFX_AddByName) return;
    
    MediaTrack* track = m_GetSelectedTrack(nullptr, 0);
    if (!track) return;
    
    TrackFX_AddByName(track, plugin.fullName.c_str(), false, -1);
    RefreshFXList();
}

//------------------------------------------------------------------------------
// FX Chain Helpers
//------------------------------------------------------------------------------

void SideFXWindow::RefreshFXList() {
    m_selectedFX = -1;
    m_multiSelect.clear();
}

std::vector<int> SideFXWindow::GetContainerChildren(MediaTrack* track, int containerIdx) {
    std::vector<int> children;
    if (!track || !TrackFX_GetNamedConfigParm) return children;
    
    char buf[64];
    if (!TrackFX_GetNamedConfigParm(track, containerIdx, "container_count", buf, sizeof(buf))) {
        return children;
    }
    
    int count = atoi(buf);
    for (int i = 0; i < count; i++) {
        char paramName[64];
        snprintf(paramName, sizeof(paramName), "container_item.%d", i);
        if (TrackFX_GetNamedConfigParm(track, containerIdx, paramName, buf, sizeof(buf))) {
            children.push_back(atoi(buf));
        }
    }
    
    return children;
}

bool SideFXWindow::IsContainerExpanded(int fxIndex) {
    for (int idx : m_expandedContainers) {
        if (idx == fxIndex) return true;
    }
    return false;
}

void SideFXWindow::ToggleContainerExpanded(int fxIndex) {
    // Find depth of this container
    int depth = -1;
    for (size_t i = 0; i < m_expandedContainers.size(); i++) {
        if (m_expandedContainers[i] == fxIndex) {
            depth = (int)i;
            break;
        }
    }
    
    if (depth >= 0) {
        // Collapse this and all deeper
        CollapseFromDepth(depth);
    } else {
        // Find which depth to insert at
        // For now, just append (assumes clicking on visible container)
        m_expandedContainers.push_back(fxIndex);
    }
    
    m_selectedFX = -1;
}

void SideFXWindow::CollapseFromDepth(int depth) {
    while ((int)m_expandedContainers.size() > depth) {
        m_expandedContainers.pop_back();
    }
    m_selectedFX = -1;
}

//------------------------------------------------------------------------------
// Theme
//------------------------------------------------------------------------------

void SideFXWindow::ApplyTheme() {
    if (!ImGui_PushStyleColor) return;

    m_themeColorCount = 0;

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

//------------------------------------------------------------------------------
// Toolbar
//------------------------------------------------------------------------------

void SideFXWindow::RenderToolbar() {
    MediaTrack* track = m_GetSelectedTrack ? m_GetSelectedTrack(nullptr, 0) : nullptr;
    
    char trackName[256] = "No track selected";
    if (track && m_GetTrackName) {
        m_GetTrackName(track, trackName, sizeof(trackName));
    }
    
    // Browser toggle button
    if (ImGui_PushStyleColor) {
        if (m_browserVisible) {
            ImGui_PushStyleColor(m_ctx, ImGuiCol::Button, Theme::Accent);
        }
    }
    
    if (ImGui_SmallButton && ImGui_SmallButton(m_ctx, m_browserVisible ? "[B]" : "B")) {
        m_browserVisible = !m_browserVisible;
    }
    
    if (ImGui_PushStyleColor && m_browserVisible) {
        int one = 1;
        ImGui_PopStyleColor(m_ctx, &one);
    }
    
    if (ImGui_IsItemHovered && ImGui_IsItemHovered(m_ctx, nullptr)) {
        if (ImGui_SetTooltip) {
            ImGui_SetTooltip(m_ctx, m_browserVisible ? "Hide Browser" : "Show Browser");
        }
    }
    
    if (ImGui_SameLine) ImGui_SameLine(m_ctx, nullptr, nullptr);
    
    // Refresh button
    if (ImGui_SmallButton && ImGui_SmallButton(m_ctx, "R")) {
        RefreshFXList();
        if (!m_pluginsScanned) ScanPlugins();
    }
    if (ImGui_IsItemHovered && ImGui_IsItemHovered(m_ctx, nullptr)) {
        if (ImGui_SetTooltip) ImGui_SetTooltip(m_ctx, "Refresh");
    }
    
    if (ImGui_SameLine) ImGui_SameLine(m_ctx, nullptr, nullptr);
    
    // Separator
    if (ImGui_Text) ImGui_Text(m_ctx, "|");
    if (ImGui_SameLine) ImGui_SameLine(m_ctx, nullptr, nullptr);
    
    // Track name
    if (track) {
        if (ImGui_Text) ImGui_Text(m_ctx, trackName);
    } else {
        if (ImGui_TextColored) ImGui_TextColored(m_ctx, Theme::TextDim, trackName);
    }
    
    // Breadcrumb trail for expanded containers
    if (!m_expandedContainers.empty() && track && m_TrackFX_GetFXName) {
        if (ImGui_SameLine) ImGui_SameLine(m_ctx, nullptr, nullptr);
        if (ImGui_Text) ImGui_Text(m_ctx, ">");
        
        for (size_t i = 0; i < m_expandedContainers.size(); i++) {
            if (ImGui_SameLine) ImGui_SameLine(m_ctx, nullptr, nullptr);
            
            char fxName[128];
            m_TrackFX_GetFXName(track, m_expandedContainers[i], fxName, sizeof(fxName));
            
            // Truncate
            if (strlen(fxName) > 15) {
                fxName[13] = '.';
                fxName[14] = '.';
                fxName[15] = '\0';
            }
            
            char btnLabel[140];
            snprintf(btnLabel, sizeof(btnLabel), "%s##bc%zu", fxName, i);
            
            if (ImGui_SmallButton && ImGui_SmallButton(m_ctx, btnLabel)) {
                CollapseFromDepth((int)i + 1);
            }
            
            if (i < m_expandedContainers.size() - 1) {
                if (ImGui_SameLine) ImGui_SameLine(m_ctx, nullptr, nullptr);
                if (ImGui_Text) ImGui_Text(m_ctx, ">");
            }
        }
    }
    
    if (ImGui_Separator) ImGui_Separator(m_ctx);
}

//------------------------------------------------------------------------------
// Plugin Browser
//------------------------------------------------------------------------------

void SideFXWindow::RenderPluginBrowser() {
    if (!m_browserVisible) return;
    
    double browserW = BROWSER_WIDTH;
    double browserH = 0;
    int childFlags = 1; // Border
    
    if (!ImGui_BeginChild || !ImGui_BeginChild(m_ctx, "Browser", &browserW, &browserH, &childFlags, nullptr)) {
        return;
    }
    
    if (ImGui_Text) ImGui_Text(m_ctx, "Plugins");
    if (ImGui_Separator) ImGui_Separator(m_ctx);
    
    // Search input
    if (ImGui_PushItemWidth) ImGui_PushItemWidth(m_ctx, -1);
    
    if (ImGui_InputText) {
        bool changed = ImGui_InputText(m_ctx, "##search", m_searchBuffer, sizeof(m_searchBuffer), nullptr, nullptr);
        if (changed) {
            FilterPlugins();
        }
    }
    
    if (ImGui_PopItemWidth) ImGui_PopItemWidth(m_ctx);
    
    if (ImGui_IsItemHovered && ImGui_IsItemHovered(m_ctx, nullptr)) {
        if (ImGui_SetTooltip) ImGui_SetTooltip(m_ctx, "Search plugins...");
    }
    
    // Filter tabs
    if (ImGui_SmallButton) {
        // All tab
        if (m_filterMode == 0) {
            if (ImGui_PushStyleColor) ImGui_PushStyleColor(m_ctx, ImGuiCol::Button, Theme::Accent);
        }
        if (ImGui_SmallButton(m_ctx, "All")) {
            if (m_filterMode != 0) {
                m_filterMode = 0;
                FilterPlugins();
            }
        }
        if (m_filterMode == 0 && ImGui_PopStyleColor) {
            int one = 1;
            ImGui_PopStyleColor(m_ctx, &one);
        }
        
        if (ImGui_SameLine) ImGui_SameLine(m_ctx, nullptr, nullptr);
        
        // Instruments tab
        if (m_filterMode == 1) {
            if (ImGui_PushStyleColor) ImGui_PushStyleColor(m_ctx, ImGuiCol::Button, Theme::Accent);
        }
        if (ImGui_SmallButton(m_ctx, "Inst")) {
            if (m_filterMode != 1) {
                m_filterMode = 1;
                FilterPlugins();
            }
        }
        if (m_filterMode == 1 && ImGui_PopStyleColor) {
            int one = 1;
            ImGui_PopStyleColor(m_ctx, &one);
        }
        
        if (ImGui_SameLine) ImGui_SameLine(m_ctx, nullptr, nullptr);
        
        // Effects tab
        if (m_filterMode == 2) {
            if (ImGui_PushStyleColor) ImGui_PushStyleColor(m_ctx, ImGuiCol::Button, Theme::Accent);
        }
        if (ImGui_SmallButton(m_ctx, "FX")) {
            if (m_filterMode != 2) {
                m_filterMode = 2;
                FilterPlugins();
            }
        }
        if (m_filterMode == 2 && ImGui_PopStyleColor) {
            int one = 1;
            ImGui_PopStyleColor(m_ctx, &one);
        }
    }
    
    if (ImGui_Separator) ImGui_Separator(m_ctx);
    
    // Plugin list
    double listW = 0;
    double listH = 0;
    int listFlags = 1; // Border
    
    if (ImGui_BeginChild && ImGui_BeginChild(m_ctx, "PluginList", &listW, &listH, &listFlags, nullptr)) {
        for (size_t i = 0; i < m_filteredPlugins.size(); i++) {
            const auto& plugin = m_filteredPlugins[i];
            
            if (ImGui_PushID) {
                char idStr[32];
                snprintf(idStr, sizeof(idStr), "plugin_%zu", i);
                ImGui_PushID(m_ctx, idStr);
            }
            
            // Icon
            const char* icon = plugin.isInstrument ? "[I]" : "[F]";
            if (ImGui_TextColored) {
                ImGui_TextColored(m_ctx, plugin.isInstrument ? Theme::SecondaryAccent : Theme::TextDim, icon);
            }
            
            if (ImGui_SameLine) ImGui_SameLine(m_ctx, nullptr, nullptr);
            
            // Name (selectable)
            bool selected = false;
            if (ImGui_Selectable && ImGui_Selectable(m_ctx, plugin.name.c_str(), &selected, nullptr, nullptr, nullptr)) {
                AddPluginToTrack(plugin);
            }
            
            // Drag source
            if (ImGui_BeginDragDropSource) {
                int dragFlags = 0;
                if (ImGui_BeginDragDropSource(m_ctx, &dragFlags)) {
                    if (ImGui_SetDragDropPayload) {
                        ImGui_SetDragDropPayload(m_ctx, "PLUGIN_NAME", plugin.fullName.c_str(), nullptr);
                    }
                    if (ImGui_Text) {
                        char dragText[256];
                        snprintf(dragText, sizeof(dragText), "Add: %s", plugin.name.c_str());
                        ImGui_Text(m_ctx, dragText);
                    }
                    if (ImGui_EndDragDropSource) ImGui_EndDragDropSource(m_ctx);
                }
            }
            
            // Tooltip
            if (ImGui_IsItemHovered && ImGui_IsItemHovered(m_ctx, nullptr)) {
                if (ImGui_SetTooltip) {
                    char tooltip[512];
                    snprintf(tooltip, sizeof(tooltip), "%s\n%s\n(Drag to add)", 
                             plugin.fullName.c_str(), plugin.type.c_str());
                    ImGui_SetTooltip(m_ctx, tooltip);
                }
            }
            
            if (ImGui_PopID) ImGui_PopID(m_ctx);
        }
        
        if (ImGui_EndChild) ImGui_EndChild(m_ctx);
    }
    
    if (ImGui_EndChild) ImGui_EndChild(m_ctx);
    
    if (ImGui_SameLine) ImGui_SameLine(m_ctx, nullptr, nullptr);
}

//------------------------------------------------------------------------------
// FX Item Rendering
//------------------------------------------------------------------------------

void SideFXWindow::RenderFXItem(MediaTrack* track, int fxIndex, int depth) {
    if (!track || !m_TrackFX_GetFXName || !m_TrackFX_GetEnabled) return;
    
    char fxName[256] = "Unknown FX";
    m_TrackFX_GetFXName(track, fxIndex, fxName, sizeof(fxName));
    
    bool enabled = m_TrackFX_GetEnabled(track, fxIndex);
    
    // Check if container
    bool isContainer = false;
    int containerCount = 0;
    if (TrackFX_GetNamedConfigParm) {
        char buf[64] = {0};
        if (TrackFX_GetNamedConfigParm(track, fxIndex, "container_count", buf, sizeof(buf))) {
            containerCount = atoi(buf);
            isContainer = containerCount > 0;
        }
    }
    
    bool isExpanded = IsContainerExpanded(fxIndex);
    bool isSelected = (m_selectedFX == fxIndex);
    bool isMultiSelected = m_multiSelect.count(fxIndex) > 0;
    
    if (ImGui_PushID) {
        char idStr[32];
        snprintf(idStr, sizeof(idStr), "fx_%d_%d", depth, fxIndex);
        ImGui_PushID(m_ctx, idStr);
    }
    
    // Icon
    const char* icon = isContainer ? (isExpanded ? "[-]" : "[+]") : "  *";
    if (ImGui_TextColored) {
        ImGui_TextColored(m_ctx, isContainer ? Theme::SecondaryAccent : Theme::TextDim, icon);
    }
    
    if (ImGui_SameLine) ImGui_SameLine(m_ctx, nullptr, nullptr);
    
    // Truncate name
    char displayName[64];
    int maxLen = 20;
    if ((int)strlen(fxName) > maxLen) {
        snprintf(displayName, sizeof(displayName), "%.*s..", maxLen - 2, fxName);
    } else {
        snprintf(displayName, sizeof(displayName), "%s", fxName);
    }
    
    // Selectable
    bool highlight = isExpanded || isSelected || isMultiSelected;
    bool clicked = false;
    
    if (ImGui_Selectable) {
        clicked = ImGui_Selectable(m_ctx, displayName, &highlight, nullptr, nullptr, nullptr);
    }
    
    // Handle click
    if (clicked) {
        if (isContainer) {
            ToggleContainerExpanded(fxIndex);
        } else {
            m_selectedFX = (m_selectedFX == fxIndex) ? -1 : fxIndex;
        }
    }
    
    // Drag source
    if (ImGui_BeginDragDropSource) {
        int dragFlags = 0;
        if (ImGui_BeginDragDropSource(m_ctx, &dragFlags)) {
            m_draggingFX = fxIndex;
            char payload[32];
            snprintf(payload, sizeof(payload), "%d", fxIndex);
            if (ImGui_SetDragDropPayload) {
                ImGui_SetDragDropPayload(m_ctx, "FX_INDEX", payload, nullptr);
            }
            if (ImGui_Text) {
                char dragText[256];
                snprintf(dragText, sizeof(dragText), "Moving: %s", fxName);
                ImGui_Text(m_ctx, dragText);
            }
            if (ImGui_EndDragDropSource) ImGui_EndDragDropSource(m_ctx);
        }
    }
    
    // Drop target
    if (ImGui_BeginDragDropTarget && ImGui_BeginDragDropTarget(m_ctx)) {
        // Accept FX reorder
        const char* fxPayload = nullptr;
        int payloadSize = 0;
        if (ImGui_AcceptDragDropPayload && 
            ImGui_AcceptDragDropPayload(m_ctx, "FX_INDEX", nullptr, &fxPayload, &payloadSize)) {
            if (fxPayload && TrackFX_CopyToTrack) {
                int srcIdx = atoi(fxPayload);
                if (srcIdx != fxIndex) {
                    TrackFX_CopyToTrack(track, srcIdx, track, fxIndex, true);
                    RefreshFXList();
                }
            }
        }
        
        // Accept plugin drop
        const char* pluginPayload = nullptr;
        if (ImGui_AcceptDragDropPayload && 
            ImGui_AcceptDragDropPayload(m_ctx, "PLUGIN_NAME", nullptr, &pluginPayload, &payloadSize)) {
            if (pluginPayload && TrackFX_AddByName) {
                // Add after this FX
                TrackFX_AddByName(track, pluginPayload, false, fxIndex + 1);
                RefreshFXList();
            }
        }
        
        if (ImGui_EndDragDropTarget) ImGui_EndDragDropTarget(m_ctx);
    }
    
    // Double-click to open
    if (ImGui_IsItemHovered && ImGui_IsMouseDoubleClicked && TrackFX_Show) {
        if (ImGui_IsItemHovered(m_ctx, nullptr) && ImGui_IsMouseDoubleClicked(m_ctx, 0)) {
            TrackFX_Show(track, fxIndex, 3);
        }
    }
    
    // Tooltip
    if (ImGui_IsItemHovered && ImGui_IsItemHovered(m_ctx, nullptr)) {
        if (ImGui_SetTooltip) {
            if (isContainer) {
                char tip[256];
                snprintf(tip, sizeof(tip), "%s\n(%d FX inside)\nClick to expand", fxName, containerCount);
                ImGui_SetTooltip(m_ctx, tip);
            } else {
                ImGui_SetTooltip(m_ctx, fxName);
            }
        }
    }
    
    // Wet/dry slider
    int wetIdx = -1;
    if (TrackFX_GetParamFromIdent) {
        wetIdx = TrackFX_GetParamFromIdent(track, fxIndex, ":wet");
    }
    
    if (wetIdx >= 0 && TrackFX_GetParamNormalized && TrackFX_SetParamNormalized) {
        if (ImGui_SameLine) ImGui_SameLine(m_ctx, nullptr, nullptr);
        
        double wetVal = TrackFX_GetParamNormalized(track, fxIndex, wetIdx);
        if (ImGui_PushItemWidth) ImGui_PushItemWidth(m_ctx, 45);
        
        char sliderLabel[32];
        snprintf(sliderLabel, sizeof(sliderLabel), "##wet%d", fxIndex);
        
        if (ImGui_SliderDouble && ImGui_SliderDouble(m_ctx, sliderLabel, &wetVal, 0.0, 1.0, "%.0f%%", nullptr)) {
            TrackFX_SetParamNormalized(track, fxIndex, wetIdx, wetVal);
        }
        
        if (ImGui_PopItemWidth) ImGui_PopItemWidth(m_ctx);
    }
    
    // ON/OFF button
    if (ImGui_SameLine) ImGui_SameLine(m_ctx, nullptr, nullptr);
    
    if (ImGui_PushStyleColor) {
        ImGui_PushStyleColor(m_ctx, ImGuiCol::Button, enabled ? Theme::FxEnabled : Theme::FxBypassed);
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
    
    if (ImGui_PopID) ImGui_PopID(m_ctx);
}

//------------------------------------------------------------------------------
// FX Chain Column
//------------------------------------------------------------------------------

void SideFXWindow::RenderFXChainColumn(int depth, int parentFxIndex) {
    if (!m_GetSelectedTrack || !m_TrackFX_GetCount) return;
    
    MediaTrack* track = m_GetSelectedTrack(nullptr, 0);
    if (!track) {
        if (depth == 0) {
            if (ImGui_TextColored) {
                ImGui_TextColored(m_ctx, Theme::TextDim, "Select a track");
            }
        }
        return;
    }
    
    // Column header
    const char* title = (depth == 0) ? "FX Chain" : nullptr;
    if (depth > 0 && parentFxIndex >= 0 && m_TrackFX_GetFXName) {
        static char containerName[128];
        m_TrackFX_GetFXName(track, parentFxIndex, containerName, sizeof(containerName));
        title = containerName;
    }
    
    if (title && ImGui_Text) {
        ImGui_Text(m_ctx, title);
    }
    if (ImGui_Separator) ImGui_Separator(m_ctx);
    
    // Get FX list for this column
    std::vector<int> fxIndices;
    
    if (depth == 0) {
        // Top level FX (those without parent container, or all if no container support)
        int fxCount = m_TrackFX_GetCount(track);
        for (int i = 0; i < fxCount; i++) {
            // Check if this FX has a parent container
            // If not, it's top level
            bool hasParent = false;
            if (TrackFX_GetNamedConfigParm) {
                char buf[64];
                if (TrackFX_GetNamedConfigParm(track, i, "parent_container", buf, sizeof(buf))) {
                    hasParent = atoi(buf) >= 0;
                }
            }
            if (!hasParent) {
                fxIndices.push_back(i);
            }
        }
        
        // If no container API or all FX have no parent info, just list all
        if (fxIndices.empty()) {
            int fxCount2 = m_TrackFX_GetCount(track);
            for (int i = 0; i < fxCount2; i++) {
                fxIndices.push_back(i);
            }
        }
    } else if (parentFxIndex >= 0) {
        // Get children of container
        fxIndices = GetContainerChildren(track, parentFxIndex);
    }
    
    if (fxIndices.empty()) {
        if (ImGui_TextColored) {
            ImGui_TextColored(m_ctx, Theme::TextDim, "Empty");
        }
        return;
    }
    
    // Render each FX
    for (int fxIdx : fxIndices) {
        RenderFXItem(track, fxIdx, depth);
    }
}

//------------------------------------------------------------------------------
// Detail Panel
//------------------------------------------------------------------------------

void SideFXWindow::RenderDetailPanel() {
    if (m_selectedFX < 0) return;
    
    MediaTrack* track = m_GetSelectedTrack ? m_GetSelectedTrack(nullptr, 0) : nullptr;
    if (!track) return;
    
    double detailW = DETAIL_WIDTH;
    double detailH = 0;
    int childFlags = 1;
    
    if (!ImGui_BeginChild || !ImGui_BeginChild(m_ctx, "DetailPanel", &detailW, &detailH, &childFlags, nullptr)) {
        return;
    }
    
    // Header
    char fxName[256] = "Unknown";
    if (m_TrackFX_GetFXName) {
        m_TrackFX_GetFXName(track, m_selectedFX, fxName, sizeof(fxName));
    }
    
    if (ImGui_Text) ImGui_Text(m_ctx, fxName);
    if (ImGui_Separator) ImGui_Separator(m_ctx);
    
    // Bypass + Open buttons
    bool enabled = m_TrackFX_GetEnabled ? m_TrackFX_GetEnabled(track, m_selectedFX) : true;
    
    double btnW = (detailW - 20) / 2;
    double btnH = 0;
    
    if (ImGui_PushStyleColor) {
        ImGui_PushStyleColor(m_ctx, ImGuiCol::Button, enabled ? Theme::FxEnabled : Theme::FxBypassed);
    }
    
    if (ImGui_Button && TrackFX_SetEnabled) {
        if (ImGui_Button(m_ctx, enabled ? "ON" : "OFF", &btnW, &btnH)) {
            TrackFX_SetEnabled(track, m_selectedFX, !enabled);
        }
    }
    
    if (ImGui_PopStyleColor) {
        int one = 1;
        ImGui_PopStyleColor(m_ctx, &one);
    }
    
    if (ImGui_SameLine) ImGui_SameLine(m_ctx, nullptr, nullptr);
    
    if (ImGui_Button && TrackFX_Show) {
        if (ImGui_Button(m_ctx, "Open FX", &btnW, &btnH)) {
            TrackFX_Show(track, m_selectedFX, 3);
        }
    }
    
    if (ImGui_Separator) ImGui_Separator(m_ctx);
    
    // Parameters
    int paramCount = TrackFX_GetNumParams ? TrackFX_GetNumParams(track, m_selectedFX) : 0;
    
    char paramHeader[64];
    snprintf(paramHeader, sizeof(paramHeader), "Parameters (%d)", paramCount);
    if (ImGui_Text) ImGui_Text(m_ctx, paramHeader);
    
    if (paramCount == 0) {
        if (ImGui_TextColored) ImGui_TextColored(m_ctx, Theme::TextDim, "No parameters");
    } else {
        // Scrollable param list
        double listW = 0;
        double listH = 0;
        int listFlags = 1;
        
        if (ImGui_BeginChild && ImGui_BeginChild(m_ctx, "ParamList", &listW, &listH, &listFlags, nullptr)) {
            for (int i = 0; i < paramCount && i < 100; i++) {  // Limit to 100 params
                char paramName[128] = "";
                if (TrackFX_GetParamName) {
                    TrackFX_GetParamName(track, m_selectedFX, i, paramName, sizeof(paramName));
                }
                
                if (strlen(paramName) == 0) {
                    snprintf(paramName, sizeof(paramName), "Param %d", i + 1);
                }
                
                if (ImGui_PushID) {
                    char idStr[32];
                    snprintf(idStr, sizeof(idStr), "param_%d", i);
                    ImGui_PushID(m_ctx, idStr);
                }
                
                if (ImGui_Text) ImGui_Text(m_ctx, paramName);
                
                if (ImGui_PushItemWidth) ImGui_PushItemWidth(m_ctx, -1);
                
                double val = TrackFX_GetParamNormalized ? TrackFX_GetParamNormalized(track, m_selectedFX, i) : 0;
                
                char sliderLabel[32];
                snprintf(sliderLabel, sizeof(sliderLabel), "##p%d", i);
                
                if (ImGui_SliderDouble && TrackFX_SetParamNormalized) {
                    if (ImGui_SliderDouble(m_ctx, sliderLabel, &val, 0.0, 1.0, "%.3f", nullptr)) {
                        TrackFX_SetParamNormalized(track, m_selectedFX, i, val);
                    }
                }
                
                if (ImGui_PopItemWidth) ImGui_PopItemWidth(m_ctx);
                
                if (ImGui_Spacing) ImGui_Spacing(m_ctx);
                
                if (ImGui_PopID) ImGui_PopID(m_ctx);
            }
            
            if (ImGui_EndChild) ImGui_EndChild(m_ctx);
        }
    }
    
    if (ImGui_EndChild) ImGui_EndChild(m_ctx);
}

//------------------------------------------------------------------------------
// Modulator Panel
//------------------------------------------------------------------------------

void SideFXWindow::RenderModulatorPanel() {
    auto& manager = ModulatorManager::instance();
    auto modulators = manager.getActiveModulators();

    char headerText[64];
    snprintf(headerText, sizeof(headerText), "Modulators (%zu)", modulators.size());
    
    if (ImGui_Text) ImGui_Text(m_ctx, headerText);
    if (ImGui_Separator) ImGui_Separator(m_ctx);

    if (modulators.empty()) {
        if (ImGui_TextColored) ImGui_TextColored(m_ctx, Theme::TextDim, "No active modulators");
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

            if (ImGui_TextColored) ImGui_TextColored(m_ctx, statusColor, modLabel);

            if (ImGui_PopID) ImGui_PopID(m_ctx);
        }
    }
}

//------------------------------------------------------------------------------
// Status Bar
//------------------------------------------------------------------------------

void SideFXWindow::RenderStatusBar() {
    if (ImGui_Separator) ImGui_Separator(m_ctx);

    extern bool isAudioHookActive();
    bool hookActive = isAudioHookActive();

    char statusText[128];
    snprintf(statusText, sizeof(statusText), "Audio: %s | Plugins: %zu",
             hookActive ? "Active" : "Inactive", m_allPlugins.size());

    int statusColor = hookActive ? Theme::Success : Theme::Warning;
    if (ImGui_TextColored) ImGui_TextColored(m_ctx, statusColor, statusText);
}

//------------------------------------------------------------------------------
// Main Render
//------------------------------------------------------------------------------

void SideFXWindow::Render() {
    if (!m_visible) return;
    
    if (!IsReaImGuiAvailable()) return;

    if (!m_ctx) {
        if (ImGui_CreateContext) {
            m_ctx = ImGui_CreateContext("SideFX", nullptr);
        }
        if (!m_ctx) return;
    }

    ApplyTheme();

    // Set initial window size
    int cond = ImGuiCond::FirstUseEver;
    if (ImGui_SetNextWindowSize) {
        ImGui_SetNextWindowSize(m_ctx, 1000, 550, &cond);
    }

    // Begin window
    int flags = ImGuiWindowFlags::None;
    bool open = true;
    if (!ImGui_Begin(m_ctx, "SideFX##main", &open, &flags)) {
        ImGui_End(m_ctx);
        PopTheme();
        if (!open) {
            m_visible = false;
            if (ImGui_DestroyContext) ImGui_DestroyContext(m_ctx);
            m_ctx = nullptr;
        }
        return;
    }

    if (!open) {
        m_visible = false;
        ImGui_End(m_ctx);
        PopTheme();
        if (ImGui_DestroyContext) ImGui_DestroyContext(m_ctx);
        m_ctx = nullptr;
        return;
    }

    // Toolbar
    RenderToolbar();
    
    // Plugin Browser (left side)
    RenderPluginBrowser();
    
    // Scrollable columns area
    int scrollFlags = ImGuiWindowFlags::AlwaysHorizontalScrollbar;
    double scrollW = 0;  // Remaining space
    double scrollH = 0;
    int scrollChildFlags = 0;
    
    if (ImGui_BeginChild && ImGui_BeginChild(m_ctx, "ColumnsArea", &scrollW, &scrollH, &scrollChildFlags, &scrollFlags)) {
        // FX Chain column (depth 0)
        double colW = COLUMN_WIDTH;
        double colH = 0;
        int colFlags = 1;  // Border
        
        if (ImGui_BeginChild && ImGui_BeginChild(m_ctx, "FXChainCol", &colW, &colH, &colFlags, nullptr)) {
            RenderFXChainColumn(0, -1);
        }
        if (ImGui_EndChild) ImGui_EndChild(m_ctx);
        
        // Expanded container columns
        for (size_t i = 0; i < m_expandedContainers.size(); i++) {
            if (ImGui_SameLine) ImGui_SameLine(m_ctx, nullptr, nullptr);
            
            char colId[32];
            snprintf(colId, sizeof(colId), "ContainerCol%zu", i);
            
            if (ImGui_BeginChild && ImGui_BeginChild(m_ctx, colId, &colW, &colH, &colFlags, nullptr)) {
                RenderFXChainColumn((int)i + 1, m_expandedContainers[i]);
            }
            if (ImGui_EndChild) ImGui_EndChild(m_ctx);
        }
        
        // Detail panel (if FX selected)
        if (m_selectedFX >= 0) {
            if (ImGui_SameLine) ImGui_SameLine(m_ctx, nullptr, nullptr);
            RenderDetailPanel();
        }
        
        // Modulator column
        if (ImGui_SameLine) ImGui_SameLine(m_ctx, nullptr, nullptr);
        
        if (ImGui_BeginChild && ImGui_BeginChild(m_ctx, "ModulatorCol", &colW, &colH, &colFlags, nullptr)) {
            RenderModulatorPanel();
        }
        if (ImGui_EndChild) ImGui_EndChild(m_ctx);
        
        if (ImGui_EndChild) ImGui_EndChild(m_ctx);
    }
    
    // Status bar
    RenderStatusBar();

    ImGui_End(m_ctx);
    PopTheme();
}

} // namespace sidefx
