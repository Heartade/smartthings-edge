-- Parent driver entry point. Child power actions use per-child learned codes.
local ZigbeeDriver = require "st.zigbee"
local capabilities = require "st.capabilities"
local children = require "children"
local learned_actions = require "ir.learned_actions"
local ac_state = require "ac.state"
local ac_learned_state = require "ac.learned_state"
local ac_registry = require "ac.registry"
local lg_encoders = require "ac.protocol_lg"
local irremote_encoders = require "ac.protocol_irremote"
local expanded_encoders = require "ac.protocol_expanded"
local catalog_encoders = require "ac.protocol_catalog"
local socket = require "socket"
local controller = require "ir.controller"
local edge_zigbee = require "ir.edge_zigbee"
local zosung = require "ir.zosung"
local gui_module = require "gui"
local gui

for id, encoder in pairs(lg_encoders.encoders) do
  ac_registry.register(id, encoder)
end
for id, encoder in pairs(irremote_encoders.encoders) do
  ac_registry.register(id, encoder)
end
for id, encoder in pairs(expanded_encoders.encoders) do
  ac_registry.register(id, encoder)
end
for id, encoder in pairs(catalog_encoders.encoders) do
  ac_registry.register(id, encoder)
end

local TRANSFER_TIMEOUT_SECONDS = 15
local states = {}
local AC_PROTOCOLS = {
  learned_state = "learned-state",
  lg_28 = "lg-28",
  lg2_28 = "lg2-28",
  lg2_akb74955603 = "lg2-akb74955603",
  toshiba_72_a = "toshiba-72-a", toshiba_72_b = "toshiba-72-b",
  mitsubishi_144 = "mitsubishi-144",
  gree_yaw1f = "gree-yaw1f", gree_ybofb = "gree-ybofb", gree_yx1fsf = "gree-yx1fsf",
  kelvinator_128 = "kelvinator-128", electra_104 = "electra-104",
  samsung_ac = "samsung-ac", carrier_64 = "carrier-64", haier_72 = "haier-72",
  haier_yrw02 = "haier-yrw02", haier_160 = "haier-160",
  haier_176_a = "haier-176-a", haier_176_b = "haier-176-b",
  tcl112_tac09chsd = "tcl112-tac09chsd", tcl112_gz055be1 = "tcl112-gz055be1",
  midea_48 = "midea-48", daikin_152 = "daikin-152"
}
for _, choice in ipairs(catalog_encoders.choices) do AC_PROTOCOLS[choice.key] = choice.id end

local function now()
  return socket.gettime()
end

local function cancel_timeout(driver, state)
  state.timer_generation = (state.timer_generation or 0) + 1
  if state.timer then
    driver:cancel_timer(state.timer)
    state.timer = nil
  end
end

local function report_transfer(state, status, detail)
  if not gui then return end
  local target = state.learn_target or (state.send_target and state.send_target.gui_test and state.send_target)
  if target then gui.status(target.device, status, detail) end
end

local function timeout_detail(state)
  local active = state.controller.active
  if not active or active.kind ~= "learn" then return "IR transfer timed out" end
  local target = state.learn_target
  local action = target and (target.action or "ac_state") or "unknown signal"
  local capture = active.session
  if capture.seq == nil then
    return "IR transfer timed out: no capture received for " .. action
  end
  return string.format("IR transfer timed out: %s capture stalled at %d/%d bytes",
    action, capture.position or 0, capture.length or 0)
end

local function schedule_timeout(driver, device, state)
  cancel_timeout(driver, state)
  local active = state.controller.active
  if not active then return true end

  local generation = state.timer_generation
  local delay = math.max(0.1, active.deadline - now())
  local ok, timer = pcall(driver.call_with_delay, driver, delay, function()
    if state.timer_generation ~= generation then return end
    state.timer = nil
    local detail = timeout_detail(state)
    local ok, expired = pcall(state.controller.expire, state.controller)
    if not ok then
      report_transfer(state, "error", "IR timeout cleanup failed")
      state.controller:abort()
      state.learn_target = nil
      state.send_target = nil
      device.log.warn("IR transfer timeout cleanup failed: " .. tostring(expired))
    elseif expired then
      report_transfer(state, "timeout", detail)
      state.learn_target = nil
      state.send_target = nil
      device.log.warn(detail)
    elseif state.controller.active then
      schedule_timeout(driver, device, state)
    end
  end, "zosung-transfer-timeout-" .. device.id)
  if not ok or not timer then
    report_transfer(state, "error", "Could not schedule IR transfer timeout")
    state.controller:abort()
    state.learn_target = nil
    state.send_target = nil
    device.log.warn("Could not schedule IR transfer timeout: " .. tostring(timer))
    return nil
  end
  state.timer = timer
  return true
