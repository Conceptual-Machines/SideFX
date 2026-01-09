--- Unit tests for SideFX track detection utilities.
-- Tests the lib/utils/track_detection.lua module functions.
-- @module unit.test_track_detection
-- @author Nomad Monad
-- @license MIT

local assert = require("assertions")
local track_detection = require("lib.utils.track_detection")

local M = {}

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

function M.run()
    assert.section("is_sidefx_jsfx")
    
    -- SideFX JSFX plugins
    assert.truthy(track_detection.is_sidefx_jsfx("JS: SideFX/SideFX_Mixer"), "detects SideFX_Mixer")
    assert.truthy(track_detection.is_sidefx_jsfx("SideFX_Mixer"), "detects SideFX_Mixer without path")
    assert.truthy(track_detection.is_sidefx_jsfx("JS: SideFX/SideFX_Utility"), "detects SideFX_Utility")
    assert.truthy(track_detection.is_sidefx_jsfx("SideFX_Utility"), "detects SideFX_Utility without path")
    assert.truthy(track_detection.is_sidefx_jsfx("JS: SideFX/SideFX_Modulator"), "detects SideFX_Modulator")
    assert.truthy(track_detection.is_sidefx_jsfx("SideFX_Modulator"), "detects SideFX_Modulator without path")
    
    -- Case insensitive
    assert.truthy(track_detection.is_sidefx_jsfx("sidefx_mixer"), "case insensitive detection")
    assert.truthy(track_detection.is_sidefx_jsfx("SIDEFX_UTILITY"), "case insensitive detection")
    
    -- Non-SideFX plugins
    assert.falsy(track_detection.is_sidefx_jsfx("ReaComp"), "doesn't detect regular plugins")
    assert.falsy(track_detection.is_sidefx_jsfx("VST: ReaComp"), "doesn't detect VST plugins")
    assert.falsy(track_detection.is_sidefx_jsfx("JS: utility"), "doesn't detect other JSFX")
    assert.falsy(track_detection.is_sidefx_jsfx(nil), "handles nil")
    assert.falsy(track_detection.is_sidefx_jsfx(""), "handles empty string")
    
    assert.section("is_sidefx_container_name")
    
    -- R-containers (racks)
    assert.truthy(track_detection.is_sidefx_container_name("R1"), "detects R1")
    assert.truthy(track_detection.is_sidefx_container_name("R12"), "detects R12")
    assert.truthy(track_detection.is_sidefx_container_name("R1: Some Name"), "detects R1: prefix")
    
    -- C-containers (chains)
    assert.truthy(track_detection.is_sidefx_container_name("C1"), "detects C1")
    assert.truthy(track_detection.is_sidefx_container_name("C5"), "detects C5")
    assert.truthy(track_detection.is_sidefx_container_name("R1_C1"), "detects R1_C1")
    assert.truthy(track_detection.is_sidefx_container_name("R1_C1: Chain Name"), "detects R1_C1: prefix")
    
    -- D-containers (devices)
    assert.truthy(track_detection.is_sidefx_container_name("D1"), "detects D1")
    assert.truthy(track_detection.is_sidefx_container_name("D42"), "detects D42")
    assert.truthy(track_detection.is_sidefx_container_name("D1: ReaComp"), "detects D1: prefix")
    assert.truthy(track_detection.is_sidefx_container_name("R1_C1_D1: Plugin"), "detects nested D container")
    
    -- Non-SideFX containers
    assert.falsy(track_detection.is_sidefx_container_name("Container"), "doesn't detect generic container")
    assert.falsy(track_detection.is_sidefx_container_name("ReaComp"), "doesn't detect regular plugins")
    assert.falsy(track_detection.is_sidefx_container_name("R"), "doesn't detect single R")
    assert.falsy(track_detection.is_sidefx_container_name("C"), "doesn't detect single C")
    assert.falsy(track_detection.is_sidefx_container_name("D"), "doesn't detect single D")
    assert.falsy(track_detection.is_sidefx_container_name("R_1"), "doesn't detect R_1 (underscore)")
    assert.falsy(track_detection.is_sidefx_container_name(nil), "handles nil")
    assert.falsy(track_detection.is_sidefx_container_name(""), "handles empty string")
    
    assert.section("is_sidefx_fx_name")
    
    -- SideFX JSFX
    assert.truthy(track_detection.is_sidefx_fx_name("SideFX_Mixer"), "detects JSFX")
    assert.truthy(track_detection.is_sidefx_fx_name("SideFX_Utility"), "detects JSFX")
    assert.truthy(track_detection.is_sidefx_fx_name("SideFX_Modulator"), "detects JSFX")
    
    -- SideFX containers
    assert.truthy(track_detection.is_sidefx_fx_name("R1"), "detects rack container")
    assert.truthy(track_detection.is_sidefx_fx_name("C1"), "detects chain container")
    assert.truthy(track_detection.is_sidefx_fx_name("D1: ReaComp"), "detects device container")
    
    -- Non-SideFX
    assert.falsy(track_detection.is_sidefx_fx_name("ReaComp"), "doesn't detect regular plugins")
    assert.falsy(track_detection.is_sidefx_fx_name("Container"), "doesn't detect generic container")
    assert.falsy(track_detection.is_sidefx_fx_name(nil), "handles nil")
    
    assert.section("scan_fx_names_for_sidefx")
    
    -- Empty list
    assert.falsy(track_detection.scan_fx_names_for_sidefx({}), "empty list returns false")
    assert.falsy(track_detection.scan_fx_names_for_sidefx(nil), "nil returns false")
    
    -- Regular FX only
    assert.falsy(track_detection.scan_fx_names_for_sidefx({
        "ReaComp",
        "ReaEQ",
        "VST: SomePlugin"
    }), "regular FX only returns false")
    
    -- SideFX JSFX in list
    assert.truthy(track_detection.scan_fx_names_for_sidefx({
        "ReaComp",
        "SideFX_Mixer",
        "ReaEQ"
    }), "detects SideFX JSFX in list")
    
    -- SideFX container in list
    assert.truthy(track_detection.scan_fx_names_for_sidefx({
        "ReaComp",
        "D1: ReaEQ",
        "ReaVerb"
    }), "detects SideFX container in list")
    
    -- Multiple SideFX markers
    assert.truthy(track_detection.scan_fx_names_for_sidefx({
        "R1",
        "SideFX_Mixer",
        "D1: Plugin"
    }), "detects multiple SideFX markers")
    
    -- SideFX at start
    assert.truthy(track_detection.scan_fx_names_for_sidefx({
        "R1",
        "ReaComp"
    }), "detects SideFX at start")
    
    -- SideFX at end
    assert.truthy(track_detection.scan_fx_names_for_sidefx({
        "ReaComp",
        "D1: Plugin"
    }), "detects SideFX at end")
    
    -- Mixed case
    assert.truthy(track_detection.scan_fx_names_for_sidefx({
        "ReaComp",
        "sidefx_mixer",
        "ReaEQ"
    }), "case insensitive detection")
end

return M
