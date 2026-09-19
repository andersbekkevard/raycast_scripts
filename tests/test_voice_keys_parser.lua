local parser = dofile("hammerspoon/voice_keys_parser.lua")

local cases = {
    { "undo", { "cmd" }, "z" },
    { "redo", { "cmd", "shift" }, "z" },
    { "copy", { "cmd" }, "c" },
    { "paste", { "cmd" }, "v" },
    { "select all", { "cmd" }, "a" },
    { "escape", {}, "escape" },
    { "enter", {}, "return" },
    { "Command W.", { "cmd" }, "w" },
    { "command shift Z", { "cmd", "shift" }, "z" },
    { "control shift tab", { "ctrl", "shift" }, "tab" },
    { "command double you", { "cmd" }, "w" },
    { "press option left arrow", { "alt" }, "left" },
    { "super y", { "cmd", "alt", "ctrl", "shift" }, "y" },
    { "super 1", { "cmd", "alt", "ctrl" }, "1", { "cmd", "alt", "ctrl" } },
}

local function sameList(left, right)
    if #left ~= #right then return false end
    for index, value in ipairs(left) do
        if right[index] ~= value then return false end
    end
    return true
end

for _, case in ipairs(cases) do
    local parsed, err = parser.parse(case[1], { superModifiers = case[4] })
    assert(parsed, case[1] .. ": " .. tostring(err))
    assert(parsed.key == case[3], case[1] .. ": expected key " .. case[3] .. ", got " .. parsed.key)
    assert(sameList(parsed.modifiers, case[2]), case[1] .. ": wrong modifiers")
end

local invalid = { "", "command", "command w then command q", "banana" }
for _, text in ipairs(invalid) do
    local parsed = parser.parse(text)
    assert(parsed == nil, "expected rejection: " .. text)
end

print(string.format("voice_keys_parser: %d valid and %d invalid cases passed", #cases, #invalid))