end

local function state_for(driver, device)
  local state = states[device.id]
  if state then return state end

  state = { timer_generation = 0 }
  state.controller = controller.new(function(cluster, command, payload)
    edge_zigbee.send(device, cluster, command, payload)
  end, now, TRANSFER_TIMEOUT_SECONDS)
  states[device.id] = state
  return state
end

local function begin_transfer(driver, device, method, argument)
  local state = state_for(driver, device)
  local expired_ok, expired = pcall(state.controller.expire, state.controller)
  if not expired_ok or expired then
    report_transfer(state, expired_ok and "timeout" or "error", "Previous IR operation expired")
    state.controller:abort()
    state.learn_target, state.send_target = nil, nil
    cancel_timeout(driver, state)
  end
  local ok, result, err = pcall(state.controller[method], state.controller, argument)
  if not ok then
    report_transfer(state, "error", tostring(result))
    state.controller:abort()
    state.learn_target = nil
    state.send_target = nil
    cancel_timeout(driver, state)
    device.log.warn("Could not start IR transfer: " .. tostring(result))
    return nil, tostring(result)
  end
  if state.controller.active then
    if not schedule_timeout(driver, device, state) then
      return nil, "could not schedule IR transfer timeout"
    end
  end
  return result, err
end

local function is_ac_device(device)
  if not device.supports_capability then return false end
  for _, name in ipairs({ "airConditionerMode", "thermostatMode" }) do
    if capabilities[name] then
      local ok, supported = pcall(device.supports_capability, device, capabilities[name])
      if ok and supported == true then return true end
    end
  end
  return false
end

local function ac_state_for(device)
  local stored = device:get_field("ac_desired_state")
  if type(stored) == "table" then
    local validated = ac_state.apply(ac_state.initial(), stored, { min_temperature = 10, max_temperature = 32 })
    if validated then return validated end
  end
  return ac_state.initial()
end

local function ac_unit_for(device)
  return device.preferences and device.preferences.acTemperatureUnit == "F" and "F" or "C"
end

local function ac_temperature_from_display(value, unit)
  if type(value) ~= "number" then return nil, "setpoint must be numeric" end
  local celsius = unit == "F" and ((value - 32) * 5 / 9) or value
  return math.floor(celsius + 0.5)
end

local function ac_temperature_for_display(celsius, unit)
  return unit == "F" and (celsius * 9 / 5 + 32) or celsius
end

local function emit_event(device, event)
  if not event then return end
  local ok, err = pcall(device.emit_event, device, event)
  if not ok then device.log.warn("Could not publish AC desired state: " .. tostring(err)) end
end

