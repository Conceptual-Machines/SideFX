# SideFX Roadmap

Future improvements sorted by priority.

## v0.3.0 - Presets & Modulator Improvements

### Presets
- [ ] Save/load track FX chain presets (entire SideFX structure)
- [ ] Save/load device presets (individual device + modulators)
- [ ] Save/load rack presets (rack with all chains and devices)

### Global/Rack Modulators
- [ ] Test plink behavior with modulators outside containers
- [ ] Add global modulators (track-level, can target any device)
- [ ] Add rack modulators (can target any device in the rack)
- [ ] Evaluate if device modulators should be kept or deprecated

### UX Improvements
- [ ] Right-click parameter → link modulator directly (remove dropdown)
- [ ] Wrap selection in rack (select devices, click + Rack to wrap them)

## v0.4.0 - Gain Staging

- [ ] Pre/post gain controls per device
- [ ] Visual metering
- [ ] Gain compensation options

## v0.5.0 - Extended Modulators

### More Modulator Types
- [ ] Classic LFO shapes (sine, triangle, saw, square, S&H)
- [ ] ADSR envelope generator
- [ ] Step sequencer

### REAPER Integration
- [ ] Expose REAPER's internal parameter modulation LFOs
- [ ] Right-click parameter → show envelope in arrange view

## Future Ideas (Unscheduled)

- [ ] Rename parameters (custom display names)
- [ ] Macro controls (one knob controls multiple parameters)
- [ ] MIDI learn for device parameters
- [ ] Undo history panel
