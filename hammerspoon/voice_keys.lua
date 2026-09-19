local M = {}

local source = debug.getinfo(1, "S").source:sub(2)
local directory = source:match("(.*/)") or "./"
local parser = dofile(directory .. "voice_keys_parser.lua")
local log = hs.logger.new("voice-keys", "info")

local defaults = {
    triggerKey = "F18",
    triggerModifiers = {},
    triggerMouseButton = nil,
    autoStopOnSilence = false,
    maxRecordingSeconds = 8,
    recorder = "/opt/homebrew/bin/rec",
    transcriber = "/Applications/TypeWhisper.app/Contents/MacOS/typewhisper-cli",
    language = "en",
    engine = "groq",
    model = "whisper-large-v3-turbo",
    superModifiers = { "cmd", "alt", "ctrl", "shift" },
    keyDelayMicroseconds = 0,
}

local config = {}
local state = {
    recordingTask = nil,
    transcriptionTask = nil,
    audioPath = nil,
    pressedAt = nil,
    releasedAt = nil,
    releaseRequested = false,
    last = nil,
    stage = "idle",
    visualAlert = nil,
    maxRecordingTimer = nil,
}

local visualStyles = {
    listening = {
        fillColor = { red = 0.08, green = 0.55, blue = 0.25, alpha = 0.96 },
        strokeColor = { white = 1, alpha = 0.25 },
        textColor = { white = 1 },
        radius = 12,
        textSize = 22,
    },
    transcribing = {
        fillColor = { red = 0.90, green = 0.55, blue = 0.05, alpha = 0.96 },
        strokeColor = { white = 1, alpha = 0.25 },
        textColor = { white = 1 },
        radius = 12,
        textSize = 22,
    },
    executed = {
        fillColor = { red = 0.10, green = 0.38, blue = 0.82, alpha = 0.96 },
        strokeColor = { white = 1, alpha = 0.25 },
        textColor = { white = 1 },
        radius = 12,
        textSize = 22,
    },
    error = {
        fillColor = { red = 0.78, green = 0.12, blue = 0.14, alpha = 0.96 },
        strokeColor = { white = 1, alpha = 0.25 },
        textColor = { white = 1 },
        radius = 12,
        textSize = 19,
    },
}

local function mergeConfig(overrides)
    local merged = {}
    for key, value in pairs(defaults) do
        merged[key] = value
    end
    for key, value in pairs(overrides or {}) do
        merged[key] = value
    end
    return merged
end

local function now()
    return hs.timer.secondsSinceEpoch()
end

local function elapsedMilliseconds(startedAt)
    return math.floor((now() - startedAt) * 1000 + 0.5)
end

local function showVisual(message, stage, duration)
    if state.visualAlert then
        pcall(hs.alert.closeSpecific, state.visualAlert)
        state.visualAlert = nil
    end
    state.stage = stage
    state.visualAlert = hs.alert.show(
        "Voice Keys  ·  " .. message,
        visualStyles[stage],
        hs.screen.mainScreen(),
        duration or 3600
    )
end

local function fail(message)
    log.e(message)
    state.last = { ok = false, error = message, at = os.time() }
    showVisual(message, "error", 2.5)
end

local function removeAudio()
    if state.audioPath then
        os.remove(state.audioPath)
        state.audioPath = nil
    end
end

local function stopMaxRecordingTimer()
    if state.maxRecordingTimer then
        state.maxRecordingTimer:stop()
        state.maxRecordingTimer = nil
    end
end

local function executeParsed(parsed, originalText)
    if hs.keycodes.map[parsed.key] == nil then
        fail("Unsupported key: " .. parsed.key)
        return false
    end

    hs.eventtap.keyStroke(parsed.modifiers, parsed.key, config.keyDelayMicroseconds)
    local latency = state.releasedAt and elapsedMilliseconds(state.releasedAt) or nil
    state.last = {
        ok = true,
        text = originalText,
        normalized = parsed.normalized,
        modifiers = parsed.modifiers,
        key = parsed.key,
        latencyMs = latency,
        at = os.time(),
    }
    log.i(string.format(
        "executed '%s' as %s+%s in %dms after release",
        parsed.normalized,
        table.concat(parsed.modifiers, "+"),
        parsed.key,
        latency or -1
    ))
    local chord = table.concat(parsed.modifiers, "+")
    if chord ~= "" then chord = chord .. "+" end
    showVisual("Executed " .. chord .. parsed.key, "executed", 1.25)
    return true
end

function M.executeText(text)
    local parsed, parseError = parser.parse(text, { superModifiers = config.superModifiers })
    if not parsed then
        fail(parseError)
        return false, parseError
    end
    return executeParsed(parsed, text), parsed
end