local function publish_ac_state(device, current)
  local unit = ac_unit_for(device)
  local mode = current.mode == "fan" and "fanOnly" or current.mode
  local selection = gui.protocol_selection(device)
  local features = ac_registry.describe(AC_PROTOCOLS[selection], device.preferences and device.preferences.acModel) or {
    min_temperature = 16, max_temperature = 30,
    swing_modes = { "off", "vertical", "horizontal", "all" }
  }
  if device:get_field("gui_ac_draft") then
    features = { min_temperature = 16, max_temperature = 30,
      swing_modes = { "off", "vertical", "horizontal", "all" } }
  end

  if capabilities.airConditionerMode then
    local modes = {}
    for _, native_mode in ipairs(features.modes or { "auto", "cool", "heat", "dry", "fan" }) do
      modes[#modes + 1] = native_mode == "fan" and "fanOnly" or native_mode
    end
    emit_event(device, capabilities.airConditionerMode.supportedAcModes(modes))
    emit_event(device, capabilities.airConditionerMode.availableAcModes(modes))
  end
  if capabilities.switch then
    emit_event(device, current.power and capabilities.switch.switch.on()
      or capabilities.switch.switch.off())
  end
  if capabilities.airConditionerMode then
    emit_event(device, capabilities.airConditionerMode.airConditionerMode(mode))
  end
  if capabilities.temperatureSetpoint then
    emit_event(device, capabilities.temperatureSetpoint.temperatureSetpoint({
      value = ac_temperature_for_display(current.temperature, unit), unit = unit
    }))
    if capabilities.temperatureSetpoint.temperatureSetpointRange then
      emit_event(device, capabilities.temperatureSetpoint.temperatureSetpointRange({
        value = { minimum = ac_temperature_for_display(features.min_temperature, unit),
          maximum = ac_temperature_for_display(features.max_temperature, unit),
          step = unit == "F" and 1.8 or 1 }, unit = unit
      }))
    end
  end
  if capabilities.fanMode then
    emit_event(device, capabilities.fanMode.fanMode(current.fan))
  end
  if capabilities.fanOscillationMode then
    local vertical, horizontal = current.swing_vertical ~= "off", current.swing_horizontal ~= "off"
    local swing = vertical and (horizontal and "all" or "vertical") or (horizontal and "horizontal" or "off")
    emit_event(device, capabilities.fanOscillationMode.fanOscillationMode(swing))
    emit_event(device, capabilities.fanOscillationMode.supportedFanOscillationModes(features.swing_modes))
    emit_event(device, capabilities.fanOscillationMode.availableFanOscillationModes(features.swing_modes))
  end
  if gui then gui.refresh(device) end
end

gui = gui_module.new(capabilities, {
  is_ac = is_ac_device, desired_state = ac_state_for,
  publish_ac = publish_ac_state, now = now,
  busy = function(device)
    local parent = gui.parent(device)
    local state = parent and states[parent.id]
    if not state or not state.controller.active then return nil end
    local target = state.learn_target or state.send_target
    return { kind = state.controller.active.kind, owner = target and target.device.id }
  end
})

local function ac_payload_for(device, current, patch)
  local selection = gui.protocol_selection(device)
  local protocol = AC_PROTOCOLS[selection]
  if not protocol then return nil, "unsupported AC protocol selection: " .. tostring(selection) end
  if protocol == "learned-state" then
    local store = ac_learned_state.new(device:get_field("learned_ac_states"))
    local next_state, code = store:resolve(current, patch)
    if not next_state then return nil, code end
    local ok, payload = pcall(learned_actions.to_payload, code)
    if not ok then return nil, "invalid learned AC code: " .. tostring(payload) end
    return next_state, payload
  end

  local model = device.preferences and device.preferences.acModel or 0
  local previous = device:get_field("ac_last_sent_state")
  if device:get_field("ac_last_sent_protocol") ~= protocol or
      device:get_field("ac_last_sent_model") ~= model then previous = nil end
  local next_state, frames = ac_registry.encode(protocol, current, patch, model, previous or ac_state.initial())
  if not next_state then return nil, frames end
  if #frames == 0 then return next_state, nil end
  local payload, err = ac_registry.to_payload(frames)
  if not payload then return nil, err end
  return next_state, payload
end

local function send_ac_patch(driver, device, patch)
  if not is_ac_device(device) then return nil, "not an AC child" end
  if gui.edit_ac(device, patch) then return true end
  local current = ac_state_for(device)
  local next_state, payload = ac_payload_for(device, current, patch)
  if not next_state then
    device.log.warn("AC command not sent: " .. tostring(payload))
    return nil, payload
  end

  local ok, parent = pcall(device.get_parent_device, device)
  if not ok or not parent then
    device.log.warn("Could not resolve the IR blaster parent")
    return nil, "could not resolve the IR blaster parent"
  end

  local seq, err = true, nil
  if payload then
    seq, err = driver:send_ir_code(parent, payload, device, next_state.power, {
      ac_state = next_state, ac_protocol = AC_PROTOCOLS[gui.protocol_selection(device)],
      ac_model = device.preferences and device.preferences.acModel or 0
    })
  end
  if not seq then
    device.log.warn("Could not send AC state: " .. tostring(err))
    return nil, err
  end

  -- This is last-commanded state, not feedback from the air conditioner.
  device:set_field("ac_desired_state", next_state, { persist = true })
  publish_ac_state(device, next_state)
  return seq
end

local function thermostat_mode_to_ac(mode)
  if mode == "dryair" or mode == "dry" then return "dry" end
  if mode == "fanonly" or mode == "fanOnly" or mode == "fan" or mode == "wind" then return "fan" end
  if mode == "auto" or mode == "cool" or mode == "heat" then return mode end
  return nil
end

local function zosung_message(driver, device, zb_rx)
  local state = state_for(driver, device)
  local command, raw = edge_zigbee.received(zb_rx)
  if not command then
    device.log.warn("Ignoring malformed Zosung message: " .. tostring(raw))
    return
  end

  local expired_ok, expired = pcall(state.controller.expire, state.controller)
  if not expired_ok or expired then
    report_transfer(state, expired_ok and "timeout" or "error", "IR operation expired")
    state.controller:abort()
    state.learn_target, state.send_target = nil, nil
    cancel_timeout(driver, state)
    return
  end
  if state.controller.active and state.controller.active.kind == "learn" then
    device.log.info(string.format("IR learning received Zosung command 0x%02X", command))
  end
  local ok, result, detail = pcall(state.controller.receive, state.controller, command, raw)
  if not ok then
    report_transfer(state, "error", "Invalid IR transfer response: " .. tostring(result))
    state.controller:abort()
    state.learn_target = nil
    state.send_target = nil
    cancel_timeout(driver, state)
    device.log.warn("IR transfer aborted after invalid Zosung message: " .. tostring(result))
    return
  end

  if not result then
    device.log.warn("Ignoring Zosung command: " .. tostring(detail))
  elseif result == "sent" then
    device.log.info("IR transmission completed")
    if state.send_target then
      local target = state.send_target
      state.send_target = nil
      if target.ac_state then
        target.device:set_field("ac_last_sent_state", target.ac_state, { persist = true })
        target.device:set_field("ac_last_sent_protocol", target.ac_protocol, { persist = true })
        target.device:set_field("ac_last_sent_model", target.ac_model, { persist = true })
      end
      if target.gui_test then gui.status(target.device, "sent", "Transfer completed") end
      if target.value ~= nil then
        target.device:set_field("ir_power_state", target.value, { persist = true })
        local event = target.value and capabilities.switch.switch.on()
          or capabilities.switch.switch.off()
        local emitted, err = pcall(target.device.emit_event, target.device, event)
        if not emitted then target.device.log.warn("IR sent but switch state event failed: " .. tostring(err)) end
      end
    end
  elseif result == "learned" then
    local target = state.learn_target
    state.learn_target = nil
    if target then
      local saved, key, err = pcall(function()
        if target.state then
          local store = ac_learned_state.new(target.device:get_field("learned_ac_states"))
          local saved_key, save_err = store:put(target.state, detail)
          if saved_key then
            target.device:set_field("learned_ac_states", store.codes, { persist = true })
          end
          return saved_key, save_err
        end

        local store = learned_actions.new(target.device:get_field("learned_ir_actions"))
        local saved_key, save_err = store:put(target.action, detail)
        if saved_key then
          target.device:set_field("learned_ir_actions", store.codes, { persist = true })
        end
        return saved_key, save_err
      end)
      if not saved then
        gui.status(target.device, "error", "Could not save learned signal: " .. tostring(key))
        target.device.log.warn("Could not save learned IR code: " .. tostring(key))
      elseif key then
        gui.status(target.device, "learned", "Signal saved")
        if target.state then
          target.device.log.info("Learned AC state saved: " .. key)
        else
          target.device.log.info("Learned IR action saved: " .. target.action)
        end
      else
        gui.status(target.device, "error", "Could not save learned signal: " .. tostring(err))
        target.device.log.warn("Could not save learned IR code: " .. tostring(err))
      end
    else
      device.log.warn("IR capture completed without a child action target")
    end
  end

  if state.controller.active then
    schedule_timeout(driver, device, state)
  else
    state.learn_target = nil
    state.send_target = nil
    cancel_timeout(driver, state)
  end
end

local function child_info_changed(driver, device)
  local power_request = device.preferences and device.preferences.learnActionRequest
  local ac_request = device.preferences and device.preferences.learnAcStateRequest
  local power_changed = type(power_request) == "string" and power_request ~= "" and
    device:get_field("last_learn_action_request") ~= power_request
  local ac_changed = type(ac_request) == "string" and ac_request ~= "" and
    device:get_field("last_learn_ac_state_request") ~= ac_request
  if not power_changed and not ac_changed then return end

  local ok, parent = pcall(device.get_parent_device, device)
  if not ok or not parent then
    device.log.warn("Could not resolve the IR blaster parent")
    return
  end

  if power_changed then
    local parsed, err = learned_actions.parse_request(power_request)
    if not parsed then
      device.log.warn(tostring(err))
    else
      local result
      if parsed.action == "cancel" then
        result, err = driver:cancel_ir_learning(parent, device)
      else
        result, err = driver:start_ir_learning(parent, device, parsed.action)
      end
      if result then
        device:set_field("last_learn_action_request", power_request, { persist = true })
      else
        device.log.warn("Could not process IR learning request: " .. tostring(err))
      end
    end
  end

  if ac_changed then
    local parsed, err = ac_learned_state.parse_request(ac_request)
    if not parsed then
      device.log.warn(tostring(err))
    else
      local result
      if parsed.action == "cancel" then
        result, err = driver:cancel_ir_learning(parent, device)
      else
        result, err = driver:start_ir_state_learning(parent, device, parsed.target)
      end
      if result then
        device:set_field("last_learn_ac_state_request", ac_request, { persist = true })
      else
        device.log.warn("Could not process AC learning request: " .. tostring(err))
      end
    end
  end
end

local function initialize_device(driver, device)
  gui.child_added(driver, device)
  if not gui.learning_enabled(device) then
    device:set_field("gui_ac_draft", nil)
    local parent = gui.parent(device)
    local active = gui.busy(device)
    if parent and active and active.kind == "learn" and active.owner == device.id then
      driver:cancel_ir_learning(parent, device)
    end
  end
  -- Existing children must select the new profile revision to receive the new
  -- capabilities. Keep their model, preferences and learned-state fields.
  local profile = gui.profile(device)
  if profile and gui.needs_profile(device, profile) then
    if device:get_field("gui_profile_migration_requested") ~= profile then
      device.log.info("Updating remote profile to " .. profile)
      local ok, err = pcall(device.try_update_metadata, device, { profile = profile })
      if ok then
        device:set_field("gui_profile_revision", 8, { persist = true })
        device:set_field("gui_profile_migration_requested", profile)
      else
        device.log.warn("Could not update setup controls: " .. tostring(err))
        return
      end
    end
  else
    device:set_field("gui_profile_migration_requested", nil)
  end

  -- Profile metadata updates are asynchronous. Publish state for every
  -- capability supported by the currently installed profile immediately rather
  -- than waiting for a follow-up infoChanged event that may never arrive.
  gui.initialize(driver, device)
  if gui.kind(device) == "remote-tv" and capabilities.keypadInput then
    local keys = { "UP", "DOWN", "LEFT", "RIGHT", "SELECT", "BACK", "EXIT", "MENU", "HOME", "SETTINGS" }
    for i = 0, 9 do keys[#keys + 1] = "NUMBER" .. i end
    emit_event(device, capabilities.keypadInput.supportedKeyCodes({ value = keys }))
  end
  if not is_ac_device(device) then
    if device:supports_capability(capabilities.switch) then
      local value = device:get_field("ir_power_state")
      if value == nil and device.get_latest_state then
        local latest = device:get_latest_state("main", "switch", "switch")
        if latest == "on" or latest == "off" then value = latest == "on" end
      end
      -- This is the last sent/assumed state; IR offers no appliance feedback.
      emit_event(device, value == true and capabilities.switch.switch.on() or capabilities.switch.switch.off())
    end
    return
  end
  local current = ac_state_for(device)
  if device:get_field("ac_desired_state") == nil then
    device:set_field("ac_desired_state", current, { persist = true })
  end

  if capabilities.fanMode and capabilities.fanMode.supportedFanModes then
    emit_event(device, capabilities.fanMode.supportedFanModes(
      { "auto", "low", "medium", "high" }))
  end
  publish_ac_state(device, gui.display_state(device))
end

local function info_changed(driver, device, _, args)
  if device.get_parent_device then
    local ok, parent = pcall(device.get_parent_device, device)
    if ok and parent then
      child_info_changed(driver, device)
      initialize_device(driver, device)
      return
    end
  end

  local request = device.preferences and device.preferences.addRemoteRequest
  local old = args and args.old_st_store and args.old_st_store.preferences
  if not request or request == (old and old.addRemoteRequest) then return end
  local _, status = children.create(driver, device, request)
  device.log.info("Add remote: " .. tostring(status))
end

local function removed(driver, device)
  gui.removed(driver, device)
  local state = states[device.id]
  if not state and device.get_parent_device then
    local ok, parent = pcall(device.get_parent_device, device)
    if ok and parent then state = states[parent.id] end
    if not state then return end

    if state.learn_target and state.learn_target.device.id == device.id then
      state.controller:abort()
      state.learn_target = nil
      cancel_timeout(driver, state)
    end
    if state.send_target and state.send_target.device.id == device.id then
      state.send_target = nil
    end
    return
  end
  if not state then return end
  report_transfer(state, "error", "IR blaster removed")
  state.controller:abort()
  state.learn_target = nil
  state.send_target = nil
  cancel_timeout(driver, state)
  states[device.id] = nil
end

local function driver_lifecycle(driver, event)
  if event ~= "shutdown" then return end
  gui.shutdown(driver)
  for _, state in pairs(states) do
    report_transfer(state, "error", "Driver stopped")
    state.controller:abort()
    state.learn_target = nil
    state.send_target = nil
    cancel_timeout(driver, state)
  end
end

local cluster_handlers = {}
for command = 0x00, 0x05 do
  cluster_handlers[command] = zosung_message
end

local function send_switch_action(driver, device, action, value)
  if is_ac_device(device) then
    send_ac_patch(driver, device, { power = value })
    return
  end

  local store = learned_actions.new(device:get_field("learned_ir_actions"))
  local code = store:get(action)
  if not code and (action == "power_on" or action == "power_off") then
    code = store:get("power_toggle")
    if code and device:get_field("ir_power_state") == value then
      -- Repeating On/Off must not invert a toggle-only appliance again.
      device.log.info("Power toggle skipped: last sent state already matches " .. action)
      return
    end
  end
  if not code then
    device.log.warn("No learned IR action named " .. action)
    gui.failure(device, "Learn the " .. action .. " button first")
    return
  end

  local ok, parent = pcall(device.get_parent_device, device)
  if not ok or not parent then
    device.log.warn("Could not resolve the IR blaster parent")
    return
  end

  local seq, err = driver:send_ir_code(parent, learned_actions.to_payload(code), device, value)
  if not seq then device.log.warn("Could not send IR action: " .. tostring(err)) end
end

local capability_handlers = {
  [capabilities.switch.ID] = {
    [capabilities.switch.commands.on.NAME] = function(driver, device)
      send_switch_action(driver, device, "power_on", true)
    end,
    [capabilities.switch.commands.off.NAME] = function(driver, device)
      send_switch_action(driver, device, "power_off", false)
    end
  },
  [capabilities.refresh.ID] = {
    [capabilities.refresh.commands.refresh.NAME] = function(_, device)
      gui.refresh(device)
      if is_ac_device(device) then
        publish_ac_state(device, gui.display_state(device))
      else
        device.log.info("IR status is maintained by captured-command transfers")
      end
    end
  }
}

local function add_capability_handler(capability_name, command_name, handler)
  local available, capability, command = pcall(function()
    local cap = capabilities[capability_name]
    return cap, cap and cap.commands and cap.commands[command_name]
  end)
  if not available then return end
  if not capability or not command then return end
  capability_handlers[capability.ID] = capability_handlers[capability.ID] or {}
  capability_handlers[capability.ID][command.NAME] = handler
end
gui.register(function(name, command, handler)
  for role, id in pairs(gui_module.IDS) do
    if name == id and gui.caps[role] then add_capability_handler(name, command, handler); return end
  end
end)

local function send_ac_thermostat_mode(driver, device, mode)
  if not is_ac_device(device) then return end
  if mode == "off" then
    send_ac_patch(driver, device, { power = false })
    return
  end
  local ac_mode = thermostat_mode_to_ac(mode)
  if not ac_mode then
    device.log.warn("Unsupported AC thermostat mode: " .. tostring(mode))
    return
  end
  send_ac_patch(driver, device, { power = true, mode = ac_mode })
end

add_capability_handler("thermostatMode", "setThermostatMode", function(driver, device, command)
  send_ac_thermostat_mode(driver, device, command.args and command.args.mode)
end)
add_capability_handler("airConditionerMode", "setAirConditionerMode", function(driver, device, command)
  send_ac_thermostat_mode(driver, device, command.args and command.args.mode)
end)
for _, mode in ipairs({ "auto", "cool", "heat", "off" }) do
  local selected_mode = mode
  add_capability_handler("thermostatMode", selected_mode, function(driver, device)
    send_ac_thermostat_mode(driver, device, selected_mode)
  end)
end

local function send_ac_setpoint(driver, device, command)
  if not is_ac_device(device) then return end
  local requested = command.args and command.args.setpoint
  local temperature, err = ac_temperature_from_display(requested, ac_unit_for(device))
  if not temperature then
    device.log.warn("Invalid AC temperature: " .. tostring(err))
    return
  end
  send_ac_patch(driver, device, { temperature = temperature })
end
add_capability_handler("thermostatCoolingSetpoint", "setCoolingSetpoint", send_ac_setpoint)
add_capability_handler("thermostatHeatingSetpoint", "setHeatingSetpoint", send_ac_setpoint)
add_capability_handler("temperatureSetpoint", "setTemperatureSetpoint", send_ac_setpoint)

add_capability_handler("fanOscillationMode", "setFanOscillationMode", function(driver, device, command)
  if not is_ac_device(device) then return end
  local swing = command.args and command.args.fanOscillationMode
  local axes = {
    off = { "off", "off" }, vertical = { "on", "off" },
    horizontal = { "off", "on" }, all = { "on", "on" }
  }
  if not axes[swing] then
    device.log.warn("Unsupported AC swing mode: " .. tostring(swing))
    return
  end
  send_ac_patch(driver, device, {
    swing_vertical = axes[swing][1], swing_horizontal = axes[swing][2]
  })
end)

add_capability_handler("fanMode", "setFanMode", function(driver, device, command)
  local fan = command.args and (command.args.fanMode or command.args.mode)
  send_ac_patch(driver, device, { fan = fan })
end)
for command_name, fan in pairs({
  fanAuto = "auto", fanLow = "low", fanMedium = "medium", fanHigh = "high"
}) do
  local selected_command, selected_fan = command_name, fan
  add_capability_handler("fanMode", selected_command, function(driver, device)
    send_ac_patch(driver, device, { fan = selected_fan })
  end)
end

add_capability_handler("momentary", "push", function(driver, device)
  if gui.kind(device) == "remote-button" then
    send_switch_action(driver, device, "press", nil)
  end
end)

-- Standard keypadInput invokes the app's native TV navigation/numeric remote.
local tv_keys = { UP = "up", DOWN = "down", LEFT = "left", RIGHT = "right",
  SELECT = "ok", BACK = "back", EXIT = "exit", MENU = "menu", HOME = "home", SETTINGS = "settings" }
for i = 0, 9 do tv_keys["NUMBER" .. i] = "digit_" .. i end
add_capability_handler("keypadInput", "sendKey", function(driver, device, command)
  if gui.kind(device) ~= "remote-tv" then return end
  local action = tv_keys[command.args and command.args.keyCode]
  if action then send_switch_action(driver, device, action, nil) end
end)

-- TV buttons share the same capture store and parent transfer ownership as power.
for _, button in ipairs(require("ir.tv_buttons").buttons) do
  local action = button.action
  if button.capability ~= "keypadInput" then
    add_capability_handler(gui_module.IDS[button.capability], button.command, function(driver, device)
      if gui.kind(device) ~= "remote-tv" then return end
      send_switch_action(driver, device, action, nil)
    end)
  end
end

local supported_capabilities = {
  capabilities.refresh, capabilities.switch, capabilities.momentary, capabilities.keypadInput, capabilities.thermostatMode,
  capabilities.thermostatCoolingSetpoint, capabilities.thermostatHeatingSetpoint,
  capabilities.fanMode, capabilities.airConditionerMode,
  capabilities.temperatureSetpoint, capabilities.fanOscillationMode
}
for _, cap in pairs(gui.caps) do supported_capabilities[#supported_capabilities + 1] = cap end
local driver = ZigbeeDriver("generic-ir-remote", {
  health_check = false,
  supported_capabilities = supported_capabilities,
  zigbee_handlers = {
    cluster = { [zosung.TRANSMIT_CLUSTER] = cluster_handlers }
  },
  lifecycle_handlers = {
    init = initialize_device, added = initialize_device,
    infoChanged = info_changed, removed = removed
  },
  driver_lifecycle = driver_lifecycle,
  capability_handlers = capability_handlers
})

-- Parent-level entry points for child command handlers. Callers must resolve
-- and pass the physical Zigbee parent so every child shares one transfer lock.
function driver:send_ir_code(parent, code, target_device, switch_value, options)
  local state = state_for(self, parent)
  local result, err = begin_transfer(self, parent, "send_code", code)
  if result and target_device then
    state.send_target = { device = target_device, value = switch_value,
      gui_test = options and options.gui_test,
      ac_state = options and options.ac_state, ac_protocol = options and options.ac_protocol,
      ac_model = options and options.ac_model }
  end
  return result, err
end

function driver:start_ir_learning(parent, target_device, action)
  if not target_device or is_ac_device(target_device) or not gui.allowed_action(target_device, action) then
    return nil, "a child device and supported remote button are required"
  end
  local state = state_for(self, parent)
  local result, err = begin_transfer(self, parent, "start_learning")
  if result then
    state.learn_target = { device = target_device, action = action }
    target_device.log.info("IR learning started for " .. action .. " on blaster " .. parent.id)
    gui.status(target_device, "learning", "Press the original remote button")
  end
  return result, err
end

function driver:start_ir_state_learning(parent, target_device, target_state)
  if not target_device or not gui.learning_enabled(target_device) or type(target_state) ~= "table" then
    return nil, "a child device and complete AC state are required"
  end
  local validated, err = ac_state.apply(ac_state.initial(), target_state)
  if not validated then return nil, err end
  local state = state_for(self, parent)
  local result
  result, err = begin_transfer(self, parent, "start_learning")
  if result then
    state.learn_target = { device = target_device, state = validated }
    gui.status(target_device, "learning", "Press the original remote button for the prepared AC state")
  end
  return result, err
end

function driver:cancel_ir_learning(parent, target_device)
  local state = states[parent.id]
  if not state then return nil, "no learning in progress" end
  if target_device and (not state.learn_target or state.learn_target.device.id ~= target_device.id) then
    return nil, "this child does not own the active learning session"
  end
  local ok, result, err = pcall(state.controller.cancel_learning, state.controller)
  if not ok then
    parent.log.warn("Could not cancel IR learning: " .. tostring(result))
    if not state.controller.active then
      state.learn_target = nil
      cancel_timeout(self, state)
    end
    return nil, tostring(result)
  end
  if result then
    gui.status(target_device or state.learn_target.device, "cancelled", "Learning cancelled")
    state.learn_target = nil
    cancel_timeout(self, state)
  end
  return result, err
end

driver:run()
