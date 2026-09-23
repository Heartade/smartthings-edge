-- Minimal parent driver entry point. The Zosung codec is not yet wired to
-- Zigbee messages, so pairing this package does not enable IR control.
local ZigbeeDriver = require "st.zigbee"
local capabilities = require "st.capabilities"

local driver = ZigbeeDriver("generic-ir-remote", {
  supported_capabilities = { capabilities.refresh },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = function(_, device)
        device.log.info("IR transport integration pending")
      end
    }
  }
})

driver:run()
