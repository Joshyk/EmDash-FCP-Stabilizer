--- === plugins.finalcutpro.stabilizer ===
---
--- Entry point for Final Cut Pro stabilization presets.

local IMPLEMENTATION_FILE = "stabilizer.lua"
local PLUGIN_VERSION = "0.3.0"
local LOAD_MARKER = "repo-loader-20260529-v1"

local okLogger, logger = pcall(require, "hs.logger")
local log = okLogger and logger and logger.new("stabLoad") or nil

local REPO_DIRECTORY = "/Users/justadev/Developer/EDT/Command-Post-Em_Dash/Stabilizer/"
local WATCHED_SOURCE_FILES = {
    ["init.lua"] = true,
    [IMPLEMENTATION_FILE] = true,
}

local function shellQuote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function dirname(path)
    return tostring(path or ""):match("^(.*[/\\])") or ""
end

local function basename(path)
    return tostring(path or ""):match("([^/\\]+)$") or tostring(path or "")
end

local function fileExists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

local function currentFilePath()
    local source = debug.getinfo(1, "S").source
    return source:sub(1, 1) == "@" and source:sub(2) or source
end

local function readlink(path)
    local handle = io.popen("/usr/bin/readlink " .. shellQuote(path))
    if not handle then return nil end
    local target = handle:read("*l")
    handle:close()
    if not target or target == "" then return nil end
    if target:sub(1, 1) ~= "/" then
        target = dirname(path) .. target
    end
    return target
end

local function implementationPath(fileName)
    local entryPath = currentFilePath()
    local directSibling = dirname(entryPath) .. fileName
    if fileExists(directSibling) then
        return directSibling
    end

    local linkedEntry = readlink(entryPath)
    if linkedEntry then
        local linkedSibling = dirname(linkedEntry) .. fileName
        if fileExists(linkedSibling) then
            return linkedSibling
        end
    end

    local repoSibling = REPO_DIRECTORY .. fileName
    if fileExists(repoSibling) then
        return repoSibling
    end

    error("Unable to find " .. fileName .. " for " .. tostring(entryPath))
end

local function logLoad(message)
    if log and log.i then
        log.i(message)
    elseif print then
        print("stabLoad: " .. message)
    end
end

local function shouldReloadForFlag(flag)
    if not flag then return true end
    if flag.itemRemoved == true then return true end
    return flag.itemIsFile == true
        and (flag.itemModified == true or flag.itemCreated == true or flag.itemRenamed == true)
end

local function startRepoSourceWatcher()
    if type(hs) ~= "table" or not hs.reload then return nil end
    if not fileExists(REPO_DIRECTORY .. "init.lua") then return nil end

    local ok, pathwatcher = pcall(require, "hs.pathwatcher")
    if not ok or not pathwatcher then return nil end

    local reloadTimer = nil
    local watcher = pathwatcher.new(REPO_DIRECTORY, function(files, flagTables)
        for index, file in ipairs(files or {}) do
            if WATCHED_SOURCE_FILES[basename(file)] and shouldReloadForFlag(flagTables and flagTables[index]) then
                if reloadTimer and reloadTimer.stop then reloadTimer:stop() end
                if hs.timer and hs.timer.doAfter then
                    reloadTimer = hs.timer.doAfter(0.25, function() hs.reload() end)
                else
                    hs.reload()
                end
                return
            end
        end
    end)

    return watcher:start()
end

logLoad("Loading repo entry " .. currentFilePath() .. " version=" .. PLUGIN_VERSION .. " marker=" .. LOAD_MARKER)

local implementation = dofile(implementationPath(IMPLEMENTATION_FILE))

local plugin = {
    id = "finalcutpro.stabilizer",
    group = "finalcutpro",
    dependencies = {},
    _repoSourceWatcher = startRepoSourceWatcher(),
}

for id, alias in pairs((implementation and implementation.dependencies) or {}) do
    plugin.dependencies[id] = alias
end

function plugin.init(deps, env)
    local module = {
        _version = PLUGIN_VERSION,
        _loadMarker = LOAD_MARKER,
        _loadedAt = os.date("%Y-%m-%d %H:%M:%S"),
        _loadedFrom = currentFilePath(),
        _implementationPath = implementationPath(IMPLEMENTATION_FILE),
    }
    if implementation and implementation.init then
        module.workflow = implementation.init(deps, env)
    end
    logLoad("Initialized " .. plugin.id .. " version=" .. PLUGIN_VERSION .. " loadedAt=" .. module._loadedAt)
    return module
end

return plugin
