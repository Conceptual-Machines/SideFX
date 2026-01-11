--- Unit tests for modulation math (unipolar/bipolar offset/scale calculations)
-- Uses LuaUnit framework
--
-- The plink formula is: target = offset + lfo * scale
-- where lfo is 0-1 from the JSFX modulator.
--
-- Unipolar mode:
--   offset = initial_value
--   scale = depth
--   Range: initial to initial+depth
--
-- Bipolar mode:
--   offset = initial - depth
--   scale = 2 * depth
--   Range: initial-depth to initial+depth
--   Center: offset + scale/2 = initial
--
-- @module test_modulation_math_luaunit
-- @author Nomad Monad
-- @license MIT

local luaunit = require("luaunit")

TestModulationMath = {}

-- Simulate plink formula
local function calc_target(offset, scale, lfo)
    return offset + lfo * scale
end

-- Calculate modulation range
local function calc_range(offset, scale)
    local min_val = math.min(offset, offset + scale)
    local max_val = math.max(offset, offset + scale)
    return min_val, max_val
end

-- Convert unipolar to bipolar settings
local function unipolar_to_bipolar(offset, scale)
    local initial = offset
    local depth = scale
    local new_offset = initial - depth
    local new_scale = depth * 2
    return new_offset, new_scale
end

-- Convert bipolar to unipolar settings
local function bipolar_to_unipolar(offset, scale)
    local depth = scale / 2
    local initial = offset + depth
    return initial, depth
end

function TestModulationMath:test_unipolar_positive()
    local initial = 0.5
    local depth = 0.3
    local offset = initial
    local scale = depth

    -- At LFO min (0)
    local target_min = calc_target(offset, scale, 0)
    luaunit.assertAlmostEquals(target_min, 0.5, 0.001)

    -- At LFO max (1)
    local target_max = calc_target(offset, scale, 1)
    luaunit.assertAlmostEquals(target_max, 0.8, 0.001)

    -- Range
    local min_r, max_r = calc_range(offset, scale)
    luaunit.assertAlmostEquals(min_r, 0.5, 0.001)
    luaunit.assertAlmostEquals(max_r, 0.8, 0.001)
end

function TestModulationMath:test_unipolar_negative()
    local initial = 0.5
    local depth = -0.3
    local offset = initial
    local scale = depth

    -- At LFO min (0)
    local target_min = calc_target(offset, scale, 0)
    luaunit.assertAlmostEquals(target_min, 0.5, 0.001)

    -- At LFO max (1)
    local target_max = calc_target(offset, scale, 1)
    luaunit.assertAlmostEquals(target_max, 0.2, 0.001)

    -- Range (note: min and max swap with negative depth)
    local min_r, max_r = calc_range(offset, scale)
    luaunit.assertAlmostEquals(min_r, 0.2, 0.001)
    luaunit.assertAlmostEquals(max_r, 0.5, 0.001)
end

function TestModulationMath:test_bipolar_positive()
    local initial = 0.5
    local depth = 0.3
    local offset = initial - depth  -- 0.2
    local scale = depth * 2  -- 0.6

    -- At LFO min (0)
    local target_min = calc_target(offset, scale, 0)
    luaunit.assertAlmostEquals(target_min, 0.2, 0.001)

    -- At LFO center (0.5)
    local target_center = calc_target(offset, scale, 0.5)
    luaunit.assertAlmostEquals(target_center, 0.5, 0.001)

    -- At LFO max (1)
    local target_max = calc_target(offset, scale, 1)
    luaunit.assertAlmostEquals(target_max, 0.8, 0.001)

    -- Range
    local min_r, max_r = calc_range(offset, scale)
    luaunit.assertAlmostEquals(min_r, 0.2, 0.001)
    luaunit.assertAlmostEquals(max_r, 0.8, 0.001)
end

function TestModulationMath:test_bipolar_negative()
    local initial = 0.5
    local depth = -0.3
    local offset = initial - depth  -- 0.8
    local scale = depth * 2  -- -0.6

    -- At LFO min (0)
    local target_min = calc_target(offset, scale, 0)
    luaunit.assertAlmostEquals(target_min, 0.8, 0.001)

    -- At LFO center (0.5)
    local target_center = calc_target(offset, scale, 0.5)
    luaunit.assertAlmostEquals(target_center, 0.5, 0.001)

    -- At LFO max (1)
    local target_max = calc_target(offset, scale, 1)
    luaunit.assertAlmostEquals(target_max, 0.2, 0.001)

    -- Range (swapped due to negative)
    local min_r, max_r = calc_range(offset, scale)
    luaunit.assertAlmostEquals(min_r, 0.2, 0.001)
    luaunit.assertAlmostEquals(max_r, 0.8, 0.001)
end

function TestModulationMath:test_mode_conversion_unipolar_to_bipolar()
    local initial = 0.5
    local depth = 0.3

    -- Start unipolar
    local uni_offset = initial
    local uni_scale = depth

    -- Convert to bipolar
    local bi_offset, bi_scale = unipolar_to_bipolar(uni_offset, uni_scale)
    luaunit.assertAlmostEquals(bi_offset, 0.2, 0.001)
    luaunit.assertAlmostEquals(bi_scale, 0.6, 0.001)

    -- Verify center is preserved
    local bi_center = bi_offset + bi_scale / 2
    luaunit.assertAlmostEquals(bi_center, initial, 0.001)

    -- Convert back to unipolar
    local back_offset, back_scale = bipolar_to_unipolar(bi_offset, bi_scale)
    luaunit.assertAlmostEquals(back_offset, initial, 0.001)
    luaunit.assertAlmostEquals(back_scale, depth, 0.001)
end

function TestModulationMath:test_mode_conversion_negative_depth()
    local initial = 0.5
    local depth = -0.3

    -- Start unipolar
    local uni_offset = initial
    local uni_scale = depth

    -- Convert to bipolar
    local bi_offset, bi_scale = unipolar_to_bipolar(uni_offset, uni_scale)
    luaunit.assertAlmostEquals(bi_offset, 0.8, 0.001)
    luaunit.assertAlmostEquals(bi_scale, -0.6, 0.001)

    -- Verify center is preserved
    local bi_center = bi_offset + bi_scale / 2
    luaunit.assertAlmostEquals(bi_center, initial, 0.001)

    -- Convert back to unipolar
    local back_offset, back_scale = bipolar_to_unipolar(bi_offset, bi_scale)
    luaunit.assertAlmostEquals(back_offset, initial, 0.001)
    luaunit.assertAlmostEquals(back_scale, depth, 0.001)
end

return TestModulationMath
