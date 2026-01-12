--- Simple JSON Serialization
-- Basic JSON encoding for Lua tables (no decoding needed for now)
-- @module json
-- @author Nomad Monad
-- @license MIT

local M = {}

--- Escape a string for JSON
local function escape_string(str)
    str = str:gsub("\\", "\\\\")
    str = str:gsub('"', '\\"')
    str = str:gsub("\n", "\\n")
    str = str:gsub("\r", "\\r")
    str = str:gsub("\t", "\\t")
    return str
end

--- Serialize a value to JSON
local function serialize_value(value, indent)
    indent = indent or 0
    local indent_str = string.rep("  ", indent)
    
    if type(value) == "string" then
        return '"' .. escape_string(value) .. '"'
    elseif type(value) == "number" then
        return tostring(value)
    elseif type(value) == "boolean" then
        return value and "true" or "false"
    elseif type(value) == "nil" then
        return "null"
    elseif type(value) == "table" then
        -- Check if it's an array (sequential numeric keys starting from 1)
        local is_array = true
        local max_key = 0
        for k, v in pairs(value) do
            if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then
                is_array = false
                break
            end
            if k > max_key then max_key = k end
        end
        
        if is_array and max_key > 0 then
            -- Array
            local parts = {}
            table.insert(parts, "[")
            for i = 1, max_key do
                if i > 1 then
                    table.insert(parts, ", ")
                end
                table.insert(parts, serialize_value(value[i], indent + 1))
            end
            table.insert(parts, "]")
            return table.concat(parts)
        else
            -- Object (single-line for ExtState compatibility)
            local parts = {}
            table.insert(parts, "{")
            local first = true
            for k, v in pairs(value) do
                if not first then
                    table.insert(parts, ",")
                end
                first = false
                local key_str = type(k) == "string" and ('"' .. escape_string(k) .. '"') or tostring(k)
                table.insert(parts, key_str .. ":" .. serialize_value(v, indent + 1))
            end
            table.insert(parts, "}")
            return table.concat(parts)
        end
    else
        return '"' .. escape_string(tostring(value)) .. '"'
    end
end

--- Encode a Lua table to JSON string
-- @param data table Lua table to encode
-- @return string JSON string
function M.encode(data)
    return serialize_value(data, 0)
end

--- Simple JSON decoder (basic recursive descent parser)
-- @param json_str string JSON string to decode
-- @return table|nil Decoded Lua table or nil on error
function M.decode(json_str)
    if not json_str or json_str == "" then return nil end

    local pos = 1
    local len = #json_str
    
    local function skip_whitespace()
        while pos <= len do
            local c = json_str:sub(pos, pos)
            if c == " " or c == "\t" or c == "\n" or c == "\r" then
                pos = pos + 1
            else
                break
            end
        end
    end
    
    local function parse_string()
        if json_str:sub(pos, pos) ~= '"' then return nil end
        pos = pos + 1
        local result = {}
        while pos <= len do
            local c = json_str:sub(pos, pos)
            if c == '"' then
                pos = pos + 1
                return table.concat(result)
            elseif c == "\\" then
                pos = pos + 1
                local next_c = json_str:sub(pos, pos)
                if next_c == "n" then
                    table.insert(result, "\n")
                elseif next_c == "r" then
                    table.insert(result, "\r")
                elseif next_c == "t" then
                    table.insert(result, "\t")
                elseif next_c == "\\" then
                    table.insert(result, "\\")
                elseif next_c == '"' then
                    table.insert(result, '"')
                else
                    table.insert(result, next_c)
                end
                pos = pos + 1
            else
                table.insert(result, c)
                pos = pos + 1
            end
        end
        return nil
    end
    
    local function parse_number()
        local start = pos
        local is_float = false
        while pos <= len do
            local c = json_str:sub(pos, pos)
            if c:match("[0-9]") or c == "-" or c == "+" then
                pos = pos + 1
            elseif c == "." or c == "e" or c == "E" then
                is_float = true
                pos = pos + 1
            else
                break
            end
        end
        local num_str = json_str:sub(start, pos - 1)
        local num = tonumber(num_str)
        return num
    end
    
    -- Forward declarations
    local parse_object, parse_array, parse_value
    
    local function parse_object()
        if json_str:sub(pos, pos) ~= "{" then return nil end
        pos = pos + 1
        skip_whitespace()
        local obj = {}
        
        if json_str:sub(pos, pos) == "}" then
            pos = pos + 1
            return obj
        end
        
        while pos <= len do
            skip_whitespace()
            local key = parse_string()
            if not key then return nil end
            skip_whitespace()
            if json_str:sub(pos, pos) ~= ":" then return nil end
            pos = pos + 1
            skip_whitespace()
            local value = parse_value()
            if value == nil and json_str:sub(pos - 5, pos - 1) ~= "null" then return nil end
            obj[key] = value
            skip_whitespace()
            local c = json_str:sub(pos, pos)
            if c == "}" then
                pos = pos + 1
                return obj
            elseif c == "," then
                pos = pos + 1
            else
                return nil
            end
        end
        return nil
    end
    
    parse_array = function()
        if json_str:sub(pos, pos) ~= "[" then return nil end
        pos = pos + 1
        skip_whitespace()
        local arr = {}
        
        if json_str:sub(pos, pos) == "]" then
            pos = pos + 1
            return arr
        end
        
        while pos <= len do
            skip_whitespace()
            local value = parse_value()
            table.insert(arr, value)
            skip_whitespace()
            local c = json_str:sub(pos, pos)
            if c == "]" then
                pos = pos + 1
                return arr
            elseif c == "," then
                pos = pos + 1
            else
                return nil
            end
        end
        return nil
    end
    
    parse_value = function()
        skip_whitespace()
        if pos > len then return nil end
        
        local c = json_str:sub(pos, pos)
        if c == '"' then
            return parse_string()
        elseif c == "{" then
            return parse_object()
        elseif c == "[" then
            return parse_array()
        elseif c == "t" and json_str:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif c == "f" and json_str:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        elseif c == "n" and json_str:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        elseif c:match("[0-9%-]") then
            return parse_number()
        else
            return nil
        end
    end
    
    skip_whitespace()
    local result = parse_value()
    skip_whitespace()
    if pos <= len then return nil end  -- Should have consumed entire string
    return result
end

return M
