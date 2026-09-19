local root = "/Users/andersbekkevard/dev/misc/raycast_scripts/hammerspoon"

require("hs.ipc")

local voiceKeysModule = dofile(root .. "/voice_keys.lua")
voiceKeys = voiceKeysModule.start({
    triggerMouseButton = 2,
    autoStopOnSilence = true,
    maxRecordingSeconds = 8,
    superModifiers = { "cmd", "alt", "ctrl" },
})

hs.autoLaunch(true)
