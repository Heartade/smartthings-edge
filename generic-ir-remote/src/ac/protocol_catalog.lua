-- Runtime for generated common-state IRremoteESP8266 ports. No C++ on the hub.
-- SPDX-License-Identifier: LGPL-2.1-only
local index = require "ac.catalog_index"
local M = { encoders = {}, choices = {} }
local modes = { "auto", "cool", "heat", "dry", "fan" }
local mode_index = { auto = 1, cool = 2, heat = 3, dry = 4, fan = 5 }
local fans = { "auto", "low", "medium", "high" }
local fan_index = { auto = 1, low = 2, medium = 3, high = 4 }
local native_fan = { [0] = "auto", "low", "low", "medium", "high", "high", "high" }
local function enabled(value) return value ~= nil and value ~= "off" end
local cache, order = {}, {}
local function expand_graph(compact)
  if not compact.values then return compact end
  local stream = compact.values:gmatch("[^,]+")
  local function next_value()
    local token = stream()
    assert(token, "truncated AC protocol graph")
    local value = tonumber(token, 36)
    assert(value ~= nil, "invalid AC protocol graph integer")
    return value
  end

  local roots = {}
  for i = 1, compact.root_count do roots[i] = next_value() end
  local nodes = {}
  for i = 1, compact.node_count do
    local depth = next_value()
    local node = { depth }
    for child = 1, compact.dims[depth] do node[child + 1] = next_value() end
    nodes[i] = node
  end
  assert(stream() == nil, "trailing AC protocol graph data")
  return { dims = compact.dims, roots = roots, nodes = nodes }
end
local function load(record)
  local key = record.module
  if cache[key] then return cache[key] end
  local module = "ac.catalog_data." .. key
  local data = expand_graph(require(module))
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
local function listed_fans(record)
  if type(record.fans) ~= "table" then return nil end
  local available = {}
  for _, value in ipairs(record.fans) do
    if fans[value + 1] then available[#available + 1] = fans[value + 1] end
  end
  return #available > 0 and available or nil
end
local function supported_fans(record)
  local listed = listed_fans(record)
  if listed then return listed end
  if record._fan_modes then return record._fan_modes end

  -- Older generated catalogs did not persist fan capability metadata. Recover
  -- it from the captured upstream toCommon() result in graph columns 5/6.
  -- A choice is exposed when at least one supported operating mode preserves
  -- that requested common fan speed. Modes such as Dry may intentionally force
  -- Auto, so requiring every state to preserve the speed would under-report it.
  local data = load(record)
  local found, saw_normalized = {}, false
  for _, mode in ipairs(record.modes) do
    for temp = record.min, record.max do
      for fan = 1, #fans do
        local inputs = { mode + 1, temp - 9, fan, 2, 1, 1, 1, 1, 1 }
        local value = evaluate(data, inputs)
        if value(6) ~= 0 then
          saw_normalized = true
          if native_fan[value(5)] == fans[fan] then found[fan] = true end
        end
      end
    end
  end

  local available = {}
  if saw_normalized then
    for fan, name in ipairs(fans) do if found[fan] then available[#available + 1] = name end end
  end
  -- Some upstream senders cannot be inspected through toCommon(). Preserve the
  -- old permissive behavior for those rather than hiding potentially valid UI.
  if #available == 0 then
    for _, name in ipairs(fans) do available[#available + 1] = name end
  end
  record._fan_modes = available
  return available
end
local function describe(record, infer_fans)
  local available_modes = {}
  for _, value in ipairs(record.modes) do available_modes[#available_modes + 1] = modes[value + 1] end
  local swing = { "off" }
  if record.vertical then swing[#swing + 1] = "vertical" end
  if record.horizontal then swing[#swing + 1] = "horizontal" end
  if record.vertical and record.horizontal then swing[#swing + 1] = "all" end
  return { min_temperature = record.min, max_temperature = record.max,
    modes = available_modes, fan_modes = infer_fans and supported_fans(record) or listed_fans(record) or fans,
    swing_modes = swing }
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
for _, entry in ipairs(index) do
  local item = entry
  local id = "irac-" .. item.protocol:lower():gsub("_", "-")
  M.choices[#M.choices + 1] = { key = "irac_" .. item.protocol:lower(), id = id,
    label = item.protocol }
  -- Avoid expanding graph data for every protocol at driver startup. Fan modes
  -- are inferred lazily for the selected model when no generated metadata exists.
  local default = describe(item.models[1], false)
  M.encoders[id] = {
    min_temperature = default.min_temperature, max_temperature = default.max_temperature,
    swing_modes = default.swing_modes, modes = default.modes, fan_modes = default.fan_modes,
    allow_noop = true,
    describe = function(model)
      local record = record_for(item, model)
      return record and describe(record, true) or default
    end,
    supports = function(state, model)
      local record, err = record_for(item, model)
      if not record then return false, err end
      if enabled(state.swing_vertical) and not record.vertical then return false, "Vertical swing is not supported by this model" end
      if enabled(state.swing_horizontal) and not record.horizontal then return false, "Horizontal swing is not supported by this model" end
      local found = false
      for _, code in ipairs(record.modes) do if modes[code + 1] == state.mode then found = true end end
      if not found then return false, "Mode is not supported by this model" end
      found = false
      for _, fan in ipairs(supported_fans(record)) do if fan == state.fan then found = true end end
      if not found then return false, "Fan mode is not supported by this model" end
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
