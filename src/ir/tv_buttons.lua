-- Shared, stable action keys for learning and sending TV buttons.
local M = { buttons = {
  { action = "power_toggle", command = "powerToggle" },
  { action = "up", command = "up" },
  { action = "left", command = "left" },
  { action = "ok", command = "ok" },
  { action = "right", command = "right" },
  { action = "down", command = "down" },
  { action = "back", command = "back" },
  { action = "home", command = "home" },
  { action = "menu", command = "menu" },
  { action = "exit", command = "exit" },
  { action = "volume_up", command = "volumeUp" },
  { action = "volume_down", command = "volumeDown" },
  { action = "mute", command = "mute" },
  { action = "channel_up", command = "channelUp" },
  { action = "channel_down", command = "channelDown" },
  { action = "previous_channel", command = "previousChannel" },
  { action = "input", command = "input" },
  { action = "guide", command = "guide" },
  { action = "info", command = "info" },
  { action = "digit_0", command = "digit0" },
  { action = "digit_1", command = "digit1" },
  { action = "digit_2", command = "digit2" },
  { action = "digit_3", command = "digit3" },
  { action = "digit_4", command = "digit4" },
  { action = "digit_5", command = "digit5" },
  { action = "digit_6", command = "digit6" },
  { action = "digit_7", command = "digit7" },
  { action = "digit_8", command = "digit8" },
  { action = "digit_9", command = "digit9" },
  { action = "dash", command = "dash" },
  { action = "play", command = "play" },
  { action = "pause", command = "pause" },
  { action = "stop", command = "stop" },
  { action = "rewind", command = "rewind" },
  { action = "fast_forward", command = "fastForward" },
  { action = "record", command = "record" },
  { action = "red", command = "red" },
  { action = "green", command = "green" },
  { action = "yellow", command = "yellow" },
  { action = "blue", command = "blue" },
  { action = "subtitles", command = "subtitles" },
  { action = "audio", command = "audio" },
} }
M.actions = { "power_on", "power_off" }
M.valid = { power_on = true, power_off = true }
for _, button in ipairs(M.buttons) do
  M.actions[#M.actions + 1] = button.action
  M.valid[button.action] = true
end
return M
