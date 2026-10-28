-- Child creation request: unique-token|profile|display name.
-- A unique token makes retries idempotent and permits duplicate display names.
local M = {}
local profiles = {
  ["remote-tv"] = true, ["remote-fan"] = true, ["remote-generic"] = true, ["remote-button"] = true,
  ["ac-protocol-learning"] = true, ["ac-button"] = true, ["ac-learned-state"] = true, ["ac-protocol"] = true,
  ["ir-logger"] = true
}

function M.parse(request)
  if type(request) ~= "string" then return nil, "missing request" end
  local token, profile, label = request:match("^([%w%-]+)|([%w%-]+)|(.+)$")
  local valid_utf8, length = pcall(utf8.len, label or "")
  if not token or #token > 24 or not profiles[profile] or
    not valid_utf8 or not length or length > 60 or label:find("|", 1, true) or not label:match("%S") then
    return nil, "expected unique-token|profile|display name"
  end
  return { key = "remote-" .. token, profile = profile, label = label }
end

function M.create(driver, parent, request, retry)
  local spec, err = M.parse(request)
  if not spec then return nil, err end
  if parent:get_child_by_parent_assigned_key(spec.key) then
    return spec, "already exists"
  end
  if not retry and parent:get_field("last_child_request") == request then
    return spec, "already requested"
  end
  local metadata = {
    type = "EDGE_CHILD",
    parent_device_id = parent.id,
    parent_assigned_child_key = spec.key,
    device_network_id = parent.device_network_id .. ":" .. spec.key,
    label = spec.label,
    profile = spec.profile,
    manufacturer = "Generic IR",
    model = spec.profile,
    vendor_provided_label = spec.label
  }
  local types = parent:get_field("ir_child_types") or {}
  types[spec.key] = spec.profile
  parent:set_field("ir_child_types", types, { persist = true })
  driver:try_create_device(metadata)
  parent:set_field("last_child_request", request, { persist = true })
  return spec, "requested"
end

return M
