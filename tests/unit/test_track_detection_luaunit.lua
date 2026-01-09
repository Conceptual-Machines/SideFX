--- Unit tests for SideFX track detection utilities (LuaUnit version).
-- Tests the lib/utils/track_detection.lua module functions.
-- @module unit.test_track_detection_luaunit
-- @author Nomad Monad
-- @license MIT

local luaunit = require("luaunit")
local track_detection = require("lib.utils.track_detection")

TestTrackDetection = {}

--------------------------------------------------------------------------------
-- Tests: is_sidefx_jsfx
--------------------------------------------------------------------------------

function TestTrackDetection:test_is_sidefx_jsfx_detects_mixer()
    luaunit.assertTrue(track_detection.is_sidefx_jsfx("JS: SideFX/SideFX_Mixer"), "detects SideFX_Mixer")
    luaunit.assertTrue(track_detection.is_sidefx_jsfx("SideFX_Mixer"), "detects SideFX_Mixer without path")
end

function TestTrackDetection:test_is_sidefx_jsfx_detects_utility()
    luaunit.assertTrue(track_detection.is_sidefx_jsfx("JS: SideFX/SideFX_Utility"), "detects SideFX_Utility")
    luaunit.assertTrue(track_detection.is_sidefx_jsfx("SideFX_Utility"), "detects SideFX_Utility without path")
end

function TestTrackDetection:test_is_sidefx_jsfx_detects_modulator()
    luaunit.assertTrue(track_detection.is_sidefx_jsfx("JS: SideFX/SideFX_Modulator"), "detects SideFX_Modulator")
    luaunit.assertTrue(track_detection.is_sidefx_jsfx("SideFX_Modulator"), "detects SideFX_Modulator without path")
end

function TestTrackDetection:test_is_sidefx_jsfx_case_insensitive()
    luaunit.assertTrue(track_detection.is_sidefx_jsfx("sidefx_mixer"), "case insensitive detection")
    luaunit.assertTrue(track_detection.is_sidefx_jsfx("SIDEFX_UTILITY"), "case insensitive detection")
end

function TestTrackDetection:test_is_sidefx_jsfx_rejects_non_sidefx()
    luaunit.assertFalse(track_detection.is_sidefx_jsfx("ReaComp"), "doesn't detect regular plugins")
    luaunit.assertFalse(track_detection.is_sidefx_jsfx("VST: ReaComp"), "doesn't detect VST plugins")
    luaunit.assertFalse(track_detection.is_sidefx_jsfx("JS: utility"), "doesn't detect other JSFX")
    luaunit.assertFalse(track_detection.is_sidefx_jsfx(nil), "handles nil")
    luaunit.assertFalse(track_detection.is_sidefx_jsfx(""), "handles empty string")
end

--------------------------------------------------------------------------------
-- Tests: is_sidefx_container_name
--------------------------------------------------------------------------------

function TestTrackDetection:test_is_sidefx_container_name_detects_racks()
    luaunit.assertTrue(track_detection.is_sidefx_container_name("R1"), "detects R1")
    luaunit.assertTrue(track_detection.is_sidefx_container_name("R12"), "detects R12")
    luaunit.assertTrue(track_detection.is_sidefx_container_name("R1: Some Name"), "detects R1: prefix")
end

function TestTrackDetection:test_is_sidefx_container_name_detects_chains()
    luaunit.assertTrue(track_detection.is_sidefx_container_name("C1"), "detects C1")
    luaunit.assertTrue(track_detection.is_sidefx_container_name("C5"), "detects C5")
    luaunit.assertTrue(track_detection.is_sidefx_container_name("R1_C1"), "detects R1_C1")
    luaunit.assertTrue(track_detection.is_sidefx_container_name("R1_C1: Chain Name"), "detects R1_C1: prefix")
end

function TestTrackDetection:test_is_sidefx_container_name_detects_devices()
    luaunit.assertTrue(track_detection.is_sidefx_container_name("D1"), "detects D1")
    luaunit.assertTrue(track_detection.is_sidefx_container_name("D42"), "detects D42")
    luaunit.assertTrue(track_detection.is_sidefx_container_name("D1: ReaComp"), "detects D1: prefix")
    luaunit.assertTrue(track_detection.is_sidefx_container_name("R1_C1_D1: Plugin"), "detects nested D container")
end

