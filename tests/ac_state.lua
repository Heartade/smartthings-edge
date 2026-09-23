package.path = "src/?.lua;src/?/init.lua;" .. package.path
local state = require "ac.state"
local initial = state.initial()
local next_state = assert(state.apply(initial, {
  power = true, mode = "cool", temperature = 23, fan = "medium",
  swing_vertical = "auto", swing_horizontal = "off"
}))
assert(next_state.temperature == 23 and next_state.fan == "medium")
assert(initial.temperature == 24 and initial.power == false)
assert(state.apply(next_state, {temperature = 31}) == nil)
assert(state.apply(next_state, {unknown = true}) == nil)
assert(state.apply(next_state, {mode = "cool"}, {supports = function(s) return s.fan == "auto" end}) == nil)
assert(state.apply(next_state, {fan = "auto"}, {supports = function(s) return s.fan == "auto" end}))
print("AC state tests passed")
