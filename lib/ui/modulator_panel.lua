--- Modulator Panel UI Component
-- Shows modulator FX and their parameter links
-- @module ui.modulator_panel
-- @author Nomad Monad
-- @license MIT

local imgui = require('imgui')

local M = {}

--------------------------------------------------------------------------------
-- Modulator Panel
--------------------------------------------------------------------------------

--- Draw modulator panel
-- @param ctx ImGui context wrapper
-- @param width number Width of the panel
-- @param state table State object
-- @param callbacks table Callbacks:
--   - find_modulators_on_track: () -> table Array of modulator data
--   - get_linkable_fx: () -> table Array of linkable FX
--   - get_modulator_links: (fx_idx) -> table Array of links
--   - create_param_link: (mod_fx_idx, target_fx_idx, target_param_idx) -> nil
--   - remove_param_link: (target_fx_idx, target_param_idx) -> nil
--   - add_modulator: () -> nil
--   - delete_modulator: (fx_idx) -> nil
function M.draw(ctx, width, state, callbacks)
    if ctx:begin_child("Modulators", width, 0, imgui.ChildFlags.Border()) then
        ctx:text("Modulators")
        ctx:same_line()
        if ctx:small_button("+ Add") then
            callbacks.add_modulator()
        end
        ctx:separator()

        if not state.track then
            ctx:text_colored(0x888888FF, "Select a track")
            ctx:end_child()
            return
        end

        local modulators = callbacks.find_modulators_on_track()

        if #modulators == 0 then
            ctx:text_colored(0x888888FF, "No modulators")
            ctx:text_colored(0x666666FF, "Click '+ Add'")
        else
            local linkable_fx = callbacks.get_linkable_fx()

            for i, mod in ipairs(modulators) do
                ctx:push_id("mod_" .. mod.fx_idx)

                -- Header row: buttons first, then name
                -- Show UI button
                if ctx:small_button("UI##ui_" .. mod.fx_idx) then
                    mod.fx:show(3)
                end
                ctx:same_line()

                -- Delete button
                ctx:push_style_color(imgui.Col.Button(), 0x993333FF)
                if ctx:small_button("X##del_" .. mod.fx_idx) then
                    ctx:pop_style_color()
                    ctx:pop_id()
                    callbacks.delete_modulator(mod.fx_idx)
                    ctx:end_child()
                    return
                end
                ctx:pop_style_color()
                ctx:same_line()

                -- Modulator name as collapsing header
                ctx:push_style_color(imgui.Col.Header(), 0x445566FF)
                ctx:push_style_color(imgui.Col.HeaderHovered(), 0x556677FF)
                local header_open = ctx:collapsing_header(mod.name, imgui.TreeNodeFlags.DefaultOpen())
                ctx:pop_style_color(2)

                if header_open then
                    -- Show existing links
                    local links = callbacks.get_modulator_links(mod.fx_idx)
                    if #links > 0 then
                        ctx:text_colored(0xAAAAAAFF, "Links:")
                        for _, link in ipairs(links) do
                            ctx:push_id("link_" .. link.target_fx_idx .. "_" .. link.target_param_idx)

                            -- Truncate names to fit
                            local fx_short = link.target_fx_name:sub(1, 15)
                            local param_short = link.target_param_name:sub(1, 12)

                            ctx:text_colored(0x88CC88FF, "→")
                            ctx:same_line()
                            ctx:text_wrapped(fx_short .. " : " .. param_short)
                            ctx:same_line(width - 30)

                            -- Remove link button
                            ctx:push_style_color(imgui.Col.Button(), 0x664444FF)
                            if ctx:small_button("×") then
                                callbacks.remove_param_link(link.target_fx_idx, link.target_param_idx)
                            end
                            ctx:pop_style_color()

                            ctx:pop_id()
                        end
                        ctx:spacing()
                    end

                    -- Two dropdowns to add new link
                    ctx:text_colored(0xAAAAAAFF, "+ Add link:")

                    -- Get current selection for this modulator
                    local selected_target = state.mod_selected_target[mod.fx_idx]
                    local fx_preview = selected_target and selected_target.name or "Select FX..."

                    -- Dropdown 1: Select target FX
                    ctx:set_next_item_width(width - 20)
                    if ctx:begin_combo("##targetfx_" .. i, fx_preview) then
                        for _, fx in ipairs(linkable_fx) do
                            if ctx:selectable(fx.name .. "##fx_" .. fx.fx_idx) then
                                state.mod_selected_target[mod.fx_idx] = {
                                    fx_idx = fx.fx_idx,
                                    name = fx.name,
                                    params = fx.params
                                }
                            end
                        end
                        ctx:end_combo()
                    end

                    -- Dropdown 2: Select parameter (only if FX is selected)
                    if selected_target then
                        ctx:set_next_item_width(width - 20)
                        if ctx:begin_combo("##targetparam_" .. i, "Select param...") then
                            for _, param in ipairs(selected_target.params) do
                                if ctx:selectable(param.name .. "##p_" .. param.idx) then
                                    callbacks.create_param_link(mod.fx_idx, selected_target.fx_idx, param.idx)
                                    -- Clear selection after linking
                                    state.mod_selected_target[mod.fx_idx] = nil
                                end
                            end
                            ctx:end_combo()
                        end
                    end
                end

                ctx:spacing()
                ctx:separator()
                ctx:pop_id()
            end
        end

        ctx:end_child()
    end
end

return M