function TestTrackDetection:test_is_sidefx_container_name_rejects_non_sidefx()
    luaunit.assertFalse(track_detection.is_sidefx_container_name("Container"), "doesn't detect generic container")
    luaunit.assertFalse(track_detection.is_sidefx_container_name("ReaComp"), "doesn't detect regular plugins")
    luaunit.assertFalse(track_detection.is_sidefx_container_name("R"), "doesn't detect single R")
    luaunit.assertFalse(track_detection.is_sidefx_container_name("C"), "doesn't detect single C")
    luaunit.assertFalse(track_detection.is_sidefx_container_name("D"), "doesn't detect single D")
    luaunit.assertFalse(track_detection.is_sidefx_container_name("R_1"), "doesn't detect R_1 (underscore)")
    luaunit.assertFalse(track_detection.is_sidefx_container_name(nil), "handles nil")
    luaunit.assertFalse(track_detection.is_sidefx_container_name(""), "handles empty string")
end

--------------------------------------------------------------------------------
-- Tests: is_sidefx_fx_name
--------------------------------------------------------------------------------

function TestTrackDetection:test_is_sidefx_fx_name_detects_jsfx()
    luaunit.assertTrue(track_detection.is_sidefx_fx_name("SideFX_Mixer"), "detects JSFX")
    luaunit.assertTrue(track_detection.is_sidefx_fx_name("SideFX_Utility"), "detects JSFX")
    luaunit.assertTrue(track_detection.is_sidefx_fx_name("SideFX_Modulator"), "detects JSFX")
end

function TestTrackDetection:test_is_sidefx_fx_name_detects_containers()
    luaunit.assertTrue(track_detection.is_sidefx_fx_name("R1"), "detects rack container")
    luaunit.assertTrue(track_detection.is_sidefx_fx_name("C1"), "detects chain container")
    luaunit.assertTrue(track_detection.is_sidefx_fx_name("D1: ReaComp"), "detects device container")
end

function TestTrackDetection:test_is_sidefx_fx_name_rejects_non_sidefx()
    luaunit.assertFalse(track_detection.is_sidefx_fx_name("ReaComp"), "doesn't detect regular plugins")
    luaunit.assertFalse(track_detection.is_sidefx_fx_name("Container"), "doesn't detect generic container")
    luaunit.assertFalse(track_detection.is_sidefx_fx_name(nil), "handles nil")
end

--------------------------------------------------------------------------------
-- Tests: scan_fx_names_for_sidefx
--------------------------------------------------------------------------------

function TestTrackDetection:test_scan_fx_names_for_sidefx_empty()
    luaunit.assertFalse(track_detection.scan_fx_names_for_sidefx({}), "empty list returns false")
    luaunit.assertFalse(track_detection.scan_fx_names_for_sidefx(nil), "nil returns false")
end

function TestTrackDetection:test_scan_fx_names_for_sidefx_regular_only()
    luaunit.assertFalse(track_detection.scan_fx_names_for_sidefx({
        "ReaComp",
        "ReaEQ",
        "VST: SomePlugin"
    }), "regular FX only returns false")
end

function TestTrackDetection:test_scan_fx_names_for_sidefx_detects_jsfx()
    luaunit.assertTrue(track_detection.scan_fx_names_for_sidefx({
        "ReaComp",
        "SideFX_Mixer",
        "ReaEQ"
    }), "detects SideFX JSFX in list")
end

function TestTrackDetection:test_scan_fx_names_for_sidefx_detects_container()
    luaunit.assertTrue(track_detection.scan_fx_names_for_sidefx({
        "ReaComp",
        "D1: ReaEQ",
        "ReaVerb"
    }), "detects SideFX container in list")
end

function TestTrackDetection:test_scan_fx_names_for_sidefx_multiple_markers()
    luaunit.assertTrue(track_detection.scan_fx_names_for_sidefx({
        "R1",
        "SideFX_Mixer",
        "D1: Plugin"
    }), "detects multiple SideFX markers")
end

function TestTrackDetection:test_scan_fx_names_for_sidefx_at_start()
    luaunit.assertTrue(track_detection.scan_fx_names_for_sidefx({
        "R1",
        "ReaComp"
    }), "detects SideFX at start")
end

function TestTrackDetection:test_scan_fx_names_for_sidefx_at_end()
    luaunit.assertTrue(track_detection.scan_fx_names_for_sidefx({
        "ReaComp",
        "D1: Plugin"
    }), "detects SideFX at end")
end

function TestTrackDetection:test_scan_fx_names_for_sidefx_case_insensitive()
    luaunit.assertTrue(track_detection.scan_fx_names_for_sidefx({
        "ReaComp",
        "sidefx_mixer",
        "ReaEQ"
    }), "case insensitive detection")
end
