#pragma once

#include "reaper_plugin.h"

namespace sidefx {

//------------------------------------------------------------------------------
// ReaImGui Function Pointers
// These are loaded at runtime from the ReaImGui extension
//------------------------------------------------------------------------------

// Context management
extern void* (*ImGui_CreateContext)(const char* label, int* config_flagsInOptional);
extern void (*ImGui_DestroyContext)(void* ctx);

// Window management
extern bool (*ImGui_Begin)(void* ctx, const char* name, bool* p_openInOutOptional, int* flagsInOptional);
extern void (*ImGui_End)(void* ctx);
extern void (*ImGui_SetNextWindowSize)(void* ctx, double size_w, double size_h, int* condInOptional);
extern void (*ImGui_SetNextWindowPos)(void* ctx, double pos_x, double pos_y, int* condInOptional, double* pivot_xInOptional, double* pivot_yInOptional);
extern bool (*ImGui_IsWindowAppearing)(void* ctx);
extern void (*ImGui_GetWindowSize)(void* ctx, double* wOut, double* hOut);
extern void (*ImGui_GetContentRegionAvail)(void* ctx, double* wOut, double* hOut);

// Text
extern void (*ImGui_Text)(void* ctx, const char* text);
extern void (*ImGui_TextColored)(void* ctx, int col_rgba, const char* text);
extern void (*ImGui_TextWrapped)(void* ctx, const char* text);

// Buttons
extern bool (*ImGui_Button)(void* ctx, const char* label, double* size_wInOptional, double* size_hInOptional);
extern bool (*ImGui_SmallButton)(void* ctx, const char* label);
extern bool (*ImGui_InvisibleButton)(void* ctx, const char* str_id, double size_w, double size_h, int* flagsInOptional);

// Checkboxes and toggles
extern bool (*ImGui_Checkbox)(void* ctx, const char* label, bool* v);

// Sliders
extern bool (*ImGui_SliderDouble)(void* ctx, const char* label, double* v, double v_min, double v_max, const char* formatInOptional, int* flagsInOptional);
extern bool (*ImGui_SliderInt)(void* ctx, const char* label, int* v, int v_min, int v_max, const char* formatInOptional, int* flagsInOptional);

// Input
extern bool (*ImGui_InputText)(void* ctx, const char* label, char* buf, int buf_size, int* flagsInOptional, void* callbackInOptional);
extern bool (*ImGui_InputTextWithHint)(void* ctx, const char* label, const char* hint, char* buf, int buf_size, int* flagsInOptional, void* callbackInOptional);
extern bool (*ImGui_InputDouble)(void* ctx, const char* label, double* v, double* stepInOptional, double* step_fastInOptional, const char* formatInOptional, int* flagsInOptional);
extern bool (*ImGui_InputInt)(void* ctx, const char* label, int* v, int* stepInOptional, int* step_fastInOptional, int* flagsInOptional);

// Combo/Dropdown
extern bool (*ImGui_BeginCombo)(void* ctx, const char* label, const char* preview_value, int* flagsInOptional);
extern void (*ImGui_EndCombo)(void* ctx);
extern bool (*ImGui_Selectable)(void* ctx, const char* label, bool* p_selectedInOut, int* flagsInOptional, double* size_wInOptional, double* size_hInOptional);

// Layout
extern void (*ImGui_SameLine)(void* ctx, double* offset_from_start_xInOptional, double* spacingInOptional);
extern void (*ImGui_Separator)(void* ctx);
extern void (*ImGui_Spacing)(void* ctx);
extern void (*ImGui_NewLine)(void* ctx);
extern void (*ImGui_Dummy)(void* ctx, double size_w, double size_h);
extern void (*ImGui_Indent)(void* ctx, double* indent_wInOptional);
extern void (*ImGui_Unindent)(void* ctx, double* indent_wInOptional);
extern void (*ImGui_PushItemWidth)(void* ctx, double item_width);
extern void (*ImGui_PopItemWidth)(void* ctx);

// Columns/Table
extern bool (*ImGui_BeginTable)(void* ctx, const char* str_id, int column, int* flagsInOptional, double* outer_size_wInOptional, double* outer_size_hInOptional, double* inner_widthInOptional);
extern void (*ImGui_EndTable)(void* ctx);
extern void (*ImGui_TableNextRow)(void* ctx, int* row_flagsInOptional, double* min_row_heightInOptional);
extern bool (*ImGui_TableNextColumn)(void* ctx);
extern bool (*ImGui_TableSetColumnIndex)(void* ctx, int column_n);
extern void (*ImGui_TableSetupColumn)(void* ctx, const char* label, int* flagsInOptional, double* init_width_or_weightInOptional, int* user_idInOptional);
extern void (*ImGui_TableHeadersRow)(void* ctx);

// Child windows
extern bool (*ImGui_BeginChild)(void* ctx, const char* str_id, double* size_wInOptional, double* size_hInOptional, int* child_flagsInOptional, int* window_flagsInOptional);
extern void (*ImGui_EndChild)(void* ctx);

// Scrolling
extern void (*ImGui_SetScrollHereY)(void* ctx, double* center_y_ratioInOptional);
extern double (*ImGui_GetScrollY)(void* ctx);
extern double (*ImGui_GetScrollMaxY)(void* ctx);

// Styling
extern void (*ImGui_PushStyleColor)(void* ctx, int idx, int col_rgba);
extern void (*ImGui_PopStyleColor)(void* ctx, int* countInOptional);
extern void (*ImGui_PushStyleVar)(void* ctx, int idx, double val);
extern void (*ImGui_PushStyleVar2)(void* ctx, int idx, double val_x, double val_y);
extern void (*ImGui_PopStyleVar)(void* ctx, int* countInOptional);

// IDs
extern void (*ImGui_PushID)(void* ctx, const char* str_id);
extern void (*ImGui_PopID)(void* ctx);

// Keyboard focus
extern void (*ImGui_SetKeyboardFocusHere)(void* ctx, int* offsetInOptional);

// Drag & Drop
extern bool (*ImGui_BeginDragDropSource)(void* ctx, int* flagsInOptional);
extern bool (*ImGui_SetDragDropPayload)(void* ctx, const char* type, const char* data, int* condInOptional);
extern void (*ImGui_EndDragDropSource)(void* ctx);
extern bool (*ImGui_BeginDragDropTarget)(void* ctx);
extern bool (*ImGui_AcceptDragDropPayload)(void* ctx, const char* type, int* flagsInOptional, const char** dataOut, int* sizeOut);
extern void (*ImGui_EndDragDropTarget)(void* ctx);

// Drawing
extern void* (*ImGui_GetWindowDrawList)(void* ctx);
extern void (*ImGui_DrawList_AddLine)(void* draw_list, double p1_x, double p1_y, double p2_x, double p2_y, int col_rgba, double* thicknessInOptional);
extern void (*ImGui_DrawList_AddRect)(void* draw_list, double p_min_x, double p_min_y, double p_max_x, double p_max_y, int col_rgba, double* roundingInOptional, int* flagsInOptional, double* thicknessInOptional);
extern void (*ImGui_DrawList_AddRectFilled)(void* draw_list, double p_min_x, double p_min_y, double p_max_x, double p_max_y, int col_rgba, double* roundingInOptional, int* flagsInOptional);
extern void (*ImGui_DrawList_AddCircle)(void* draw_list, double center_x, double center_y, double radius, int col_rgba, int* num_segmentsInOptional, double* thicknessInOptional);
extern void (*ImGui_DrawList_AddCircleFilled)(void* draw_list, double center_x, double center_y, double radius, int col_rgba, int* num_segmentsInOptional);
extern void (*ImGui_DrawList_AddBezierCubic)(void* draw_list, double p1_x, double p1_y, double p2_x, double p2_y, double p3_x, double p3_y, double p4_x, double p4_y, int col_rgba, double thickness, int* num_segmentsInOptional);
extern void (*ImGui_DrawList_AddText)(void* draw_list, double x, double y, int col_rgba, const char* text);

// Cursor position
extern void (*ImGui_GetCursorScreenPos)(void* ctx, double* xOut, double* yOut);
extern void (*ImGui_GetCursorPos)(void* ctx, double* xOut, double* yOut);
extern void (*ImGui_SetCursorPos)(void* ctx, double local_x, double local_y);
extern void (*ImGui_SetCursorPosX)(void* ctx, double local_x);
extern void (*ImGui_SetCursorPosY)(void* ctx, double local_y);

// Mouse
extern bool (*ImGui_IsItemHovered)(void* ctx, int* flagsInOptional);
extern bool (*ImGui_IsItemClicked)(void* ctx, int* mouse_buttonInOptional);
extern bool (*ImGui_IsItemActive)(void* ctx);
extern bool (*ImGui_IsMouseDown)(void* ctx, int button);
extern bool (*ImGui_IsMouseClicked)(void* ctx, int button, bool* repeatInOptional);
extern bool (*ImGui_IsMouseDoubleClicked)(void* ctx, int button);
extern void (*ImGui_GetMousePos)(void* ctx, double* xOut, double* yOut);
extern void (*ImGui_GetMouseDelta)(void* ctx, double* xOut, double* yOut);

// Tooltips
extern bool (*ImGui_BeginTooltip)(void* ctx);
extern void (*ImGui_EndTooltip)(void* ctx);
extern void (*ImGui_SetTooltip)(void* ctx, const char* text);

// Popups
extern bool (*ImGui_BeginPopup)(void* ctx, const char* str_id, int* flagsInOptional);
extern bool (*ImGui_BeginPopupContextItem)(void* ctx, const char* str_idInOptional, int* popup_flagsInOptional);
extern void (*ImGui_EndPopup)(void* ctx);
extern void (*ImGui_OpenPopup)(void* ctx, const char* str_id, int* popup_flagsInOptional);
extern void (*ImGui_CloseCurrentPopup)(void* ctx);

// Menu
extern bool (*ImGui_BeginMenuBar)(void* ctx);
extern void (*ImGui_EndMenuBar)(void* ctx);
extern bool (*ImGui_BeginMenu)(void* ctx, const char* label, bool* enabledInOptional);
extern void (*ImGui_EndMenu)(void* ctx);
extern bool (*ImGui_MenuItem)(void* ctx, const char* label, const char* shortcutInOptional, bool* p_selectedInOptional, bool* enabledInOptional);

// Tree nodes
extern bool (*ImGui_TreeNode)(void* ctx, const char* label, int* flagsInOptional);
extern bool (*ImGui_TreeNodeEx)(void* ctx, const char* str_id, int flags, const char* label);
extern void (*ImGui_TreePop)(void* ctx);
extern void (*ImGui_SetNextItemOpen)(void* ctx, bool is_open, int* condInOptional);

// Color
extern bool (*ImGui_ColorEdit4)(void* ctx, const char* label, int* col_rgbaInOut, int* flagsInOptional);

//------------------------------------------------------------------------------
// ReaImGui Constants
//------------------------------------------------------------------------------

namespace ImGuiCond {
    constexpr int Always = 1 << 0;
    constexpr int Once = 1 << 1;
    constexpr int FirstUseEver = 1 << 2;
    constexpr int Appearing = 1 << 3;
}

namespace ImGuiWindowFlags {
    constexpr int None = 0;
    constexpr int NoTitleBar = 1 << 0;
    constexpr int NoResize = 1 << 1;
    constexpr int NoMove = 1 << 2;
    constexpr int NoScrollbar = 1 << 3;
    constexpr int NoScrollWithMouse = 1 << 4;
    constexpr int NoCollapse = 1 << 5;
    constexpr int AlwaysAutoResize = 1 << 6;
    constexpr int NoBackground = 1 << 7;
    constexpr int NoSavedSettings = 1 << 8;
    constexpr int NoMouseInputs = 1 << 9;
    constexpr int MenuBar = 1 << 10;
    constexpr int HorizontalScrollbar = 1 << 11;
    constexpr int NoFocusOnAppearing = 1 << 12;
    constexpr int NoBringToFrontOnFocus = 1 << 13;
    constexpr int AlwaysVerticalScrollbar = 1 << 14;
    constexpr int AlwaysHorizontalScrollbar = 1 << 15;
    constexpr int NoNavInputs = 1 << 16;
    constexpr int NoNavFocus = 1 << 17;
}

namespace ImGuiCol {
    constexpr int Text = 0;
    constexpr int TextDisabled = 1;
    constexpr int WindowBg = 2;
    constexpr int ChildBg = 3;
    constexpr int PopupBg = 4;
    constexpr int Border = 5;
    constexpr int BorderShadow = 6;
    constexpr int FrameBg = 7;
    constexpr int FrameBgHovered = 8;
    constexpr int FrameBgActive = 9;
    constexpr int TitleBg = 10;
    constexpr int TitleBgActive = 11;
    constexpr int TitleBgCollapsed = 12;
    constexpr int MenuBarBg = 13;
    constexpr int ScrollbarBg = 14;
    constexpr int ScrollbarGrab = 15;
    constexpr int ScrollbarGrabHovered = 16;
    constexpr int ScrollbarGrabActive = 17;
    constexpr int CheckMark = 18;
    constexpr int SliderGrab = 19;
    constexpr int SliderGrabActive = 20;
    constexpr int Button = 21;
    constexpr int ButtonHovered = 22;
    constexpr int ButtonActive = 23;
    constexpr int Header = 24;
    constexpr int HeaderHovered = 25;
    constexpr int HeaderActive = 26;
    constexpr int Separator = 27;
    constexpr int SeparatorHovered = 28;
    constexpr int SeparatorActive = 29;
    constexpr int ResizeGrip = 30;
    constexpr int ResizeGripHovered = 31;
    constexpr int ResizeGripActive = 32;
    constexpr int Tab = 33;
    constexpr int TabHovered = 34;
    constexpr int TabActive = 35;
    constexpr int PlotLines = 40;
    constexpr int PlotLinesHovered = 41;
    constexpr int PlotHistogram = 42;
    constexpr int PlotHistogramHovered = 43;
    constexpr int TextSelectedBg = 45;
    constexpr int DragDropTarget = 46;
    constexpr int NavHighlight = 47;
}

namespace ImGuiStyleVar {
    constexpr int Alpha = 0;
    constexpr int WindowPadding = 1;
    constexpr int WindowRounding = 2;
    constexpr int WindowBorderSize = 3;
    constexpr int WindowMinSize = 4;
    constexpr int ChildRounding = 7;
    constexpr int ChildBorderSize = 8;
    constexpr int PopupRounding = 9;
    constexpr int PopupBorderSize = 10;
    constexpr int FramePadding = 11;
    constexpr int FrameRounding = 12;
    constexpr int FrameBorderSize = 13;
    constexpr int ItemSpacing = 14;
    constexpr int ItemInnerSpacing = 15;
    constexpr int CellPadding = 18;
    constexpr int ScrollbarSize = 19;
    constexpr int ScrollbarRounding = 20;
    constexpr int GrabMinSize = 21;
    constexpr int GrabRounding = 22;
    constexpr int ButtonTextAlign = 24;
    constexpr int SelectableTextAlign = 25;
}

namespace ImGuiTableFlags {
    constexpr int None = 0;
    constexpr int Resizable = 1 << 0;
    constexpr int Reorderable = 1 << 1;
    constexpr int Hideable = 1 << 2;
    constexpr int Sortable = 1 << 3;
    constexpr int Borders = 1 << 6;
    constexpr int BordersInner = 1 << 7;
    constexpr int BordersOuter = 1 << 8;
    constexpr int RowBg = 1 << 9;
    constexpr int ScrollX = 1 << 10;
    constexpr int ScrollY = 1 << 11;
    constexpr int SizingFixedFit = 1 << 13;
    constexpr int SizingStretchSame = 1 << 14;
}

namespace ImGuiDragDropFlags {
    constexpr int None = 0;
    constexpr int SourceNoPreviewTooltip = 1 << 0;
    constexpr int SourceNoDisableHover = 1 << 1;
    constexpr int SourceNoHoldToOpenOthers = 1 << 2;
    constexpr int SourceAllowNullID = 1 << 3;
    constexpr int SourceExtern = 1 << 4;
    constexpr int AcceptBeforeDelivery = 1 << 10;
    constexpr int AcceptNoDrawDefaultRect = 1 << 11;
    constexpr int AcceptPeekOnly = AcceptBeforeDelivery | AcceptNoDrawDefaultRect;
}

//------------------------------------------------------------------------------
// Theme Colors (SideFX style)
//------------------------------------------------------------------------------

#define SIDEFX_RGBA(r, g, b) (((r) << 24) | ((g) << 16) | ((b) << 8) | 0xFF)
#define SIDEFX_RGBA_A(r, g, b, a) (((r) << 24) | ((g) << 16) | ((b) << 8) | (a))

namespace Theme {
    // Background colors
    constexpr int WindowBg = SIDEFX_RGBA(0x1A, 0x1A, 0x1F);       // Very dark blue-gray
    constexpr int ChildBg = SIDEFX_RGBA(0x22, 0x22, 0x28);        // Slightly lighter
    constexpr int PopupBg = SIDEFX_RGBA(0x2A, 0x2A, 0x32);
    
