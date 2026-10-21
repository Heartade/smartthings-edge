-- Native SmartThings setup controls. Appliance I/O stays in the parent driver.
local children = require "children"
local actions = require "ir.learned_actions"
local ac_store = require "ac.learned_state"
local ac_state = require "ac.state"
local tv_buttons = require "ir.tv_buttons"
local definitions = require "capability_definitions"
local json = require "st.json"
local M = {
  IDS = { creation = "againmusic09479.irRemoteCreation",
    learning = "againmusic09479.irSignalLearning", setup = "againmusic09479.acLearningSetup",
    tv = "againmusic09479.irTvRemote", tvKeypad = "againmusic09479.irTvKeypad",
    tvMedia = "againmusic09479.irTvMedia" }
}
local remote_types = { ["remote-tv"] = true, ["remote-fan"] = true,
  ["remote-generic"] = true, ["ac-learned-state"] = true, ["ac-protocol"] = true, ["ac-protocol-learning"] = true }

function M.new(capabilities, services)
  local g = { caps = {}, creation_timers = {} }
  for name, id in pairs(M.IDS) do
    local ok, cap = pcall(function()
      if definitions[name] then
        local definition = json.decode(definitions[name])
        definition.id, definition.version = id, 1
        local candidate = capabilities.build_cap_from_json_string(json.encode(definition), false)
        -- Command dispatch also resolves this table by ID. Use the same current
        -- schema there as for event construction, rather than its cached proxy.
        capabilities[id] = candidate
        return candidate
      end
      local candidate = capabilities[id]
      if candidate and candidate.commands then return candidate end
    end)
    if ok then g.caps[name] = cap
    elseif definitions[name] then error("Could not load bundled " .. name .. " capability: " .. tostring(cap)) end
  end
  local function supports(device, cap)
    if not cap or not device.supports_capability then return false end
    local ok, value = pcall(device.supports_capability, device, cap)
    return ok and value == true
  end
  local function emit(device, name, attribute, value)
    local cap = g.caps[name]
    if not supports(device, cap) then return end
    local ok, result, err = pcall(function()
      return device:emit_event(cap[attribute]({ value = value },
        attribute == "supportedActions" and { state_change = true } or nil))
    end)
    if not ok or result == false or err ~= nil then
      device.log.warn("Could not publish " .. attribute .. ": " .. tostring(ok and err or result))
    end
  end
  local function message(value)
    local text = tostring(value or "")
    local ok, boundary = pcall(utf8.offset, text, 161)
    return ok and (boundary and text:sub(1, boundary - 1) or text) or "IR operation failed"
  end
  function g.parent(device)
    if not device.get_parent_device then return nil end
    local ok, parent = pcall(device.get_parent_device, device)
    return ok and parent or nil
  end
  -- Zigbee children may not expose the model supplied at creation. Resolve the
  -- type from their installed profile/capabilities as well as persisted metadata.
  function g.kind(device)
    local parent = g.parent(device)
    local types = parent and parent:get_field("ir_child_types")
    local assigned = types and types[device.parent_assigned_child_key]
    if assigned then return assigned end
    local stored = device:get_field("ir_remote_kind")
    if stored then return stored end
    local kind = device.model
    if not remote_types[kind] and kind ~= "ac-protocol-generated" then
      kind = device.profile and device.profile.name
    end
    if remote_types[kind] or kind == "ac-protocol-generated" then return kind end
    if g.parent(device) then
      if services.is_ac(device) then
        return device.preferences and device.preferences.acProtocol ~= nil and "ac-protocol" or "ac-learned-state"
      end
      if supports(device, capabilities.keypadInput) or supports(device, g.caps.tv) or
          supports(device, g.caps.tvKeypad) or supports(device, g.caps.tvMedia) then return "remote-tv" end
    end
  end
  function g.protocol_selection(device)
    local selection = device.preferences and device.preferences.acProtocol
    if selection then return selection end
    local kind = g.kind(device)
    return (kind == "ac-protocol" or kind == "ac-protocol-generated") and "lg_28" or "learned_state"
  end
  function g.profile(device)
    local kind = g.kind(device)
    if kind == "ac-protocol" or kind == "ac-protocol-generated" or kind == "ac-protocol-learning" then
      return g.protocol_selection(device) == "learned_state" and "ac-protocol-learning" or "ac-protocol"
    end
    if remote_types[kind] then return kind end
    if not g.parent(device) and device.get_short_address then return "ir-blaster" end
  end
  function g.needs_profile(device, profile)
    if not device.try_update_metadata then return false end
    if device:get_field("gui_profile_revision") ~= 5 then return true end
    if profile == "ir-blaster" then
      return g.caps.creation and not supports(device, g.caps.creation)
    end
    if profile == "ac-protocol" then
      return supports(device, g.caps.learning) or supports(device, g.caps.setup)
    end
    if remote_types[profile] then
      if profile == "remote-tv" then
        if not supports(device, capabilities.keypadInput) then return true end
        for _, role in ipairs({ "tv", "tvKeypad", "tvMedia" }) do
          if supports(device, g.caps[role]) then return true end
        end
      end
      if g.caps.learning and not supports(device, g.caps.learning) then return true end
      if services.is_ac(device) then
        if capabilities.airConditionerMode and not supports(device, capabilities.airConditionerMode) then return true end
        if g.caps.setup and not supports(device, g.caps.setup) then return true end
      end
    end
    return false
  end
  function g.learning_enabled(device)
    return g.profile(device) ~= "ac-protocol"
  end
  function g.allowed_action(device, action)
    if services.is_ac(device) then return action == "ac_state" end
    if g.kind(device) == "remote-tv" then return tv_buttons.valid[action] == true end
    return action == "power_on" or action == "power_off"
  end
  function g.display_state(device)
    return device:get_field("gui_ac_draft") or services.desired_state(device)
  end
  local function selected(device)
    return device:get_field("gui_selected_action") or (services.is_ac(device) and "ac_state" or "power_on")
  end
  local function saved_code(device)
    if services.is_ac(device) then
      local store = ac_store.new(device:get_field("learned_ac_states"))
      return store:resolve(g.display_state(device), {})
    end
    return selected(device), actions.new(device:get_field("learned_ir_actions")):get(selected(device))
  end
  function g.refresh(device)
    if g.learning_enabled(device) and supports(device, g.caps.learning) then
      local valid, code = saved_code(device)
      emit(device, "learning", "supportedActions", services.is_ac(device) and { "ac_state" } or
        (g.kind(device) == "remote-tv" and tv_buttons.actions or { "power_on", "power_off" }))
      emit(device, "learning", "action", selected(device))
      emit(device, "learning", "signalStatus", valid and code and "saved" or "empty")
      emit(device, "learning", "learningStatus", device:get_field("gui_learning_status") or "idle")
      emit(device, "learning", "statusMessage", device:get_field("gui_learning_message") or "")
    end
    emit(device, "setup", "setupMode", device:get_field("gui_ac_draft") and "on" or "off")
    if supports(device, g.caps.creation) then
      emit(device, "creation", "remoteType", device:get_field("gui_remote_type") or "remote-tv")
      emit(device, "creation", "remoteName", device:get_field("gui_remote_name") or "")
      emit(device, "creation", "creationStatus", device:get_field("gui_creation_status") or "idle")
      emit(device, "creation", "statusMessage", device:get_field("gui_creation_message") or "")
    end
  end
  function g.status(device, status, detail)
    device:set_field("gui_learning_status", status)
    device:set_field("gui_learning_message", message(detail))
    g.refresh(device)
  end
  function g.failure(device, err)
    g.status(device, tostring(err):find("busy", 1, true) and "busy" or "error", err)
  end
  function g.busy(device)
    return services.busy(device)
  end
  function g.edit_ac(device, patch)
    if not device:get_field("gui_ac_draft") then return false end
    if g.busy(device) then g.status(device, "busy", "Finish or cancel the current IR operation first"); return true end
    local draft, err = ac_state.apply(g.display_state(device), patch)
    if not draft then g.failure(device, err); return true end
    device:set_field("gui_ac_draft", draft)
    services.publish_ac(device, draft)
    g.refresh(device)
    return true
  end
  local function creation_status(device, status, detail)
    device:set_field("gui_creation_status", status, { persist = true })
    device:set_field("gui_creation_message", message(detail), { persist = true })
    g.refresh(device)
  end
  local function cancel_creation_timer(driver, device)
    local timer = g.creation_timers[device.id]
    if timer then driver:cancel_timer(timer); g.creation_timers[device.id] = nil end
  end
  local function creation_confirmed(driver, parent)
    local pending = parent:get_field("gui_creation_pending")
    if not pending or not parent:get_child_by_parent_assigned_key(pending.key) then return false end
    cancel_creation_timer(driver, parent)
    parent:set_field("gui_creation_pending", nil, { persist = true })
    creation_status(parent, "created", "Remote created")
    return true
  end
  local function watch_creation(driver, parent)
    cancel_creation_timer(driver, parent)
    if creation_confirmed(driver, parent) then return end
    local pending = parent:get_field("gui_creation_pending")
    if not pending then return end
    local ok, timer = pcall(driver.call_with_delay, driver,
      math.max(0.1, 30 - (services.now() - pending.started)), function()
        g.creation_timers[parent.id] = nil
        if not creation_confirmed(driver, parent) then
          creation_status(parent, "error", "Creation not confirmed; press Create to retry the same request")
        end
      end, "ir-create-" .. parent.id)
    if ok and timer then g.creation_timers[parent.id] = timer
    else creation_status(parent, "error", "Could not schedule child-creation confirmation") end
  end
  function g.child_added(driver, device)
    local parent = g.parent(device)
    if parent and parent.get_child_by_parent_assigned_key then creation_confirmed(driver, parent) end
  end
  function g.initialize(driver, device)
    if not device:get_field("gui_initialized") then
      device:set_field("gui_initialized", true)
      device:set_field("gui_ac_draft", nil)
      device:set_field("gui_learning_status", "idle")
      device:set_field("gui_learning_message", "")
      if supports(device, g.caps.creation) and device:get_field("gui_creation_pending") then
        watch_creation(driver, device)
      end
    end
    g.refresh(device)
  end
  function g.removed(driver, device)
    cancel_creation_timer(driver, device)
  end
  function g.shutdown(driver)
    for id, timer in pairs(g.creation_timers) do
      driver:cancel_timer(timer)
      g.creation_timers[id] = nil
    end
  end
  function g.register(add)
    add(M.IDS.creation, "setRemoteType", function(_, device, command)
      local value = command.args and command.args.remoteType
      if not remote_types[value] then creation_status(device, "error", "Unsupported remote type"); return end
      device:set_field("gui_remote_type", value, { persist = true }); g.refresh(device)
    end)
    add(M.IDS.creation, "setRemoteName", function(_, device, command)
      local value = command.args and command.args.name
      local ok, length = pcall(utf8.len, value or "")
      if type(value) ~= "string" or not ok or not length or length < 1 or length > 60 or
          not value:match("%S") or value:find("|", 1, true) then
        creation_status(device, "error", "Use a nonblank name of at most 60 characters without |"); return
      end
      device:set_field("gui_remote_name", value, { persist = true }); g.refresh(device)
    end)
    add(M.IDS.creation, "createRemote", function(driver, parent)
      if g.parent(parent) then return end
      if creation_confirmed(driver, parent) then return end
      local pending = parent:get_field("gui_creation_pending")
      if pending and parent:get_field("gui_creation_status") == "creating" then return end
      if not pending then
        local count = (parent:get_field("gui_child_counter") or 0) + 1
        local previous = parent:get_field("last_child_request") or ""
        while parent:get_child_by_parent_assigned_key("remote-gui" .. count) or
            previous:match("^gui" .. count .. "|") do count = count + 1 end
        local request = "gui" .. count .. "|" .. (parent:get_field("gui_remote_type") or "remote-tv") ..
          "|" .. (parent:get_field("gui_remote_name") or "")
        local spec, err = children.parse(request)
        if not spec then creation_status(parent, "error", err); return end
        parent:set_field("gui_child_counter", count, { persist = true })
        pending = { key = spec.key, request = request, started = services.now() }
        parent:set_field("gui_creation_pending", pending, { persist = true })
      end
      pending.started = services.now()
      parent:set_field("gui_creation_pending", pending, { persist = true })
      creation_status(parent, "creating", "Waiting for the new remote")
      local ok, spec, err = pcall(children.create, driver, parent, pending.request, true)
      if not ok or not spec then creation_status(parent, "error", tostring(ok and err or spec)); return end
      watch_creation(driver, parent)
    end)
    add(M.IDS.learning, "selectAction", function(_, device, command)
      if not g.learning_enabled(device) then return end
      if g.busy(device) then g.status(device, "busy", "Finish or cancel the current IR operation first"); return end
      local action = command.args and command.args.action
      if not g.allowed_action(device, action) then
        g.failure(device, "Unsupported signal selection"); return
      end
      device:set_field("gui_selected_action", action, { persist = true })
      g.status(device, "idle", "")
    end)
    add(M.IDS.learning, "learn", function(driver, device)
      if not g.learning_enabled(device) then return end
      local parent = g.parent(device)
      if not parent then g.failure(device, "IR blaster parent is unavailable"); return end
      local result, err
      if services.is_ac(device) then
        local draft = device:get_field("gui_ac_draft")
        if not draft then g.failure(device, "Enable AC learning setup and prepare the capture state first"); return end
        result, err = driver:start_ir_state_learning(parent, device, draft)
      else result, err = driver:start_ir_learning(parent, device, selected(device)) end
      if not result then g.failure(device, err) end
    end)
    add(M.IDS.learning, "cancel", function(driver, device)
      local parent = g.parent(device)
      local result, err
      if parent then result, err = driver:cancel_ir_learning(parent, device) end
      if not result then g.failure(device, err or "No learning session owned by this remote") end
    end)
    add(M.IDS.learning, "test", function(driver, device)
      if not g.learning_enabled(device) then return end
      local parent = g.parent(device)
      if not parent then g.failure(device, "IR blaster parent is unavailable"); return end
      if g.busy(device) then g.status(device, "busy", "IR blaster busy"); return end
      local valid, code = saved_code(device)
      if not valid or not code then g.failure(device, "No saved signal for this selection"); return end
      local ok, payload = pcall(actions.to_payload, code)
      if not ok then g.failure(device, payload); return end
      local result, err = driver:send_ir_code(parent, payload, device, nil, { gui_test = true })
      if result then g.status(device, "testing", "") else g.failure(device, err) end
    end)
    add(M.IDS.learning, "deleteSignal", function(_, device)
      if not g.learning_enabled(device) then return end
      if g.busy(device) then g.status(device, "busy", "IR blaster busy"); return end
      local store, result, err
      if services.is_ac(device) then
        store = ac_store.new(device:get_field("learned_ac_states"))
        result, err = store:remove(g.display_state(device))
        if result then device:set_field("learned_ac_states", store.codes, { persist = true }) end
      else
        store = actions.new(device:get_field("learned_ir_actions"))
        result, err = store:remove(selected(device))
        if result then device:set_field("learned_ir_actions", store.codes, { persist = true }) end
      end
      if result then g.status(device, "deleted", "") else g.failure(device, err) end
    end)
    add(M.IDS.setup, "setSetupMode", function(driver, device, command)
      if not services.is_ac(device) or not g.learning_enabled(device) then return end
      local mode = command.args and command.args.mode
      if mode == "on" then
        if g.busy(device) then g.status(device, "busy", "IR blaster busy"); return end
        if not device:get_field("gui_ac_draft") then
          local source = services.desired_state(device)
          local draft = assert(ac_state.apply(source, { temperature = math.min(30, math.max(16, source.temperature)) }))
          device:set_field("gui_ac_draft", draft)
        end
      elseif mode == "off" then
        local active = services.busy(device)
        if active and active.owner == device.id then
          if active.kind ~= "learn" then g.status(device, "busy", "Wait for the test transfer to finish"); return end
          local result, err = driver:cancel_ir_learning(g.parent(device), device)
          if not result then g.failure(device, err); return end
        end
        device:set_field("gui_ac_draft", nil)
      else g.failure(device, "Unsupported setup mode"); return end
      services.publish_ac(device, g.display_state(device)); g.refresh(device)
    end)
  end
  return g
end

return M
