local M = {}

local modifierAliases = {
    command = "cmd",
    cmd = "cmd",
    control = "ctrl",
    ctrl = "ctrl",
    option = "alt",
    alt = "alt",
    shift = "shift",
    functionkey = "fn",
    fn = "fn",
}

local keyAliases = {
    escape = "escape",
    esc = "escape",
    enter = "return",
    returnkey = "return",
    ["return"] = "return",
    tab = "tab",
    space = "space",
    spacebar = "space",
    delete = "delete",
    backspace = "delete",
    forwarddelete = "forwarddelete",
    left = "left",
    right = "right",
    up = "up",
    down = "down",
    home = "home",
    endkey = "end",
    pagedown = "pagedown",
    pageup = "pageup",
}

local semanticAliases = {
    ["undo"] = { modifiers = { "cmd" }, key = "z" },
    ["redo"] = { modifiers = { "cmd", "shift" }, key = "z" },
    ["copy"] = { modifiers = { "cmd" }, key = "c" },
    ["paste"] = { modifiers = { "cmd" }, key = "v" },
    ["select all"] = { modifiers = { "cmd" }, key = "a" },
    ["escape"] = { modifiers = {}, key = "escape" },
    ["enter"] = { modifiers = {}, key = "return" },
    ["return"] = { modifiers = {}, key = "return" },
}

local modifierOrder = { cmd = 1, alt = 2, ctrl = 3, shift = 4, fn = 5 }

local function copyList(values)
    local result = {}
    for index, value in ipairs(values) do
        result[index] = value
    end
    return result
end

local function normalize(text)
    local value = tostring(text or ""):lower()
    value = value:gsub("double%s+you", "w")
    value = value:gsub("double%s+u", "w")
    value = value:gsub("space%s+bar", "spacebar")
    value = value:gsub("forward%s+delete", "forwarddelete")
    value = value:gsub("page%s+up", "pageup")
    value = value:gsub("page%s+down", "pagedown")
    value = value:gsub("return%s+key", "returnkey")
    value = value:gsub("end%s+key", "endkey")
    value = value:gsub("function%s+key", "functionkey")
    value = value:gsub("left%s+arrow", "left")
    value = value:gsub("right%s+arrow", "right")
    value = value:gsub("up%s+arrow", "up")
    value = value:gsub("down%s+arrow", "down")
    value = value:gsub("[^%w%s]", " ")
    value = value:gsub("%s+", " ")
    return value:match("^%s*(.-)%s*$")
end

local function result(modifiers, key, normalized)
    return {
        modifiers = copyList(modifiers),
        key = key,
        normalized = normalized,
    }
end

function M.parse(text, options)
    options = options or {}
    local normalized = normalize(text)
    if normalized == "" then
        return nil, "No command was heard"
    end

    local alias = semanticAliases[normalized]
    if alias then
        return result(alias.modifiers, alias.key, normalized)
    end

    local modifiers = {}
    local seenModifiers = {}
    local keys = {}
    local ignored = { press = true, key = true, the = true }

    for token in normalized:gmatch("%S+") do
        if token == "super" or token == "hyper" then
            local superModifiers = options.superModifiers or { "cmd", "alt", "ctrl", "shift" }
            for _, modifier in ipairs(superModifiers) do
                if not seenModifiers[modifier] then
                    seenModifiers[modifier] = true
                    table.insert(modifiers, modifier)
                end
            end
        elseif modifierAliases[token] then
            local modifier = modifierAliases[token]
            if not seenModifiers[modifier] then
                seenModifiers[modifier] = true
                table.insert(modifiers, modifier)
            end
        elseif not ignored[token] then
            table.insert(keys, keyAliases[token] or token)
        end
    end

    if #keys == 0 then
        return nil, "The command has modifiers but no key: " .. normalized
    end
    if #keys > 1 then
        return nil, "Expected one key, heard: " .. table.concat(keys, " ")
    end

    local key = keys[1]
    if not key:match("^[a-z0-9]$")
        and not key:match("^f%d%d?$")
        and not keyAliases[key]
        and key ~= "escape"
        and key ~= "return"
        and key ~= "tab"
        and key ~= "space"
        and key ~= "delete"
        and key ~= "forwarddelete"
        and key ~= "left"
        and key ~= "right"
        and key ~= "up"
        and key ~= "down"
        and key ~= "home"
        and key ~= "end"
        and key ~= "pageup"
        and key ~= "pagedown" then
        return nil, "Unknown key: " .. key
    end

    table.sort(modifiers, function(left, right)
        return (modifierOrder[left] or 99) < (modifierOrder[right] or 99)
    end)
    return result(modifiers, key, normalized)
end

function M.normalize(text)
    return normalize(text)
end

return M