    // Frame colors
    constexpr int FrameBg = SIDEFX_RGBA(0x30, 0x30, 0x3A);
    constexpr int FrameBgHovered = SIDEFX_RGBA(0x40, 0x40, 0x4A);
    constexpr int FrameBgActive = SIDEFX_RGBA(0x38, 0x38, 0x42);
    
    // Title bar
    constexpr int TitleBg = SIDEFX_RGBA(0x12, 0x12, 0x18);
    constexpr int TitleBgActive = SIDEFX_RGBA(0x18, 0x18, 0x22);
    
    // Text
    constexpr int Text = SIDEFX_RGBA(0xE8, 0xE8, 0xF0);
    constexpr int TextDim = SIDEFX_RGBA(0x88, 0x88, 0x98);
    constexpr int TextDisabled = SIDEFX_RGBA(0x58, 0x58, 0x68);
    
    // Accent colors - Electric cyan/teal
    constexpr int Accent = SIDEFX_RGBA(0x00, 0xD4, 0xE0);         // Bright cyan
    constexpr int AccentHovered = SIDEFX_RGBA(0x20, 0xE8, 0xF0);  // Lighter
    constexpr int AccentActive = SIDEFX_RGBA(0x00, 0xA8, 0xB8);   // Darker
    
    // Secondary accent - Purple/magenta
    constexpr int SecondaryAccent = SIDEFX_RGBA(0xA0, 0x60, 0xF0);
    constexpr int SecondaryHovered = SIDEFX_RGBA(0xB8, 0x78, 0xFF);
    