local function transcribe()
    local audioPath = state.audioPath
    if not audioPath or not hs.fs.attributes(audioPath) then
        fail("Recorder produced no audio")
        removeAudio()
        return
    end

    local arguments = {
        "transcribe",
        audioPath,
        "--language", config.language,
        "--engine", config.engine,
        "--model", config.model,
        "--json",
    }

    state.transcriptionTask = hs.task.new(config.transcriber, function(exitCode, stdout, stderr)
        state.transcriptionTask = nil
        removeAudio()
        if exitCode ~= 0 then
            fail("Transcription failed: " .. ((stderr ~= "" and stderr) or ("exit " .. exitCode)))
            return
        end

        local ok, payload = pcall(hs.json.decode, stdout)
        if not ok or type(payload) ~= "table" then
            fail("TypeWhisper returned invalid JSON")
            return
        end

        local text = payload.text
        if type(text) ~= "string" or text:match("^%s*$") then
            fail("TypeWhisper returned no text")
            return
        end
        M.executeText(text)
    end, arguments)

    if not state.transcriptionTask or not state.transcriptionTask:start() then
        state.transcriptionTask = nil
        removeAudio()
        fail("Could not start TypeWhisper transcription")
    end
end

local function recorderExited(exitCode, _, stderr)
    state.recordingTask = nil
    stopMaxRecordingTimer()
    if config.autoStopOnSilence and not state.releaseRequested and exitCode == 0 then
        state.releasedAt = now()
        state.releaseRequested = true
        showVisual("Transcribing", "transcribing")
    end
    if not state.releaseRequested then
        removeAudio()
        fail("Recorder stopped unexpectedly: " .. ((stderr ~= "" and stderr) or ("exit " .. exitCode)))
        return
    end
    transcribe()
end

function M.press()
    if state.recordingTask or state.transcriptionTask then
        return false
    end

    state.audioPath = string.format("/tmp/voice-keys-%d-%d.wav", os.time(), math.random(100000, 999999))
    state.pressedAt = now()
    state.releasedAt = nil
    state.releaseRequested = false
    showVisual("Listening", "listening")

    local arguments = {
        "-q",
        "-c", "1",
        "-r", "16000",
        "-b", "16",
        state.audioPath,
    }
    if config.autoStopOnSilence then
        table.insert(arguments, "silence")
        table.insert(arguments, "1")
        table.insert(arguments, "0.03")
        table.insert(arguments, "0.5%")
        table.insert(arguments, "1")
        table.insert(arguments, "0.55")
        table.insert(arguments, "0.5%")
    end
    state.recordingTask = hs.task.new(config.recorder, recorderExited, arguments)
    if not state.recordingTask or not state.recordingTask:start() then
        state.recordingTask = nil
        removeAudio()
        fail("Could not start microphone recording")
        return false
    end
    if config.autoStopOnSilence then
        state.maxRecordingTimer = hs.timer.doAfter(config.maxRecordingSeconds, function()
            M.release()
        end)
    end
    return true
end

function M.release()
    if not state.recordingTask or not state.recordingTask:isRunning() then
        return false
    end
    state.releasedAt = now()
    state.releaseRequested = true
    stopMaxRecordingTimer()
    showVisual("Transcribing", "transcribing")
    state.recordingTask:interrupt()
    return true
end

function M.status()
    return {
        recording = state.recordingTask ~= nil,
        transcribing = state.transcriptionTask ~= nil,
        last = state.last,
        stage = state.stage,
        triggerKey = config.triggerKey,
        triggerModifiers = config.triggerModifiers,
        triggerMouseButton = config.triggerMouseButton,
    }
end

function M.showFeedback(message, stage, duration)
    showVisual(message, stage or "executed", duration or 1.25)
end

function M.start(overrides)
    config = mergeConfig(overrides)
    if M.hotkey then
        M.hotkey:delete()
        M.hotkey = nil
    end
    if M.mouseTap then
        M.mouseTap:stop()
        M.mouseTap = nil
    end

    if config.triggerMouseButton ~= nil then
        local types = hs.eventtap.event.types
        local buttonProperty = hs.eventtap.event.properties.mouseEventButtonNumber
        M.mouseTap = hs.eventtap.new({ types.otherMouseDown, types.otherMouseUp }, function(event)
            if event:getProperty(buttonProperty) ~= config.triggerMouseButton then
                return false
            end
            if event:getType() == types.otherMouseDown then
                M.press()
            elseif not config.autoStopOnSilence then
                M.release()
            end
            return true
        end):start()
        log.i("hold-to-command ready on mouse button " .. config.triggerMouseButton)
        return M
    end
    M.hotkey = hs.hotkey.bind(config.triggerModifiers, config.triggerKey, M.press, M.release)
    if not M.hotkey then
        error("Voice Keys could not bind " .. config.triggerKey)
    end
    local trigger = table.concat(config.triggerModifiers, "+")
    if trigger ~= "" then trigger = trigger .. "+" end
    log.i("hold-to-command ready on " .. trigger .. config.triggerKey)
    return M
end

M.parse = parser.parse

return M
