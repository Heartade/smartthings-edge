-- Runtime for generated common-state IRremoteESP8266 ports. No C++ on the hub.
-- SPDX-License-Identifier: LGPL-2.1-only
local index = require "ac.catalog_index"
local M = { encoders = {}, choices = {} }
local modes = { "auto", "cool", "heat", "dry", "fan" }
local mode_index = { auto = 1, cool = 2, heat = 3, dry = 4, fan = 5 }
local fan_index = { auto = 1, low = 2, medium = 3, high = 4 }
local native_fan = { [0] = "auto", "low", "low", "medium", "high", "high", "high" }
local function enabled(value) return value ~= nil and value ~= "off" end
local cache, order = {}, {}
local function load(record)
  local key = record.module
  if cache[key] then return cache[key] end
  local module = "ac.catalog_data." .. key
  local data = require(module)
  -- Keep a small cache when a user browses through models/protocols.
  package.loaded[module] = nil
  cache[key] = data; order[#order + 1] = key
  if #order > 4 then cache[table.remove(order, 1)] = nil end
  return data
end
local function record_for(entry, model)
  model = tonumber(model) or 0
  if model == 0 then return entry.models[1] end
  for _, record in ipairs(entry.models) do if record.value == model then return record end end
  return nil, "Model number is not defined for " .. entry.protocol
end
local function describe(record)
  local available_modes = {}
  for _, value in ipairs(record.modes) do available_modes[#available_modes + 1] = modes[value + 1] end
  local swing = { "off" }
  if record.vertical then swing[#swing + 1] = "vertical" end
  if record.horizontal then swing[#swing + 1] = "horizontal" end
  if record.vertical and record.horizontal then swing[#swing + 1] = "all" end
  return { min_temperature = record.min, max_temperature = record.max,
    modes = available_modes, swing_modes = swing }
end
local function inputs_for(data, state, previous)
  previous = previous or { power = false, swing_vertical = "off", swing_horizontal = "off" }
  return { mode_index[state.mode], state.temperature - 9, fan_index[state.fan],
    state.power and 2 or 1, enabled(state.swing_vertical) and 2 or 1,
    enabled(state.swing_horizontal) and 2 or 1,
    data.dims[7] == 1 and 1 or (previous.power and 2 or 1),
    data.dims[8] == 1 and 1 or (enabled(previous.swing_vertical) and 2 or 1),
    data.dims[9] == 1 and 1 or (enabled(previous.swing_horizontal) and 2 or 1) }
end
local function evaluate(data, inputs)
  local memo = {}
  local function value(root)
    if root < 0 then return -root - 1 end
    local cached = memo[root]
    if cached ~= nil then return cached end
    local node = data.nodes[root]
    local result = value(node[inputs[node[1]] + 1])
    memo[root] = result
    return result
  end
  return function(column) return value(data.roots[column]) end
end
for _, entry in ipairs(index) do
  local item = entry
  local id = "irac-" .. item.protocol:lower():gsub("_", "-")
  M.choices[#M.choices + 1] = { key = "irac_" .. item.protocol:lower(), id = id,
    label = "IRac " .. item.protocol }
  local default = describe(item.models[1])
  M.encoders[id] = {
    min_temperature = default.min_temperature, max_temperature = default.max_temperature,
    swing_modes = default.swing_modes, modes = default.modes, allow_noop = true,
    describe = function(model)
      local record = record_for(item, model)
      return record and describe(record) or default
    end,
    supports = function(state, model)
      local record, err = record_for(item, model)
      if not record then return false, err end
      if enabled(state.swing_vertical) and not record.vertical then return false, "Vertical swing is not supported by this model" end
      if enabled(state.swing_horizontal) and not record.horizontal then return false, "Horizontal swing is not supported by this model" end
      local found = false
      for _, code in ipairs(record.modes) do if modes[code + 1] == state.mode then found = true end end
      if not found then return false, "Mode is not supported by this model" end
      return true
    end,
    encode = function(state, model, previous)
      local record = assert(record_for(item, model))
      local data = load(record)
      local value = evaluate(data, inputs_for(data, state, previous))
      local count, carrier = value(2), value(1)
      local normalized = {}
      -- toCommon supplies canonical field values after native setters clamp or
      -- constrain them. Preserve requested power/swing for toggle-only formats.
      if value(6) ~= 0 and state.power then
        if modes[value(3)] then normalized.mode = modes[value(3)] end
        if value(4) >= 10 and value(4) <= 32 then normalized.temperature = value(4) end
        normalized.fan = native_fan[value(5)] or state.fan
      end
      if count == 0 then return {}, normalized end
      local timings = {}
      for i = 1, count do timings[i] = value(i + 6) end
      return { { carrier_hz = carrier, timings = timings } }, normalized
    end
  }
end
M.index = index
return M
