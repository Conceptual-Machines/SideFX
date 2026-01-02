#include "reaimgui_api.h"
#include <cstddef>

namespace sidefx {

//------------------------------------------------------------------------------
// Function Pointer Definitions
//------------------------------------------------------------------------------

// Context management
void* (*ImGui_CreateContext)(const char* label, int* config_flagsInOptional) = nullptr;
void (*ImGui_DestroyContext)(void* ctx) = nullptr;

// Window management
bool (*ImGui_Begin)(void* ctx, const char* name, bool* p_openInOutOptional, int* flagsInOptional) = nullptr;
void (*ImGui_End)(void* ctx) = nullptr;
void (*ImGui_SetNextWindowSize)(void* ctx, double size_w, double size_h, int* condInOptional) = nullptr;
void (*ImGui_SetNextWindowPos)(void* ctx, double pos_x, double pos_y, int* condInOptional, double* pivot_xInOptional, double* pivot_yInOptional) = nullptr;
bool (*ImGui_IsWindowAppearing)(void* ctx) = nullptr;
void (*ImGui_GetWindowSize)(void* ctx, double* wOut, double* hOut) = nullptr;
void (*ImGui_GetContentRegionAvail)(void* ctx, double* wOut, double* hOut) = nullptr;

// Text
void (*ImGui_Text)(void* ctx, const char* text) = nullptr;
void (*ImGui_TextColored)(void* ctx, int col_rgba, const char* text) = nullptr;
void (*ImGui_TextWrapped)(void* ctx, const char* text) = nullptr;

// Buttons
bool (*ImGui_Button)(void* ctx, const char* label, double* size_wInOptional, double* size_hInOptional) = nullptr;
bool (*ImGui_SmallButton)(void* ctx, const char* label) = nullptr;
bool (*ImGui_InvisibleButton)(void* ctx, const char* str_id, double size_w, double size_h, int* flagsInOptional) = nullptr;

// Checkboxes
bool (*ImGui_Checkbox)(void* ctx, const char* label, bool* v) = nullptr;

// Sliders
bool (*ImGui_SliderDouble)(void* ctx, const char* label, double* v, double v_min, double v_max, const char* formatInOptional, int* flagsInOptional) = nullptr;
bool (*ImGui_SliderInt)(void* ctx, const char* label, int* v, int v_min, int v_max, const char* formatInOptional, int* flagsInOptional) = nullptr;

// Input
bool (*ImGui_InputText)(void* ctx, const char* label, char* buf, int buf_size, int* flagsInOptional, void* callbackInOptional) = nullptr;
bool (*ImGui_InputTextWithHint)(void* ctx, const char* label, const char* hint, char* buf, int buf_size, int* flagsInOptional, void* callbackInOptional) = nullptr;
bool (*ImGui_InputDouble)(void* ctx, const char* label, double* v, double* stepInOptional, double* step_fastInOptional, const char* formatInOptional, int* flagsInOptional) = nullptr;
bool (*ImGui_InputInt)(void* ctx, const char* label, int* v, int* stepInOptional, int* step_fastInOptional, int* flagsInOptional) = nullptr;

// Combo/Dropdown
bool (*ImGui_BeginCombo)(void* ctx, const char* label, const char* preview_value, int* flagsInOptional) = nullptr;
void (*ImGui_EndCombo)(void* ctx) = nullptr;
bool (*ImGui_Selectable)(void* ctx, const char* label, bool* p_selectedInOut, int* flagsInOptional, double* size_wInOptional, double* size_hInOptional) = nullptr;

// Layout
void (*ImGui_SameLine)(void* ctx, double* offset_from_start_xInOptional, double* spacingInOptional) = nullptr;
void (*ImGui_Separator)(void* ctx) = nullptr;
void (*ImGui_Spacing)(void* ctx) = nullptr;
void (*ImGui_NewLine)(void* ctx) = nullptr;
void (*ImGui_Dummy)(void* ctx, double size_w, double size_h) = nullptr;
void (*ImGui_Indent)(void* ctx, double* indent_wInOptional) = nullptr;
void (*ImGui_Unindent)(void* ctx, double* indent_wInOptional) = nullptr;
void (*ImGui_PushItemWidth)(void* ctx, double item_width) = nullptr;
void (*ImGui_PopItemWidth)(void* ctx) = nullptr;

// Table
bool (*ImGui_BeginTable)(void* ctx, const char* str_id, int column, int* flagsInOptional, double* outer_size_wInOptional, double* outer_size_hInOptional, double* inner_widthInOptional) = nullptr;
void (*ImGui_EndTable)(void* ctx) = nullptr;
void (*ImGui_TableNextRow)(void* ctx, int* row_flagsInOptional, double* min_row_heightInOptional) = nullptr;
bool (*ImGui_TableNextColumn)(void* ctx) = nullptr;
bool (*ImGui_TableSetColumnIndex)(void* ctx, int column_n) = nullptr;
void (*ImGui_TableSetupColumn)(void* ctx, const char* label, int* flagsInOptional, double* init_width_or_weightInOptional, int* user_idInOptional) = nullptr;
void (*ImGui_TableHeadersRow)(void* ctx) = nullptr;

// Child windows
bool (*ImGui_BeginChild)(void* ctx, const char* str_id, double* size_wInOptional, double* size_hInOptional, int* child_flagsInOptional, int* window_flagsInOptional) = nullptr;
void (*ImGui_EndChild)(void* ctx) = nullptr;

// Scrolling
void (*ImGui_SetScrollHereY)(void* ctx, double* center_y_ratioInOptional) = nullptr;
double (*ImGui_GetScrollY)(void* ctx) = nullptr;
double (*ImGui_GetScrollMaxY)(void* ctx) = nullptr;

// Styling
void (*ImGui_PushStyleColor)(void* ctx, int idx, int col_rgba) = nullptr;
void (*ImGui_PopStyleColor)(void* ctx, int* countInOptional) = nullptr;
void (*ImGui_PushStyleVar)(void* ctx, int idx, double val) = nullptr;
void (*ImGui_PushStyleVar2)(void* ctx, int idx, double val_x, double val_y) = nullptr;
void (*ImGui_PopStyleVar)(void* ctx, int* countInOptional) = nullptr;

// IDs
void (*ImGui_PushID)(void* ctx, const char* str_id) = nullptr;
void (*ImGui_PopID)(void* ctx) = nullptr;

// Keyboard focus
void (*ImGui_SetKeyboardFocusHere)(void* ctx, int* offsetInOptional) = nullptr;

// Drag & Drop
bool (*ImGui_BeginDragDropSource)(void* ctx, int* flagsInOptional) = nullptr;
bool (*ImGui_SetDragDropPayload)(void* ctx, const char* type, const char* data, int* condInOptional) = nullptr;
void (*ImGui_EndDragDropSource)(void* ctx) = nullptr;
bool (*ImGui_BeginDragDropTarget)(void* ctx) = nullptr;
bool (*ImGui_AcceptDragDropPayload)(void* ctx, const char* type, int* flagsInOptional, const char** dataOut, int* sizeOut) = nullptr;
void (*ImGui_EndDragDropTarget)(void* ctx) = nullptr;

// Drawing
void* (*ImGui_GetWindowDrawList)(void* ctx) = nullptr;
void (*ImGui_DrawList_AddLine)(void* draw_list, double p1_x, double p1_y, double p2_x, double p2_y, int col_rgba, double* thicknessInOptional) = nullptr;
void (*ImGui_DrawList_AddRect)(void* draw_list, double p_min_x, double p_min_y, double p_max_x, double p_max_y, int col_rgba, double* roundingInOptional, int* flagsInOptional, double* thicknessInOptional) = nullptr;
void (*ImGui_DrawList_AddRectFilled)(void* draw_list, double p_min_x, double p_min_y, double p_max_x, double p_max_y, int col_rgba, double* roundingInOptional, int* flagsInOptional) = nullptr;
void (*ImGui_DrawList_AddCircle)(void* draw_list, double center_x, double center_y, double radius, int col_rgba, int* num_segmentsInOptional, double* thicknessInOptional) = nullptr;
void (*ImGui_DrawList_AddCircleFilled)(void* draw_list, double center_x, double center_y, double radius, int col_rgba, int* num_segmentsInOptional) = nullptr;
void (*ImGui_DrawList_AddBezierCubic)(void* draw_list, double p1_x, double p1_y, double p2_x, double p2_y, double p3_x, double p3_y, double p4_x, double p4_y, int col_rgba, double thickness, int* num_segmentsInOptional) = nullptr;
void (*ImGui_DrawList_AddText)(void* draw_list, double x, double y, int col_rgba, const char* text) = nullptr;

// Cursor position
void (*ImGui_GetCursorScreenPos)(void* ctx, double* xOut, double* yOut) = nullptr;
void (*ImGui_GetCursorPos)(void* ctx, double* xOut, double* yOut) = nullptr;
void (*ImGui_SetCursorPos)(void* ctx, double local_x, double local_y) = nullptr;
void (*ImGui_SetCursorPosX)(void* ctx, double local_x) = nullptr;
void (*ImGui_SetCursorPosY)(void* ctx, double local_y) = nullptr;

// Mouse
bool (*ImGui_IsItemHovered)(void* ctx, int* flagsInOptional) = nullptr;
bool (*ImGui_IsItemClicked)(void* ctx, int* mouse_buttonInOptional) = nullptr;
bool (*ImGui_IsItemActive)(void* ctx) = nullptr;
bool (*ImGui_IsMouseDown)(void* ctx, int button) = nullptr;
bool (*ImGui_IsMouseClicked)(void* ctx, int button, bool* repeatInOptional) = nullptr;
bool (*ImGui_IsMouseDoubleClicked)(void* ctx, int button) = nullptr;
void (*ImGui_GetMousePos)(void* ctx, double* xOut, double* yOut) = nullptr;
void (*ImGui_GetMouseDelta)(void* ctx, double* xOut, double* yOut) = nullptr;

// Tooltips
bool (*ImGui_BeginTooltip)(void* ctx) = nullptr;
void (*ImGui_EndTooltip)(void* ctx) = nullptr;
void (*ImGui_SetTooltip)(void* ctx, const char* text) = nullptr;

// Popups
bool (*ImGui_BeginPopup)(void* ctx, const char* str_id, int* flagsInOptional) = nullptr;
bool (*ImGui_BeginPopupContextItem)(void* ctx, const char* str_idInOptional, int* popup_flagsInOptional) = nullptr;
void (*ImGui_EndPopup)(void* ctx) = nullptr;
void (*ImGui_OpenPopup)(void* ctx, const char* str_id, int* popup_flagsInOptional) = nullptr;
void (*ImGui_CloseCurrentPopup)(void* ctx) = nullptr;

// Menu
bool (*ImGui_BeginMenuBar)(void* ctx) = nullptr;
void (*ImGui_EndMenuBar)(void* ctx) = nullptr;
bool (*ImGui_BeginMenu)(void* ctx, const char* label, bool* enabledInOptional) = nullptr;
void (*ImGui_EndMenu)(void* ctx) = nullptr;
bool (*ImGui_MenuItem)(void* ctx, const char* label, const char* shortcutInOptional, bool* p_selectedInOptional, bool* enabledInOptional) = nullptr;

// Tree nodes
bool (*ImGui_TreeNode)(void* ctx, const char* label, int* flagsInOptional) = nullptr;
bool (*ImGui_TreeNodeEx)(void* ctx, const char* str_id, int flags, const char* label) = nullptr;
void (*ImGui_TreePop)(void* ctx) = nullptr;
void (*ImGui_SetNextItemOpen)(void* ctx, bool is_open, int* condInOptional) = nullptr;

// Color
bool (*ImGui_ColorEdit4)(void* ctx, const char* label, int* col_rgbaInOut, int* flagsInOptional) = nullptr;

//------------------------------------------------------------------------------
// State
//------------------------------------------------------------------------------

static bool g_reaimguiAvailable = false;

//------------------------------------------------------------------------------
// Helper macro for loading functions
//------------------------------------------------------------------------------

#define LOAD_IMGUI_FUNC(name) \
    name = (decltype(name))rec->GetFunc(#name); \
    if (!name) { \
        /* Some functions may be optional, don't fail completely */ \
    }

//------------------------------------------------------------------------------
// Initialize ReaImGui API
//------------------------------------------------------------------------------

bool InitializeReaImGui(reaper_plugin_info_t* rec) {
    if (!rec || !rec->GetFunc) {
        return false;
    }

    // Get ShowConsoleMsg for debug output
    void (*ShowConsoleMsg)(const char* msg) = 
        (void (*)(const char*))rec->GetFunc("ShowConsoleMsg");
    
    if (ShowConsoleMsg) {
        ShowConsoleMsg("[SideFX Mod] Initializing ReaImGui API...\n");
    }

    // Core functions (required)
    LOAD_IMGUI_FUNC(ImGui_CreateContext);
    LOAD_IMGUI_FUNC(ImGui_DestroyContext);
    LOAD_IMGUI_FUNC(ImGui_Begin);
    LOAD_IMGUI_FUNC(ImGui_End);

    // Debug: show which core functions loaded
    if (ShowConsoleMsg) {
        char buf[256];
        snprintf(buf, sizeof(buf), 
            "[SideFX Mod] Core ImGui functions: CreateContext=%p, Begin=%p, End=%p\n",
            (void*)ImGui_CreateContext, (void*)ImGui_Begin, (void*)ImGui_End);
        ShowConsoleMsg(buf);
    }

    // Check if core functions are available
    if (!ImGui_CreateContext || !ImGui_Begin || !ImGui_End) {
        g_reaimguiAvailable = false;
        return false;
    }

    // Window functions
    LOAD_IMGUI_FUNC(ImGui_SetNextWindowSize);
    LOAD_IMGUI_FUNC(ImGui_SetNextWindowPos);
    LOAD_IMGUI_FUNC(ImGui_IsWindowAppearing);
    LOAD_IMGUI_FUNC(ImGui_GetWindowSize);
    LOAD_IMGUI_FUNC(ImGui_GetContentRegionAvail);

    // Text functions
    LOAD_IMGUI_FUNC(ImGui_Text);
    LOAD_IMGUI_FUNC(ImGui_TextColored);
    LOAD_IMGUI_FUNC(ImGui_TextWrapped);

    // Button functions
    LOAD_IMGUI_FUNC(ImGui_Button);
    LOAD_IMGUI_FUNC(ImGui_SmallButton);
    LOAD_IMGUI_FUNC(ImGui_InvisibleButton);

    // Input functions
    LOAD_IMGUI_FUNC(ImGui_Checkbox);
    LOAD_IMGUI_FUNC(ImGui_SliderDouble);
    LOAD_IMGUI_FUNC(ImGui_SliderInt);
    LOAD_IMGUI_FUNC(ImGui_InputText);
    LOAD_IMGUI_FUNC(ImGui_InputTextWithHint);
    LOAD_IMGUI_FUNC(ImGui_InputDouble);
    LOAD_IMGUI_FUNC(ImGui_InputInt);

    // Combo
    LOAD_IMGUI_FUNC(ImGui_BeginCombo);
    LOAD_IMGUI_FUNC(ImGui_EndCombo);
    LOAD_IMGUI_FUNC(ImGui_Selectable);

    // Layout
    LOAD_IMGUI_FUNC(ImGui_SameLine);
    LOAD_IMGUI_FUNC(ImGui_Separator);
    LOAD_IMGUI_FUNC(ImGui_Spacing);
    LOAD_IMGUI_FUNC(ImGui_NewLine);
    LOAD_IMGUI_FUNC(ImGui_Dummy);
    LOAD_IMGUI_FUNC(ImGui_Indent);
    LOAD_IMGUI_FUNC(ImGui_Unindent);
    LOAD_IMGUI_FUNC(ImGui_PushItemWidth);
    LOAD_IMGUI_FUNC(ImGui_PopItemWidth);

    // Tables
    LOAD_IMGUI_FUNC(ImGui_BeginTable);
    LOAD_IMGUI_FUNC(ImGui_EndTable);
    LOAD_IMGUI_FUNC(ImGui_TableNextRow);
    LOAD_IMGUI_FUNC(ImGui_TableNextColumn);
    LOAD_IMGUI_FUNC(ImGui_TableSetColumnIndex);
    LOAD_IMGUI_FUNC(ImGui_TableSetupColumn);
    LOAD_IMGUI_FUNC(ImGui_TableHeadersRow);

    // Child windows
    LOAD_IMGUI_FUNC(ImGui_BeginChild);
    LOAD_IMGUI_FUNC(ImGui_EndChild);

    // Scrolling
    LOAD_IMGUI_FUNC(ImGui_SetScrollHereY);
    LOAD_IMGUI_FUNC(ImGui_GetScrollY);
    LOAD_IMGUI_FUNC(ImGui_GetScrollMaxY);

    // Styling
    LOAD_IMGUI_FUNC(ImGui_PushStyleColor);
    LOAD_IMGUI_FUNC(ImGui_PopStyleColor);
    LOAD_IMGUI_FUNC(ImGui_PushStyleVar);
    LOAD_IMGUI_FUNC(ImGui_PushStyleVar2);
    LOAD_IMGUI_FUNC(ImGui_PopStyleVar);

    // IDs
    LOAD_IMGUI_FUNC(ImGui_PushID);
    LOAD_IMGUI_FUNC(ImGui_PopID);

    // Focus
    LOAD_IMGUI_FUNC(ImGui_SetKeyboardFocusHere);

    // Drag & Drop
    LOAD_IMGUI_FUNC(ImGui_BeginDragDropSource);
    LOAD_IMGUI_FUNC(ImGui_SetDragDropPayload);
    LOAD_IMGUI_FUNC(ImGui_EndDragDropSource);
    LOAD_IMGUI_FUNC(ImGui_BeginDragDropTarget);
    LOAD_IMGUI_FUNC(ImGui_AcceptDragDropPayload);
    LOAD_IMGUI_FUNC(ImGui_EndDragDropTarget);

    // Drawing
    LOAD_IMGUI_FUNC(ImGui_GetWindowDrawList);
    LOAD_IMGUI_FUNC(ImGui_DrawList_AddLine);
    LOAD_IMGUI_FUNC(ImGui_DrawList_AddRect);
    LOAD_IMGUI_FUNC(ImGui_DrawList_AddRectFilled);
    LOAD_IMGUI_FUNC(ImGui_DrawList_AddCircle);
    LOAD_IMGUI_FUNC(ImGui_DrawList_AddCircleFilled);
    LOAD_IMGUI_FUNC(ImGui_DrawList_AddBezierCubic);
    LOAD_IMGUI_FUNC(ImGui_DrawList_AddText);

    // Cursor
    LOAD_IMGUI_FUNC(ImGui_GetCursorScreenPos);
    LOAD_IMGUI_FUNC(ImGui_GetCursorPos);
    LOAD_IMGUI_FUNC(ImGui_SetCursorPos);
    LOAD_IMGUI_FUNC(ImGui_SetCursorPosX);
    LOAD_IMGUI_FUNC(ImGui_SetCursorPosY);

    // Mouse
    LOAD_IMGUI_FUNC(ImGui_IsItemHovered);
    LOAD_IMGUI_FUNC(ImGui_IsItemClicked);
    LOAD_IMGUI_FUNC(ImGui_IsItemActive);
    LOAD_IMGUI_FUNC(ImGui_IsMouseDown);
    LOAD_IMGUI_FUNC(ImGui_IsMouseClicked);
    LOAD_IMGUI_FUNC(ImGui_IsMouseDoubleClicked);
    LOAD_IMGUI_FUNC(ImGui_GetMousePos);
    LOAD_IMGUI_FUNC(ImGui_GetMouseDelta);

    // Tooltips
    LOAD_IMGUI_FUNC(ImGui_BeginTooltip);
    LOAD_IMGUI_FUNC(ImGui_EndTooltip);
    LOAD_IMGUI_FUNC(ImGui_SetTooltip);

    // Popups
    LOAD_IMGUI_FUNC(ImGui_BeginPopup);
    LOAD_IMGUI_FUNC(ImGui_BeginPopupContextItem);
    LOAD_IMGUI_FUNC(ImGui_EndPopup);
    LOAD_IMGUI_FUNC(ImGui_OpenPopup);
    LOAD_IMGUI_FUNC(ImGui_CloseCurrentPopup);

    // Menu
    LOAD_IMGUI_FUNC(ImGui_BeginMenuBar);
    LOAD_IMGUI_FUNC(ImGui_EndMenuBar);
    LOAD_IMGUI_FUNC(ImGui_BeginMenu);
    LOAD_IMGUI_FUNC(ImGui_EndMenu);
    LOAD_IMGUI_FUNC(ImGui_MenuItem);

    // Tree
    LOAD_IMGUI_FUNC(ImGui_TreeNode);
    LOAD_IMGUI_FUNC(ImGui_TreeNodeEx);
    LOAD_IMGUI_FUNC(ImGui_TreePop);
    LOAD_IMGUI_FUNC(ImGui_SetNextItemOpen);

    // Color
    LOAD_IMGUI_FUNC(ImGui_ColorEdit4);

    g_reaimguiAvailable = true;
    return true;
}

bool IsReaImGuiAvailable() {
    return g_reaimguiAvailable;
}

} // namespace sidefx

