--- Rack Panel UI Component
-- Renders a parallel rack container with stacked chains.
-- @module ui.rack_panel
-- @author Nomad Monad
-- @license MIT

local r = reaper

local M = {}

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

M.config = {
    rack_min_width = 480,
    chain_row_height = 40,
    chain_label_width = 100,
    header_height = 36,
    volume_width = 80,
    border_radius = 6,
}

-- Colors
M.colors = {
    rack_bg = 0x252530FF,
    rack_border = 0x445566FF,
    rack_header = 0x334455FF,
    chain_bg = 0x2A2A35FF,
    chain_bg_alt = 0x2E2E38FF,
    chain_label = 0xAABBCCFF,
    text = 0xDDDDDDFF,
    text_dim = 0x888888FF,
    add_chain = 0x446688FF,
}

--------------------------------------------------------------------------------
-- Rack Panel Component
--------------------------------------------------------------------------------

--- Draw a rack container (expanded view).
-- @param ctx ImGui context wrapper  
-- @param container ReaWrap FX object (container)
-- @param chains table Array of chain data: {name, fx_list, output_channels, volume}
-- @param opts table Options {on_add_chain, on_remove_chain, on_chain_volume, ...}
-- @return boolean True if interacted
function M.draw(ctx, container, chains, opts)
    opts = opts or {}
    local cfg = M.config
    local colors = M.colors
    
    if not container then return false end
    
    local guid = container:get_guid()
    local rack_name = container:get_name()
    -- Strip "Container" prefix for cleaner display
    rack_name = rack_name:gsub("^Container", ""):gsub("^%s*", "")
    if rack_name == "" then rack_name = "Rack" end
    
    local interacted = false
    local chain_count = #chains
    
    -- Calculate rack dimensions
    local rack_height = cfg.header_height + (chain_count * cfg.chain_row_height) + 16
    rack_height = math.max(rack_height, 80)
    
    -- Calculate content width based on longest chain
    local max_fx_count = 0
    for _, chain in ipairs(chains) do
        max_fx_count = math.max(max_fx_count, #chain.fx_list)
    end
    local content_width = cfg.chain_label_width + (max_fx_count * 128) + cfg.volume_width + 60
    local rack_width = math.max(cfg.rack_min_width, content_width)
    
    ctx:push_id("rack_" .. guid)
    
    -- Rack frame
    local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(ctx.ctx)
    local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)
    
    r.ImGui_DrawList_AddRectFilled(draw_list,
        cursor_x, cursor_y,
        cursor_x + rack_width, cursor_y + rack_height,
        colors.rack_bg, cfg.border_radius)
    r.ImGui_DrawList_AddRect(draw_list,
        cursor_x, cursor_y,
        cursor_x + rack_width, cursor_y + rack_height,
        colors.rack_border, cfg.border_radius, 0, 2)
    
    if ctx:begin_child("rack_content_" .. guid, rack_width, rack_height, 0) then
        -- Header
        r.ImGui_DrawList_AddRectFilled(draw_list,
            cursor_x, cursor_y,
            cursor_x + rack_width, cursor_y + cfg.header_height,
            colors.rack_header, cfg.border_radius)
        
        -- Collapse/expand arrow (placeholder - would need state management)
        ctx:text("▼")
        ctx:same_line()
        
        -- Rack name
        ctx:text(rack_name)
        
        -- Add Chain button (right side)
        ctx:same_line(rack_width - 100)
        ctx:push_style_color(r.ImGui_Col_Button(), colors.add_chain)
        if ctx:small_button("+ Chain") then
            if opts.on_add_chain then
                opts.on_add_chain(container)
            end
            interacted = true
        end
        ctx:pop_style_color()
        
        -- Close button
        ctx:same_line(rack_width - 30)
        ctx:push_style_color(r.ImGui_Col_Button(), 0x00000000)
        ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x663333FF)
        if ctx:small_button("×##close_rack") then
            if opts.on_delete then
                opts.on_delete(container)
            end
            interacted = true
        end
        ctx:pop_style_color(2)
        
        ctx:separator()
        
        -- Chain rows
        for i, chain in ipairs(chains) do
            ctx:push_id("chain_" .. i)
            
            local row_color = (i % 2 == 0) and colors.chain_bg_alt or colors.chain_bg
            local row_y = cursor_y + cfg.header_height + ((i - 1) * cfg.chain_row_height)
            
            r.ImGui_DrawList_AddRectFilled(draw_list,
                cursor_x, row_y,
                cursor_x + rack_width, row_y + cfg.chain_row_height,
                row_color)
            
            -- Chain label
            ctx:push_style_color(r.ImGui_Col_Text(), colors.chain_label)
            local chain_label = chain.name or ("Chain " .. i)
            ctx:text(chain_label)
            ctx:pop_style_color()
            
            -- FX chain (horizontal)
            ctx:same_line(cfg.chain_label_width)
            
            if #chain.fx_list == 0 then
                ctx:text_disabled("(empty - drag FX here)")
            else
                for j, fx in ipairs(chain.fx_list) do
                    if j > 1 then
                        ctx:same_line()
                        ctx:push_style_color(r.ImGui_Col_Text(), colors.text_dim)
                        ctx:text("→")
                        ctx:pop_style_color()
                        ctx:same_line()
                    end
                    
                    -- Compact FX button
                    local fx_name = fx:get_name():sub(1, 12)
                    local enabled = fx:get_enabled()
                    local btn_color = enabled and 0x3A4A5AFF or 0x2A2A35FF
                    
                    ctx:push_style_color(r.ImGui_Col_Button(), btn_color)
                    if ctx:small_button(fx_name .. "##fx_" .. j) then
                        fx:show(3)  -- Open native UI
                        interacted = true
                    end
                    ctx:pop_style_color()
                    
                    if ctx:is_item_hovered() then
                        ctx:set_tooltip(fx:get_name())
                    end
                end
            end
            
            -- Volume slider (right side)
            ctx:same_line(rack_width - cfg.volume_width - 20)
            ctx:set_next_item_width(cfg.volume_width)
            local vol = chain.volume or 1.0
            local vol_changed, new_vol = ctx:slider_double("##vol", vol, 0, 1, "%.0f%%")
            if vol_changed then
                if opts.on_chain_volume then
                    opts.on_chain_volume(i, new_vol)
                end
                interacted = true
            end
            
            ctx:pop_id()
        end
        
        -- Empty state
        if chain_count == 0 then
            ctx:spacing()
            ctx:text_disabled("No chains - click '+ Chain' to add")
        end
        
        ctx:end_child()
    end
    
    -- Drop target for adding FX to rack
    if ctx:begin_drag_drop_target() then
        local accepted, payload = ctx:accept_drag_drop_payload("FX_GUID")
        if accepted and payload then
            if opts.on_drop_fx then
                opts.on_drop_fx(container, payload)
            end
            interacted = true
        end
        ctx:end_drag_drop_target()
    end
    
    ctx:pop_id()
    
    return interacted
