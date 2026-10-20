-- Parent driver entry point. Child power actions use per-child learned codes.
local ZigbeeDriver = require "st.zigbee"
local capabilities = require "st.capabilities"
local children = require "children"
local learned_actions = require "ir.learned_actions"
local socket = require "socket"
local controller = require "ir.controller"
local edge_zigbee = require "ir.edge_zigbee"
local zosung = require "ir.zosung"

local TRANSFER_TIMEOUT_SECONDS = 15
local states = {}

local function now()
  return socket.gettime() / 1000
end

local function cancel_timeout(driver, state)
  state.timer_generation = (state.timer_generation or 0) + 1
  if state.timer then
    driver:cancel_timer(state.timer)
    state.timer = nil
  end
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
    local ok, expired = pcall(state.controller.expire, state.controller)
    if not ok then
      state.controller:abort()
      state.learn_target = nil
      state.send_target = nil
      device.log.warn("IR transfer timeout cleanup failed: " .. tostring(expired))
    elseif expired then
      state.learn_target = nil
      state.send_target = nil
      device.log.warn("IR transfer timed out")
    elseif state.controller.active then
      schedule_timeout(driver, device, state)
    end
  end, "zosung-transfer-timeout-" .. device.id)
  if not ok or not timer then
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
  local ok, result, err = pcall(state.controller[method], state.controller, argument)
  if not ok then
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

local function zosung_message(driver, device, zb_rx)
  local state = state_for(driver, device)
  local command, raw = edge_zigbee.received(zb_rx)
  if not command then
    device.log.warn("Ignoring malformed Zosung message: " .. tostring(raw))
    return
  end

  local ok, result, detail = pcall(state.controller.receive, state.controller, command, raw)
  if not ok then
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
      local event = target.value and capabilities.switch.switch.on()
        or capabilities.switch.switch.off()
      local emitted, err = pcall(target.device.emit_event, target.device, event)
      if not emitted then
        target.device.log.warn("IR sent but switch state event failed: " .. tostring(err))
      end
    end
  elseif result == "learned" then
    local target = state.learn_target
    state.learn_target = nil
    if target then
      local saved, key, err = pcall(function()
        local store = learned_actions.new(target.device:get_field("learned_ir_actions"))
        local saved_key, save_err = store:put(target.action, detail)
        if saved_key then
          target.device:set_field("learned_ir_actions", store.codes, { persist = true })
        end
        return saved_key, save_err
      end)
      if not saved then
        target.device.log.warn("Could not save learned IR action: " .. tostring(key))
      elseif key then
        target.device.log.info("Learned IR action saved: " .. target.action)
      else
        target.device.log.warn("Could not save learned IR action: " .. tostring(err))
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
  local request = device.preferences and device.preferences.learnActionRequest
  if type(request) ~= "string" or request == "" then return end
  if device:get_field("last_learn_action_request") == request then return end

  local parsed, err = learned_actions.parse_request(request)
  if not parsed then
    device.log.warn(tostring(err))
    return
  end

  local ok, parent = pcall(device.get_parent_device, device)
  if not ok or not parent then
    device.log.warn("Could not resolve the IR blaster parent")
    return
  end

  local result, err
  if parsed.action == "cancel" then
    result, err = driver:cancel_ir_learning(parent, device)
  else
    result, err = driver:start_ir_learning(parent, device, parsed.action)
  end
  if result then
    device:set_field("last_learn_action_request", request, { persist = true })
  else
    device.log.warn("Could not process IR learning request: " .. tostring(err))
  end
end

local function info_changed(driver, device, _, args)
  if device.get_parent_device then
    local ok, parent = pcall(device.get_parent_device, device)
    if ok and parent then
      child_info_changed(driver, device)
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
  state.controller:abort()
  state.learn_target = nil
  state.send_target = nil
  cancel_timeout(driver, state)
  states[device.id] = nil
end

local function driver_lifecycle(driver, event)
  if event ~= "shutdown" then return end
  for _, state in pairs(states) do
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
  if capabilities.thermostatMode and device.supports_capability and
    device:supports_capability(capabilities.thermostatMode) then
    device.log.warn("Switch commands are not implemented for AC profiles")
    return
  end

  local store = learned_actions.new(device:get_field("learned_ir_actions"))
  local code = store:get(action)
  if not code then
    device.log.warn("No learned IR action named " .. action)
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

local driver = ZigbeeDriver("generic-ir-remote", {
  supported_capabilities = { capabilities.refresh, capabilities.switch },
  zigbee_handlers = {
    cluster = { [zosung.TRANSMIT_CLUSTER] = cluster_handlers }
  },
  lifecycle_handlers = { infoChanged = info_changed, removed = removed },
  driver_lifecycle = driver_lifecycle,
  capability_handlers = {
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
        device.log.info("IR status is maintained by captured-command transfers")
      end
    }
  }
})

-- Parent-level entry points for child command handlers. Callers must resolve
-- and pass the physical Zigbee parent so every child shares one transfer lock.
function driver:send_ir_code(parent, code, target_device, switch_value)
  local state = state_for(self, parent)
  local result, err = begin_transfer(self, parent, "send_code", code)
  if result and target_device then
    state.send_target = { device = target_device, value = switch_value }
  end
  return result, err
end

function driver:start_ir_learning(parent, target_device, action)
  if not target_device or (action ~= "power_on" and action ~= "power_off") then
    return nil, "a child device and power action are required"
  end
  local state = state_for(self, parent)
  local result, err = begin_transfer(self, parent, "start_learning")
  if result then state.learn_target = { device = target_device, action = action } end
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
    state.learn_target = nil
    cancel_timeout(self, state)
  end
  return result, err
end

driver:run()
