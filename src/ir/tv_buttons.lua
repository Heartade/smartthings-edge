-- Shared, stable action keys for learning and sending TV buttons.
local M = { buttons = {
  { action = "power_toggle", command = "powerToggle", capability = "tv" },
  { action = "up", command = "up", capability = "tv" },
  { action = "left", command = "left", capability = "tv" },
  { action = "ok", command = "ok", capability = "tv" },
  { action = "right", command = "right", capability = "tv" },
  { action = "down", command = "down", capability = "tv" },
  { action = "back", command = "back", capability = "tv" },
  { action = "home", command = "home", capability = "tv" },
  { action = "menu", command = "menu", capability = "tv" },
  { action = "exit", command = "exit", capability = "tv" },
  { action = "volume_up", command = "volumeUp", capability = "tv" },
  { action = "volume_down", command = "volumeDown", capability = "tv" },
  { action = "mute", command = "mute", capability = "tv" },
  { action = "channel_up", command = "channelUp", capability = "tv" },
  { action = "channel_down", command = "channelDown", capability = "tv" },
  { action = "previous_channel", command = "previousChannel", capability = "tv" },
  { action = "input", command = "input", capability = "tv" },
  { action = "guide", command = "guide", capability = "tv" },
  { action = "info", command = "info", capability = "tv" },
  { action = "digit_0", command = "digit0", capability = "tvKeypad" },
  { action = "digit_1", command = "digit1", capability = "tvKeypad" },
  { action = "digit_2", command = "digit2", capability = "tvKeypad" },
  { action = "digit_3", command = "digit3", capability = "tvKeypad" },
  { action = "digit_4", command = "digit4", capability = "tvKeypad" },
  { action = "digit_5", command = "digit5", capability = "tvKeypad" },
  { action = "digit_6", command = "digit6", capability = "tvKeypad" },
  { action = "digit_7", command = "digit7", capability = "tvKeypad" },
  { action = "digit_8", command = "digit8", capability = "tvKeypad" },
  { action = "digit_9", command = "digit9", capability = "tvKeypad" },
  { action = "dash", command = "dash", capability = "tvKeypad" },
  { action = "play", command = "play", capability = "tvMedia" },
  { action = "pause", command = "pause", capability = "tvMedia" },
  { action = "stop", command = "stop", capability = "tvMedia" },
  { action = "rewind", command = "rewind", capability = "tvMedia" },
  { action = "fast_forward", command = "fastForward", capability = "tvMedia" },
  { action = "record", command = "record", capability = "tvMedia" },
  { action = "red", command = "red", capability = "tvMedia" },
  { action = "green", command = "green", capability = "tvMedia" },
  { action = "yellow", command = "yellow", capability = "tvMedia" },
  { action = "blue", command = "blue", capability = "tvMedia" },
  { action = "subtitles", command = "subtitles", capability = "tvMedia" },
  { action = "settings", command = "settings", capability = "tv" },
  { action = "audio", command = "audio", capability = "tvMedia" },
} }
M.actions = { "power_on", "power_off" }
M.valid = { power_on = true, power_off = true }
for _, button in ipairs(M.buttons) do
  M.actions[#M.actions + 1] = button.action
  M.valid[button.action] = true
end
return M