end

--------------------------------------------------------------------------------
-- Collapsed Rack (compact view)
--------------------------------------------------------------------------------

--- Draw a collapsed rack as a single device panel.
-- @param ctx ImGui context wrapper
-- @param container ReaWrap FX object
-- @param chain_count number Number of chains in rack
-- @param opts table Options
-- @return boolean True if clicked to expand
function M.draw_collapsed(ctx, container, chain_count, opts)
    opts = opts or {}
    local cfg = M.config
    local colors = M.colors
    
    if not container then return false end
    
    local guid = container:get_guid()
    local rack_name = container:get_name():gsub("^Container", ""):gsub("^%s*", "")
    if rack_name == "" then rack_name = "Rack" end
    
    local collapsed_width = 160
    local collapsed_height = 80
    
    ctx:push_id("rack_collapsed_" .. guid)
    
    -- Frame
    local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(ctx.ctx)
    local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)
    
    r.ImGui_DrawList_AddRectFilled(draw_list,
        cursor_x, cursor_y,
        cursor_x + collapsed_width, cursor_y + collapsed_height,
        colors.rack_bg, cfg.border_radius)
    r.ImGui_DrawList_AddRect(draw_list,
        cursor_x, cursor_y,
        cursor_x + collapsed_width, cursor_y + collapsed_height,
        colors.rack_border, cfg.border_radius, 0, 2)
    
    if ctx:begin_child("rack_coll_" .. guid, collapsed_width, collapsed_height, 0) then
        -- Expand arrow
        ctx:text("▶")
        ctx:same_line()
        ctx:text(rack_name)
        
        ctx:text_disabled(string.format("  %d chains", chain_count))
        
        -- Click to expand
        if ctx:invisible_button("expand_" .. guid, collapsed_width - 8, collapsed_height - 40) then
            if opts.on_expand then
                opts.on_expand(container)
            end
            ctx:end_child()
            ctx:pop_id()
            return true
        end
        
        ctx:end_child()
    end
    
    ctx:pop_id()
    
    return false
end

--------------------------------------------------------------------------------
-- Chain Row Component (for use inside racks)
--------------------------------------------------------------------------------

--- Draw a single chain row.
-- @param ctx ImGui context wrapper
-- @param chain table Chain data {name, fx_list, volume}
-- @param index number Chain index (1-based)
-- @param width number Available width
-- @param opts table Options
-- @return boolean True if interacted
function M.draw_chain_row(ctx, chain, index, width, opts)
    opts = opts or {}
    local cfg = M.config
    local colors = M.colors
    
    local interacted = false
    
    ctx:push_id("chain_row_" .. index)
    
    -- Chain label
    ctx:push_style_color(r.ImGui_Col_Text(), colors.chain_label)
    ctx:text(chain.name or ("Chain " .. index))
    ctx:pop_style_color()
    
    ctx:same_line(cfg.chain_label_width)
    
    -- FX buttons
    local device_panel = require('ui.device_panel')
    
    for i, fx in ipairs(chain.fx_list) do
        if i > 1 then
            ctx:same_line()
            ctx:text_disabled("→")
            ctx:same_line()
        end
        
        device_panel.draw_compact(ctx, fx, {
            on_click = opts.on_fx_click,
            on_drop = opts.on_fx_drop,
        })
        ctx:same_line()
    end
    
    -- Drop zone at end of chain
    ctx:push_style_color(r.ImGui_Col_Button(), 0x33445533)
    if ctx:button("+##add_fx_" .. index, 24, 20) then
        if opts.on_add_fx then
            opts.on_add_fx(index)
        end
        interacted = true
    end
    ctx:pop_style_color()
    if ctx:is_item_hovered() then
        ctx:set_tooltip("Add FX to chain")
    end
    
    -- Volume at end
    ctx:same_line(width - cfg.volume_width - 8)
    ctx:set_next_item_width(cfg.volume_width)
    local vol = chain.volume or 1.0
    local vol_changed, new_vol = ctx:slider_double("##vol_" .. index, vol, 0, 1, "%.0f%%")
    if vol_changed and opts.on_volume_change then
        opts.on_volume_change(index, new_vol)
        interacted = true
    end
    
    ctx:pop_id()
    
    return interacted
end

return M