    // Button colors
    constexpr int Button = SIDEFX_RGBA(0x38, 0x38, 0x44);
    constexpr int ButtonHovered = SIDEFX_RGBA(0x48, 0x48, 0x58);
    constexpr int ButtonActive = SIDEFX_RGBA(0x30, 0x30, 0x3C);
    
    // Header/Selection
    constexpr int Header = SIDEFX_RGBA(0x30, 0x50, 0x60);
    constexpr int HeaderHovered = SIDEFX_RGBA(0x40, 0x68, 0x78);
    constexpr int HeaderActive = SIDEFX_RGBA(0x35, 0x58, 0x68);
    
    // Border
    constexpr int Border = SIDEFX_RGBA(0x40, 0x40, 0x50);
    constexpr int BorderLight = SIDEFX_RGBA(0x58, 0x58, 0x68);
    
    // Status colors
    constexpr int Success = SIDEFX_RGBA(0x40, 0xC0, 0x60);
    constexpr int Warning = SIDEFX_RGBA(0xE0, 0xA0, 0x20);
    constexpr int Error = SIDEFX_RGBA(0xE0, 0x40, 0x40);
    
    // FX specific
    constexpr int FxEnabled = SIDEFX_RGBA(0x60, 0xE0, 0x80);
    constexpr int FxBypassed = SIDEFX_RGBA(0x80, 0x60, 0x60);
    constexpr int ContainerBg = SIDEFX_RGBA(0x28, 0x28, 0x35);
    
    // Modulator colors
    constexpr int ModulatorActive = SIDEFX_RGBA(0x00, 0xE0, 0xA0);
    constexpr int ModulatorIdle = SIDEFX_RGBA(0x60, 0x60, 0x70);
    constexpr int CurveColor = SIDEFX_RGBA(0x00, 0xD4, 0xE0);
    constexpr int CurvePoint = SIDEFX_RGBA(0xFF, 0xFF, 0xFF);
    constexpr int CurvePointHover = SIDEFX_RGBA(0x00, 0xE8, 0xF0);
}

//------------------------------------------------------------------------------
// Initialization
//------------------------------------------------------------------------------

// Load all ReaImGui function pointers from REAPER
bool InitializeReaImGui(reaper_plugin_info_t* rec);

// Check if ReaImGui is available
bool IsReaImGuiAvailable();

} // namespace sidefx

