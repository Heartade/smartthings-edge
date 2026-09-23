-- Minimal parent driver entry point. The Zosung codec is not yet wired to
-- Zigbee messages, so pairing this package does not enable IR control.
local ZigbeeDriver = require "st.zigbee"
local capabilities = require "st.capabilities"
local children = require "children"

local function info_changed(driver, device, _, args)
  local request = device.preferences and device.preferences.addRemoteRequest
  local old = args and args.old_st_store and args.old_st_store.preferences
  if not request or request == (old and old.addRemoteRequest) then return end
  local _, status = children.create(driver, device, request)
  device.log.info("Add remote: " .. tostring(status))
end

local driver = ZigbeeDriver("generic-ir-remote", {
  supported_capabilities = { capabilities.refresh },
  lifecycle_handlers = { infoChanged = info_changed },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = function(_, device)
        device.log.info("IR transport integration pending")
      end
    }
  }
})

driver:run()
