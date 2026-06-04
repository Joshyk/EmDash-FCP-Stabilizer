--- === plugins.finalcutpro.stabilizer.workflow ===
---
--- Applies one dynamic stabilization workflow to the selected Final Cut Pro clip.

local require = require
local hs = _G.hs

local log = require "hs.logger".new "stabPreset"
local dialog = require "cp.dialog"
local fcp = require "cp.apple.finalcutpro"
local flicks = require "cp.time.flicks"
local json = require "cp.json"
local pasteboard = require "hs.pasteboard"
local osascript = require "hs.osascript"
local plist = require "cp.plist"
local archiver = require "cp.plist.archiver"
local base64 = require "hs.base64"
local fs = require "hs.fs"
local timer = require "hs.timer"
local eventtap = require "hs.eventtap"
local alert = require "hs.alert"
local task = require "hs.task"
local canvasOK, canvas = pcall(require, "hs.canvas")
local screenOK, screen = pcall(require, "hs.screen")
if not canvasOK then canvas = nil end
if not screenOK then screen = nil end

local format = string.format
local usleep = timer.usleep

local mod = {}

local ACTION_TITLE = "Stabilizer: Transform Keyframes"
local ACTION_ID = "stabilizerDynamicStrengthScale"
local FXPLUG_CACHE_ACTION_TITLE = "Stabilizer: Analyze FxPlug Cache"
local FXPLUG_CACHE_ACTION_ID = "stabilizerAnalyzeFxPlugCache"
local REPO_DIRECTORY = "/Users/justadev/Developer/EDT/Command-Post-Em_Dash/Stabilizer"
local ESTIMATOR_SCRIPT = REPO_DIRECTORY .. "/scripts/estimate_stabilization_scale.py"
local GPU_ESTIMATOR_SCRIPT = REPO_DIRECTORY .. "/scripts/estimate_stabilization_gpu.swift"
local PYTHON_BINARY = os.getenv("STABILIZER_PYTHON") or "/Library/Frameworks/Python.framework/Versions/3.10/bin/python3"
local SWIFT_RUNNER = os.getenv("STABILIZER_SWIFT_RUNNER") or "/usr/bin/xcrun"
local FXPLUG_CACHE_PATH = os.getenv("STABILIZER_FXPLUG_CACHE_PATH") or ((os.getenv("HOME") or "") .. "/Library/Application Support/CommandPost/StabilizerFxPlug/current.json")
local DEFAULT_INTERVAL_FRAMES = "3"
local DEFAULT_FXPLUG_CACHE_FPS = "15"
local DEFAULT_PAN_SMOOTH_SECONDS = "6"
local MAX_SAMPLES = 240
local CONTROL_READY_TIMEOUT_SECONDS = 12
local KEYFRAME_CONFIRM_TIMEOUT_SECONDS = 1.5
local PLAYHEAD_ENTRY_TIMEOUT_SECONDS = 1.4
local PASTE_TIMECODE_MOVE_TIMEOUT_SECONDS = 1.4
local FCP_PASTEBOARD_UTI = "com.apple.flexo.proFFPasteboardUTI"

local playheadMovePreferredMethod = nil
local restorePasteboard
local withTextPasteboard
local activeCacheTasks = {}

local function sleep(seconds)
    usleep((seconds or 0.1) * 1000000)
end

local function shellQuote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function fileExists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

local function parentDirectory(path)
    return tostring(path or ""):match("^(.*)/[^/]*$") or ""
end

local function ensureDirectory(path)
    if path == nil or path == "" then
        return false, "Directory path was empty."
    end
    local _, ok = hs.execute("/bin/mkdir -p " .. shellQuote(path), true)
    if not ok then
        return false, "Could not create directory: " .. tostring(path)
    end
    return true, nil
end

local function readTextFile(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local text = file:read("*a")
    file:close()
    return text
end

local function removeFile(path)
    if path and path ~= "" then
        os.remove(path)
    end
end

local function progressUIStart(title)
    if not canvas or not screen or not screen.mainScreen then
        return nil
    end
    local mainScreen = screen.mainScreen()
    if not mainScreen then return nil end
    local frame = mainScreen:frame()
    local width = 520
    local height = 126
    local view = canvas.new({
        x = frame.x + ((frame.w - width) / 2),
        y = frame.y + 88,
        w = width,
        h = height,
    })
    if not view then return nil end
    view:appendElements({
        {
            type = "rectangle",
            action = "fill",
            frame = { x = 0, y = 0, w = width, h = height },
            roundedRectRadii = { xRadius = 10, yRadius = 10 },
            fillColor = { white = 0.08, alpha = 0.92 },
        },
        {
            type = "text",
            text = tostring(title or "Stabilizer"),
            frame = { x = 24, y = 18, w = width - 48, h = 22 },
            textColor = { white = 1.0, alpha = 1.0 },
            textSize = 15,
        },
        {
            type = "rectangle",
            action = "fill",
            frame = { x = 24, y = 58, w = width - 48, h = 14 },
            roundedRectRadii = { xRadius = 7, yRadius = 7 },
            fillColor = { white = 0.30, alpha = 1.0 },
        },
        {
            type = "rectangle",
            action = "fill",
            frame = { x = 24, y = 58, w = 1, h = 14 },
            roundedRectRadii = { xRadius = 7, yRadius = 7 },
            fillColor = { red = 0.20, green = 0.58, blue = 1.0, alpha = 1.0 },
        },
        {
            type = "text",
            text = "0%",
            frame = { x = width - 82, y = 78, w = 58, h = 20 },
            textAlignment = "right",
            textColor = { white = 0.92, alpha = 1.0 },
            textSize = 12,
        },
        {
            type = "text",
            text = "Starting...",
            frame = { x = 24, y = 78, w = width - 116, h = 26 },
            textColor = { white = 0.82, alpha = 1.0 },
            textSize = 12,
        },
    })
    if view.level then
        pcall(function() view:level("floating") end)
    end
    if view.behavior then
        pcall(function() view:behavior({ "canJoinAllSpaces", "fullScreenAuxiliary" }) end)
    end
    view:show()
    return { view = view, width = width, barWidth = width - 48 }
end

local function progressUIUpdate(progress, percent, message)
    if not progress or not progress.view then return end
    local value = math.max(0, math.min(1, tonumber(percent) or 0))
    local fillWidth = math.max(1, progress.barWidth * value)
    pcall(function()
        progress.view[4].frame = { x = 24, y = 58, w = fillWidth, h = 14 }
        progress.view[5].text = tostring(math.floor((value * 100) + 0.5)) .. "%"
        progress.view[6].text = tostring(message or "")
    end)
end

local function progressUIStop(progress)
    if progress and progress.view then
        pcall(function() progress.view:delete() end)
    end
end

local function activateFinalCutPro()
    local ok = osascript.applescript([[tell application id "com.apple.FinalCut" to activate]])
    sleep(0.3)
    return ok
end

local function displayError(title, detail)
    dialog.displayErrorMessage(tostring(title or "Stabilizer") .. "\n\n" .. tostring(detail or ""))
end

local function displayMessage(title, detail)
    dialog.displayAlertMessage(tostring(title or "Stabilizer"), tostring(detail or ""))
end

local function showFailure(title, detail)
    local text = tostring(title or ACTION_TITLE) .. "\n" .. tostring(detail or "")
    log.ef("%s failed: %s", tostring(title or ACTION_TITLE), tostring(detail or ""))
    if alert and alert.show then
        pcall(function() alert.show(text, 6) end)
    end
end

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function oneLine(value, maxLength)
    local text = tostring(value or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    local limit = tonumber(maxLength) or 240
    if #text > limit then
        return text:sub(1, limit) .. "..."
    end
    return text
end

local function logStage(stage, message, fields)
    local parts = {
        "Stabilizer",
        tostring(stage or "stage"),
        tostring(message or ""),
    }
    if type(fields) == "table" then
        for _, field in ipairs(fields) do
            if type(field) == "table" then
                parts[#parts + 1] = tostring(field[1]) .. "=" .. tostring(field[2])
            else
                parts[#parts + 1] = tostring(field)
            end
        end
    end
    log.i(table.concat(parts, " | "))
end

local function elementAttribute(element, attribute)
    if not element then return nil end
    local ok, value = pcall(function() return element:attributeValue(attribute) end)
    return ok and value or nil
end

local function elementText(element)
    if not element then return "" end
    local parts = {}
    local function add(value)
        if value ~= nil and value ~= "" then
            parts[#parts + 1] = tostring(value)
        end
    end

    add(elementAttribute(element, "AXTitle"))
    add(elementAttribute(element, "AXDescription"))
    add(elementAttribute(element, "AXValue"))
    add(elementAttribute(element, "AXHelp"))

    local children = elementAttribute(element, "AXChildren")
    if type(children) == "table" then
        for _, child in ipairs(children) do
            add(elementAttribute(child, "AXRole"))
            add(elementAttribute(child, "AXSubrole"))
            add(elementAttribute(child, "AXTitle"))
            add(elementAttribute(child, "AXDescription"))
            add(elementAttribute(child, "AXValue"))
            add(elementAttribute(child, "AXHelp"))
        end
    end

    return table.concat(parts, " ")
end

local function clipLabel(clip, fallback)
    local title = trim(elementAttribute(clip, "AXTitle"))
    if title ~= "" then return title end

    local description = trim(elementText(clip)):gsub("%s+", " ")
    if description ~= "" then
        if #description > 90 then
            return description:sub(1, 87) .. "..."
        end
        return description
    end
    return fallback or "timeline clip"
end

local function selectedClipsUI(includeChildren)
    fcp.timeline:show()
    fcp.timeline.contents:focus()
    local ok, selected = pcall(function()
        return fcp.timeline.contents:selectedClipsUI(includeChildren == true)
    end)
    if ok and type(selected) == "table" then
        return selected
    end
    return {}
end

local function normalizedText(value)
    return tostring(value or ""):lower():gsub("%s+", " ")
end

local function elementRole(element)
    local role = ""
    pcall(function() role = tostring(element:attributeValue("AXRole") or "") end)
    return role
end

local function elementFrame(element)
    local ok, frame = pcall(function() return element:attributeValue("AXFrame") end)
    return ok and frame or nil
end

local function frameArea(frame)
    if not frame then return 0 end
    return math.max(0, tonumber(frame.w) or 0) * math.max(0, tonumber(frame.h) or 0)
end

local function frameOverlapArea(a, b)
    if not a or not b then return 0 end
    local overlapW = math.max(0, math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x))
    local overlapH = math.max(0, math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y))
    return overlapW * overlapH
end

local function isTimelineVideoClip(element)
    local description = trim(elementAttribute(element, "AXDescription"))
    return description:find("AV%-Clip:", 1, false) == 1
end

local function isRecoverableAccessoryElement(element)
    local text = normalizedText(elementText(element))
    if text:find("item accessory", 1, true) then return true end
    if text:find("video animation", 1, true) then return true end

    local role = elementRole(element)
    return role == "AXGroup" or role == "AXButton"
end

local function timelineClipElementsMatch(a, b)
    if not a or not b then return false end
    if a == b then return true end

    local aFrame = elementFrame(a)
    local bFrame = elementFrame(b)
    local overlap = frameOverlapArea(aFrame, bFrame)
    local smallestArea = math.min(frameArea(aFrame), frameArea(bFrame))
    if smallestArea <= 0 or (overlap / smallestArea) < 0.75 then
        return false
    end

    local aLabel = normalizedText(elementText(a))
    local bLabel = normalizedText(elementText(b))
    return aLabel == "" or bLabel == "" or aLabel == bLabel
end

local function appendUniqueVideoClip(clips, element)
    if not element or not isTimelineVideoClip(element) then return false end
    for _, existing in ipairs(clips) do
        if timelineClipElementsMatch(existing, element) then
            return false
        end
    end
    clips[#clips + 1] = element
    return true
end

local function collectTimelineVideoClipElements(element, results)
    results = results or {}
    if not element then return results end

    local children = elementAttribute(element, "AXChildren")
    if type(children) ~= "table" then return results end
    for _, child in ipairs(children) do
        if isTimelineVideoClip(child) then
            appendUniqueVideoClip(results, child)
        end
        collectTimelineVideoClipElements(child, results)
    end
    return results
end

local function collectSelectedTimelineElements(element, results)
    results = results or {}
    if not element then return results end

    local selected = false
    pcall(function() selected = element:attributeValue("AXSelected") == true end)
    if selected then
        results[#results + 1] = element
    end

    local children = elementAttribute(element, "AXChildren")
    if type(children) == "table" then
        for _, child in ipairs(children) do
            collectSelectedTimelineElements(child, results)
        end
    end
    return results
end

local function recoverVideoClipsFromAccessorySelection(selected)
    local contentsUI = nil
    pcall(function() contentsUI = fcp.timeline.contents:UI() end)
    if not contentsUI then return {} end

    local candidates = collectTimelineVideoClipElements(contentsUI)
    local recovered = {}
    for _, selectedElement in ipairs(selected or {}) do
        if isRecoverableAccessoryElement(selectedElement) then
            local bestClip = nil
            local bestArea = 0
            local bestFrame = nil
            local selectedFrame = elementFrame(selectedElement)
            for _, candidate in ipairs(candidates) do
                local candidateFrame = elementFrame(candidate)
                local area = frameOverlapArea(selectedFrame, candidateFrame)
                if area > bestArea then
                    bestArea = area
                    bestClip = candidate
                    bestFrame = candidateFrame
                end
            end
            local smallestArea = math.min(frameArea(selectedFrame), frameArea(bestFrame))
            local coverage = smallestArea > 0 and (bestArea / smallestArea) or 0
            if bestClip and coverage >= 0.5 and appendUniqueVideoClip(recovered, bestClip) then
                log.wf("Recovered selected timeline video clip from accessory selection overlap: %s", clipLabel(bestClip))
            end
        end
    end
    return recovered
end

local function recoverVideoClipsFromAXSelectedTimeline()
    local contentsUI = nil
    pcall(function() contentsUI = fcp.timeline.contents:UI() end)
    if not contentsUI then return {} end

    local selectedElements = collectSelectedTimelineElements(contentsUI)
    if #selectedElements < 1 then return {} end

    log.wf("Scanning %d AXSelected timeline element(s) for selected video clip recovery.", #selectedElements)
    local recovered = {}
    for _, element in ipairs(selectedElements) do
        appendUniqueVideoClip(recovered, element)
    end
    for _, recoveredClip in ipairs(recoverVideoClipsFromAccessorySelection(selectedElements)) do
        appendUniqueVideoClip(recovered, recoveredClip)
    end
    return recovered
end

local function recoverVideoClipsAfterHidingVideoAnimation()
    log.w("Attempting selected video clip recovery by hiding Video Animation and rereading the timeline selection.")
    fcp.timeline:show()
    fcp.timeline.contents:focus()
    local hidden = fcp:selectMenu({"Clip", "Hide Video Animation"})
    if not hidden then
        eventtap.keyStroke({"ctrl"}, "v", 0, fcp:application())
    end
    sleep(0.35)
    fcp.timeline.contents:focus()
    sleep(0.15)

    local recovered = {}
    for _, element in ipairs(selectedClipsUI(false)) do
        appendUniqueVideoClip(recovered, element)
    end
    if #recovered < 1 then
        for _, element in ipairs(selectedClipsUI(true)) do
            appendUniqueVideoClip(recovered, element)
        end
    end
    if #recovered > 0 then
        log.wf("Recovered %d selected timeline video clip(s) after hiding Video Animation.", #recovered)
    end
    return recovered
end

local function selectedTimelineVideoClips()
    local selected = selectedClipsUI(false)
    local videoClips = {}
    for _, element in ipairs(selected) do
        appendUniqueVideoClip(videoClips, element)
    end
    if #videoClips < 1 then
        for _, recoveredClip in ipairs(recoverVideoClipsFromAccessorySelection(selected)) do
            appendUniqueVideoClip(videoClips, recoveredClip)
        end
    end
    if #videoClips < 1 then
        for _, element in ipairs(selectedClipsUI(true)) do
            appendUniqueVideoClip(videoClips, element)
        end
    end
    if #videoClips < 1 then
        for _, recoveredClip in ipairs(recoverVideoClipsFromAXSelectedTimeline()) do
            appendUniqueVideoClip(videoClips, recoveredClip)
        end
    end
    if #videoClips < 1 and selected[1] and isRecoverableAccessoryElement(selected[1]) then
        for _, recoveredClip in ipairs(recoverVideoClipsAfterHidingVideoAnimation()) do
            appendUniqueVideoClip(videoClips, recoveredClip)
        end
    end
    return videoClips, selected
end

local function chooseBestVideoClip(candidates)
    if #candidates == 1 then return candidates[1] end
    table.sort(candidates, function(a, b)
        local af = elementFrame(a)
        local bf = elementFrame(b)
        local aw = af and tonumber(af.w) or math.huge
        local bw = bf and tonumber(bf.w) or math.huge
        return aw < bw
    end)
    return candidates[1]
end

local function timecodeFrameRate(frameRate)
    local value = tonumber(frameRate) or 30
    local rounded = math.floor(value + 0.5)
    if rounded < 1 then return 30 end
    return rounded
end

local function parseTimecodePair(startTC, endTC, frameRate)
    if not startTC or not endTC then return nil, nil end
    local fps = timecodeFrameRate(frameRate)
    local okStart, startFlicks = pcall(function() return flicks.parse(startTC, fps) end)
    local okEnd, endFlicks = pcall(function() return flicks.parse(endTC, fps) end)
    if okStart and okEnd then
        return startFlicks, endFlicks
    end
    return nil, nil
end

local function parseTimecodeValue(value, frameRate)
    if not value or value == "" then return nil end
    local fps = timecodeFrameRate(frameRate)
    local ok, parsed = pcall(function() return flicks.parse(tostring(value), fps) end)
    return ok and parsed or nil
end

local function collectTimecodeValues(element, frameRate, result, depth)
    result = result or {}
    depth = depth or 0
    if not element or depth > 3 then return result end

    local value = elementAttribute(element, "AXValue")
    local parsed = parseTimecodeValue(value, frameRate)
    if parsed then
        result[#result + 1] = { text = tostring(value), flicks = parsed }
    end

    local children = elementAttribute(element, "AXChildren")
    if type(children) == "table" then
        for _, child in ipairs(children) do
            collectTimecodeValues(child, frameRate, result, depth + 1)
        end
    end
    return result
end

local function clipTimecodeSpan(clip, frameRate)
    local children = elementAttribute(clip, "AXChildren")
    local startTC = children and children[1] and elementAttribute(children[1], "AXValue")
    local endTC = children and children[2] and elementAttribute(children[2], "AXValue")
    local startFlicks, endFlicks = parseTimecodePair(startTC, endTC, frameRate)
    if startFlicks and endFlicks then
        return startFlicks, endFlicks, "direct AXChildren[1:2]"
    end

    local values = collectTimecodeValues(clip, frameRate)
    for index = 1, #values - 1 do
        startFlicks = values[index].flicks
        endFlicks = values[index + 1].flicks
        if startFlicks and endFlicks and endFlicks > startFlicks then
            return startFlicks, endFlicks, "AX descendant values"
        end
    end
    return nil, nil, "AX timecode values unavailable"
end

local function playheadFlicks(frameRate)
    local timecode = fcp.timeline.playhead:timecode()
    if not timecode then return nil end
    local fps = timecodeFrameRate(frameRate)
    local ok, parsed = pcall(function() return flicks.parse(timecode, fps) end)
    return ok and parsed or nil
end

local function offsetFrom(startFlicks, seconds)
    return startFlicks + flicks(math.floor((seconds * flicks.perSecond) + 0.5))
end

local function selectedDurationText()
    local durationUI = fcp.timeline.toolbar.duration:UI()
    local value = durationUI and elementAttribute(durationUI, "AXValue")
    if not value or value == "" then return nil end
    local selection = tostring(value):match("^%s*([^/／]+)%s*[/／]")
    return selection or value
end

local function durationSecondsFromToolbar(frameRate)
    local text = selectedDurationText()
    if not text then return nil end
    text = tostring(text):gsub("%s+", "")
    local parsed = parseTimecodeValue(text, frameRate)
    return parsed and parsed:toSeconds() or nil
end

local function selectOnlyTimelineClip(clip)
    if not clip then return false end
    fcp.timeline:show()
    fcp.timeline.contents:focus()
    pcall(function() fcp.timeline.contents:selectNone() end)
    sleep(0.08)
    local ok = pcall(function() fcp.timeline.contents:selectClip(clip) end)
    sleep(0.2)
    if not ok then return false end

    local videoClips = selectedTimelineVideoClips()
    return #videoClips == 1 and timelineClipElementsMatch(videoClips[1], clip)
end

local function selectedClipTimelineSpanFromSelection(clip, frameRate, originalTimecode)
    if not clip then return nil, nil end

    originalTimecode = originalTimecode or fcp.timeline.playhead:timecode()
    if not selectOnlyTimelineClip(clip) then
        return nil, nil, "could not reselect the intended timeline clip"
    end

    local duration = durationSecondsFromToolbar(frameRate)
    log.wf(
        "%s: AX timeline span unavailable; deriving selected clip span via Final Cut Pro Set Clip Range.",
        ACTION_TITLE
    )

    local setRange = fcp:selectMenu({"Mark", "Set Clip Range"})
    sleep(0.25)
    if not setRange then
        if originalTimecode then
            pcall(function() fcp.timeline.playhead:timecode(originalTimecode) end)
        end
        return nil, nil, "Final Cut Pro did not accept Mark > Set Clip Range"
    end

    local startFlicks, endFlicks
    if fcp:selectMenu({"Mark", "Go to", "Range Start"}) then
        sleep(0.25)
        startFlicks = playheadFlicks(frameRate)
    end
    if fcp:selectMenu({"Mark", "Go to", "Range End"}) then
        sleep(0.25)
        endFlicks = playheadFlicks(frameRate)
    end
    if startFlicks and not endFlicks and duration then
        endFlicks = offsetFrom(startFlicks, duration)
    end

    if originalTimecode then
        pcall(function() fcp.timeline.playhead:timecode(originalTimecode) end)
    end

    if startFlicks and endFlicks then
        return startFlicks, endFlicks, "FCP Set Clip Range"
    end
    return nil, nil, "could not derive range start/end from Final Cut Pro"
end

local function flicksCloseEnough(a, b)
    if not a or not b then return false end
    return math.abs((a - b):toSeconds()) < 0.15
end

local function waitForPlayhead(targetFlicks, frameRate, timeoutSeconds)
    local deadline = timer.secondsSinceEpoch() + (timeoutSeconds or PLAYHEAD_ENTRY_TIMEOUT_SECONDS)
    local current
    sleep(0.04)
    repeat
        current = playheadFlicks(frameRate)
        if flicksCloseEnough(current, targetFlicks) then
            return true, current
        end
        sleep(0.04)
    until timer.secondsSinceEpoch() >= deadline
    return false, current
end

local function movePlayheadWithPasteTimecode(targetFlicks, frameRate)
    local targetTimecode = targetFlicks:toTimecode(timecodeFrameRate(frameRate), ":")
    local shortcuts = fcp:getCommandShortcuts("PasteTimecode")
    if type(shortcuts) ~= "table" or #shortcuts == 0 then
        return false, targetTimecode, "Paste Timecode shortcut is not assigned"
    end

    local app = fcp:application()
    local result, detail = withTextPasteboard(targetTimecode, function()
        local ok, err = pcall(function()
            shortcuts[1]:trigger(app)
        end)
        if not ok then
            return false, "Paste Timecode shortcut failed: " .. tostring(err)
        end

        local matched, current = waitForPlayhead(targetFlicks, frameRate, PASTE_TIMECODE_MOVE_TIMEOUT_SECONDS)
        if matched then
            return true, current
        end
        return false, current
    end)
    if result == true then
        return true, targetTimecode, "Paste Timecode shortcut", detail
    end
    if type(detail) == "string" then
        return false, targetTimecode, detail
    end
    return false, targetTimecode, "Paste Timecode shortcut did not reach target", detail
end

local function movePlayheadWithPlayheadPositionCommand(targetFlicks, frameRate)
    local targetTimecode = targetFlicks:toTimecode(timecodeFrameRate(frameRate), ":")
    local entryTimecode = targetTimecode:gsub("[;:]", "")
    fcp:launch()
    fcp.timeline:show()
    fcp.timeline.contents:focus()
    sleep(0.15)

    local app = fcp:application()
    local okShortcut, shortcutResult = pcall(function()
        return fcp:doShortcut("ShowTimecodeEntryPlayhead", true):Now()
    end)
    if not okShortcut or shortcutResult == false then
        eventtap.keyStroke({"ctrl"}, "p", 0, app)
    end

    sleep(0.2)
    local result, detail = withTextPasteboard(entryTimecode, function()
        eventtap.keyStroke({"cmd"}, "a", 0, app)
        sleep(0.03)
        eventtap.keyStroke({"cmd"}, "v", 0, app)
        sleep(0.03)
        eventtap.keyStroke({}, "return", 0, app)

        local matched, current = waitForPlayhead(targetFlicks, frameRate, PLAYHEAD_ENTRY_TIMEOUT_SECONDS)
        if matched then
            return true, current
        end
        return false, current
    end)
    if result == true then
        return true, targetTimecode, "Move Playhead Position paste entry", detail
    end
    return false, targetTimecode, "Move Playhead Position paste entry did not reach target", detail
end

local function movePlayheadToFlicks(targetFlicks, frameRate)
    local targetTimecode = targetFlicks:toTimecode(timecodeFrameRate(frameRate), ":")
    local current = playheadFlicks(frameRate)
    if flicksCloseEnough(current, targetFlicks) then
        return true, targetTimecode, "already at target", current
    end

    if playheadMovePreferredMethod == "pasteTimecode" then
        local moved, timecode, reason, currentAfter = movePlayheadWithPasteTimecode(targetFlicks, frameRate)
        if moved then return true, timecode, reason, currentAfter end
        log.df("%s for %s; trying playhead entry.", tostring(reason), tostring(timecode))
        playheadMovePreferredMethod = nil
    elseif playheadMovePreferredMethod == "entry" then
        local moved, timecode, reason, currentAfter = movePlayheadWithPlayheadPositionCommand(targetFlicks, frameRate)
        if moved then return true, timecode, reason, currentAfter end
        log.df("%s for %s; trying Paste Timecode shortcut.", tostring(reason), tostring(timecode))
        playheadMovePreferredMethod = nil
    end

    local moved, timecode, reason, currentAfter = movePlayheadWithPasteTimecode(targetFlicks, frameRate)
    if moved then
        playheadMovePreferredMethod = "pasteTimecode"
        return true, timecode, reason, currentAfter
    end
    log.df("%s for %s; trying playhead entry.", tostring(reason), tostring(timecode))

    moved, timecode, reason, currentAfter = movePlayheadWithPlayheadPositionCommand(targetFlicks, frameRate)
    if moved then
        playheadMovePreferredMethod = "entry"
        return true, timecode, reason, currentAfter
    end

    return false, targetTimecode, reason or "all playhead move methods failed", currentAfter
end

local function runStatement(statement, failureMessage)
    local ok, result = pcall(function()
        return statement:Now()
    end)
    if not ok then
        return false, tostring(result)
    end
    if result == false then
        return false, failureMessage
    end
    return true, nil
end

local function waitForEnabled(control, timeoutSeconds)
    local deadline = timer.secondsSinceEpoch() + (timeoutSeconds or CONTROL_READY_TIMEOUT_SECONDS)
    repeat
        local ok, enabled = pcall(function()
            return control.isEnabled and control.isEnabled()
        end)
        if ok and enabled == true then
            return true
        end
        sleep(0.25)
    until timer.secondsSinceEpoch() >= deadline
    return false
end

local function setCheckBox(checkBox, enabled, label)
    local statement = enabled and checkBox:doCheck() or checkBox:doUncheck()
    return runStatement(statement, "Could not set " .. label .. ".")
end

local function setPopup(row, flexoID, label)
    if not waitForEnabled(row, CONTROL_READY_TIMEOUT_SECONDS) then
        return false, label .. " is not enabled yet. Final Cut Pro may still be analyzing stabilization."
    end
    local localizedValue = fcp:string(flexoID)
    return runStatement(row:doSelectValue(localizedValue), "Could not set " .. label .. " to " .. tostring(localizedValue) .. ".")
end

local function setNumberRow(row, value, label)
    if not waitForEnabled(row, CONTROL_READY_TIMEOUT_SECONDS) then
        return false, label .. " is not enabled yet. Final Cut Pro may still be analyzing stabilization."
    end
    row:show()
    local ok, err = pcall(function()
        row.value:value(value)
    end)
    if not ok then
        return false, "Could not set " .. label .. ": " .. tostring(err)
    end
    return true, nil
end

local function setXYRow(row, xValue, yValue, label)
    if not waitForEnabled(row, CONTROL_READY_TIMEOUT_SECONDS) then
        return false, label .. " is not enabled."
    end
    row:show()
    local ok, err = pcall(function()
        row.x:value(xValue)
        row.y:value(yValue)
    end)
    if not ok then
        return false, "Could not set " .. label .. ": " .. tostring(err)
    end
    return true, nil
end

local function buttonSummary(button)
    return oneLine(table.concat({
        tostring(elementAttribute(button, "AXTitle") or ""),
        tostring(elementAttribute(button, "AXDescription") or ""),
        tostring(elementAttribute(button, "AXHelp") or ""),
        tostring(elementAttribute(button, "AXValue") or ""),
    }, " "), 160)
end

local function collectDescendants(element, predicate, output, depth)
    output = output or {}
    depth = depth or 0
    if not element or depth > 8 then return output end
    local children = nil
    pcall(function() children = element:attributeValue("AXChildren") end)
    if type(children) ~= "table" then return output end
    for _, child in ipairs(children) do
        local ok, matched = pcall(predicate, child)
        if ok and matched then
            output[#output + 1] = child
        end
        collectDescendants(child, predicate, output, depth + 1)
    end
    return output
end

local function rowButtons(row)
    local children = row and row:children()
    local buttons = {}
    if type(children) == "table" then
        for _, child in ipairs(children) do
            if elementAttribute(child, "AXRole") == "AXButton" then
                buttons[#buttons + 1] = child
            end
        end
    end
    return buttons
end

local function clearRowChildrenCache(row)
    if row then
        row._children = nil
    end
end

local function allRowButtons(row)
    local buttons = rowButtons(row)
    local ui = nil
    pcall(function() ui = row and row:UI() end)
    if ui then
        collectDescendants(ui, function(element)
            return elementRole(element) == "AXButton"
        end, buttons)
    end
    return buttons
end

local function rowButtonSummaries(row)
    local summaries = {}
    for _, candidate in ipairs(allRowButtons(row)) do
        local frame = elementFrame(candidate)
        if frame then
            summaries[#summaries + 1] = format(
                "%s frame=%.0f/%.0f/%.0f/%.0f",
                buttonSummary(candidate),
                tonumber(frame.x) or 0,
                tonumber(frame.y) or 0,
                tonumber(frame.w) or 0,
                tonumber(frame.h) or 0
            )
        else
            summaries[#summaries + 1] = buttonSummary(candidate)
        end
    end
    return table.concat(summaries, " | ")
end

local function setTransformValues(position, rotation, scaleAll, sample)
    local ok, err
    ok, err = setXYRow(position, sample.transformX or 0, sample.transformY or 0, "Transform Position")
    if not ok then return false, err end
    ok, err = setNumberRow(rotation, sample.transformRotation or 0, "Transform Rotation")
    if not ok then return false, err end
    ok, err = setNumberRow(scaleAll, sample.scale, "Transform Scale All")
    if not ok then return false, err end
    return true, nil
end

local function transformRowKeyframeState(row)
    local addButton = nil
    for _, button in ipairs(allRowButtons(row)) do
        local text = normalizedText(buttonSummary(button))
        if not text:find("parameter menu", 1, true) then
            local hasKeyframeText = text:find("keyframe", 1, true) ~= nil
            local isAnimationButton = text:find("animation button", 1, true) ~= nil
            if hasKeyframeText and (text:find("delete", 1, true) or text:find("remove", 1, true)) then
                return "already", button
            end
            if hasKeyframeText and (text:find("next", 1, true) or text:find("previous", 1, true)) then
                return "navigation", button
            end
            if (hasKeyframeText and text:find("add", 1, true)) or isAnimationButton then
                addButton = button
            end
        end
    end
    return addButton and "add" or nil, addButton
end

local function addTransformRowKeyframe(row, label, targetTimecode)
    row:show()
    local state, button = transformRowKeyframeState(row)
    if state == "already" then
        return true, label .. " already has a keyframe at " .. tostring(targetTimecode)
    end
    if state ~= "add" and state ~= "navigation" then
        return false, "Could not find " .. label .. " Add Keyframe button. Row buttons: " .. rowButtonSummaries(row)
    end

    local keyframeControl = nil
    local controlOK, controlErr = pcall(function()
        keyframeControl = row:keyframe()
    end)
    if not controlOK or not keyframeControl or type(keyframeControl.addKeyframe) ~= "function" then
        return false, label .. " did not expose CommandPost's official keyframe control: " .. tostring(controlErr) .. ". Row buttons: " .. rowButtonSummaries(row)
    end

    activateFinalCutPro()
    local apiOK, apiErr = pcall(function()
        keyframeControl:addKeyframe()
    end)
    if not apiOK then
        return false, "Could not add " .. label .. " keyframe via CommandPost official video inspector API: " .. tostring(apiErr) .. ". Row buttons: " .. rowButtonSummaries(row)
    end

    local deadline = timer.secondsSinceEpoch() + KEYFRAME_CONFIRM_TIMEOUT_SECONDS
    repeat
        clearRowChildrenCache(row)
        row:show()
        state = transformRowKeyframeState(row)
        if state == "already" then
            return true, label .. " Add Keyframe at " .. tostring(targetTimecode)
        end
        sleep(0.12)
    until timer.secondsSinceEpoch() >= deadline

    return true, "Called CommandPost official " .. label .. " keyframe API at " .. tostring(targetTimecode) .. "; Final Cut Pro kept reporting Add Keyframe, continuing AutoWB-style. Row buttons after API call: " .. rowButtonSummaries(row)
end

local function applyDynamicSample(transform, position, rotation, scaleAll, sample, targetTimecode)
    local ok, err

    local reasons = {}
    ok, err = addTransformRowKeyframe(position, "Transform Position", targetTimecode)
    if not ok then return false, err end
    reasons[#reasons + 1] = err

    ok, err = addTransformRowKeyframe(rotation, "Transform Rotation", targetTimecode)
    if not ok then return false, err end
    reasons[#reasons + 1] = err

    ok, err = addTransformRowKeyframe(scaleAll, "Transform Scale All", targetTimecode)
    if not ok then return false, err end
    reasons[#reasons + 1] = err

    ok, err = setTransformValues(position, rotation, scaleAll, sample)
    if not ok then
        return false, tostring(err) .. " after Transform row keyframes at " .. tostring(targetTimecode)
    end
    return true, table.concat(reasons, "; ")
end

local function parseFCPRange(value)
    local startValue, durationValue = tostring(value or ""):match("^%{%(([^%)]+)%),%(([^%)]+)%)%}$")
    if not startValue or not durationValue then
        return nil, nil
    end
    return startValue, durationValue
end

local function frameDurationFromVideoProps(videoProps)
    local frd = type(videoProps) == "table" and videoProps.FRD or nil
    local value = frd and tonumber(frd.value)
    local timescale = frd and tonumber(frd.timescale)
    if value and value > 0 and timescale and timescale > 0 then
        return tostring(math.floor(value + 0.5)) .. "/" .. tostring(math.floor(timescale + 0.5)) .. "s"
    end
    return nil
end

local function mediaForIdentifier(mediaItems, mediaIdentifier)
    if type(mediaItems) ~= "table" then return nil end
    if mediaIdentifier then
        for _, media in ipairs(mediaItems) do
            if media.mediaIdentifier == mediaIdentifier then
                return media
            end
        end
    end
    return mediaItems[1]
end

local function pathFromFCPBookmark(bookmark)
    if type(bookmark) ~= "string" or bookmark == "" then return nil end
    local decoded = base64.decode(bookmark:gsub("%s+", ""))
    if not decoded then return nil end
    local ok, path = pcall(function() return fs.pathFromBookmark(decoded) end)
    if ok and path and path ~= "" then return path end
    return nil
end

function restorePasteboard(contents)
    if type(contents) == "table" and next(contents) ~= nil then
        pcall(function() pasteboard.writeAllData(contents) end)
    else
        pcall(function() pasteboard.clearContents() end)
    end
end

function withTextPasteboard(value, fn)
    local previousPasteboard = nil
    pcall(function() previousPasteboard = pasteboard.readAllData() end)
    pcall(function() pasteboard.clearContents() end)
    pasteboard.setContents(tostring(value or ""))

    local ok, result, extra = pcall(fn)
    restorePasteboard(previousPasteboard)
    if not ok then
        return false, tostring(result)
    end
    return result, extra
end

local function selectedClipPasteboardSource(context)
    local label = context and context.label or "selected timeline clip"
    if not selectOnlyTimelineClip(context and context.clip) then
        return nil, "Could not select exactly one timeline clip before copying it."
    end

    local previousPasteboard = nil
    pcall(function() previousPasteboard = pasteboard.readAllData() end)
    pcall(function() pasteboard.clearContents() end)

    local copyOK = fcp:selectMenu({"Edit", "Copy"})
    if not copyOK then
        restorePasteboard(previousPasteboard)
        return nil, "Final Cut Pro Edit > Copy did not respond for the selected timeline clip."
    end

    local raw = nil
    local started = timer.secondsSinceEpoch()
    repeat
        raw = pasteboard.readDataForUTI(FCP_PASTEBOARD_UTI)
        if raw then break end
        sleep(0.1)
    until timer.secondsSinceEpoch() - started > 3

    restorePasteboard(previousPasteboard)
    previousPasteboard = nil
    if not raw then
        return nil, "Final Cut Pro did not put selected clip data on the pasteboard."
    end

    local pasteboardTable = plist.binaryToTable(raw)
    if type(pasteboardTable) ~= "table" then
        return nil, "Could not decode Final Cut Pro selected clip pasteboard plist."
    end
    local base64Data = pasteboardTable.ffpasteboardobject
    local archiveTable, archiveErr = plist.base64ToTable(base64Data)
    if not archiveTable then
        return nil, "Could not decode Final Cut Pro selected clip pasteboard data: " .. tostring(archiveErr)
    end
    local unarchived = archiver.unarchive(archiveTable)
    if type(unarchived) ~= "table" then
        return nil, "Could not unarchive Final Cut Pro selected clip pasteboard data."
    end

    local info = unarchived.root
        and unarchived.root.userInfo
        and unarchived.root.userInfo.copiedItemsPasteboardInfo
    local collection = info
        and type(info.nonAudioComponentSources) == "table"
        and info.nonAudioComponentSources[1]
        or nil
    if type(collection) ~= "table" then
        return nil, "Final Cut Pro pasteboard data did not include the selected video collection."
    end

    local sourceStart, duration = parseFCPRange(collection.clippedRange)
    if not sourceStart or not duration then
        return nil, "Could not read the selected clip range from Final Cut Pro pasteboard data."
    end

    local frameDuration = frameDurationFromVideoProps(collection.videoProps)
        or frameDurationFromVideoProps(unarchived.media and unarchived.media[1] and unarchived.media[1].videoProps)
    if not frameDuration then
        return nil, "Could not read the selected clip frame duration from Final Cut Pro pasteboard data."
    end

    local component = type(collection.containedItems) == "table" and collection.containedItems[1] or nil
    local mediaIdentifier = component and component.media and component.media.mediaIdentifier
    local media = mediaForIdentifier(unarchived.media, mediaIdentifier)
    local rep = media and media.originalMediaRep
    local bookmark = rep
        and rep.metadata
        and rep.metadata.FFMediaRep
        and rep.metadata.FFMediaRep.bookmark
        or nil
    local mediaPath = pathFromFCPBookmark(bookmark)
    if not mediaPath or not fileExists(mediaPath) then
        return nil, "Could not resolve the selected clip media file from Final Cut Pro pasteboard data."
    end

    local source = {
        mediaPath = mediaPath,
        frameDuration = frameDuration,
        sourceStart = sourceStart,
        duration = duration,
        clipName = collection.displayName or (media and media.displayName) or label,
    }
    return source, nil
end

local function runEstimator(source, intervalFrames, durationSeconds)
    if not fileExists(ESTIMATOR_SCRIPT) then
        return nil, "Estimator script was not found: " .. ESTIMATOR_SCRIPT
    end
    if not fileExists(PYTHON_BINARY) then
        return nil, "Python binary was not found: " .. PYTHON_BINARY
    end

    local command = table.concat({
        shellQuote(PYTHON_BINARY),
        shellQuote(ESTIMATOR_SCRIPT),
        "--media-path", shellQuote(source.mediaPath),
        "--frame-duration", shellQuote(source.frameDuration),
        "--source-start", shellQuote(source.sourceStart),
        "--duration", shellQuote(source.duration),
        "--clip-name", shellQuote(source.clipName or "selected timeline clip"),
        "--interval-frames", tostring(intervalFrames),
        "--duration-seconds", tostring(durationSeconds),
        "--max-samples", tostring(MAX_SAMPLES),
        "2>&1",
    }, " ")

    local output, ok = hs.execute(command, true)
    if not ok then
        local decoded = nil
        pcall(function() decoded = json.decode(output or "") end)
        if decoded and decoded.error then
            return nil, decoded.error
        end
        return nil, output or "Estimator failed."
    end

    local decoded = nil
    local decodeOK, decodeErr = pcall(function()
        decoded = json.decode(output or "")
    end)
    if not decodeOK or type(decoded) ~= "table" then
        return nil, "Estimator did not return valid JSON: " .. tostring(decodeErr or output)
    end
    if decoded.error then
        return nil, decoded.error
    end
    if type(decoded.samples) ~= "table" or #decoded.samples == 0 then
        return nil, "Estimator returned no samples."
    end
    return decoded, nil
end

local function startFxPlugCacheEstimator(source, durationSeconds, panSmoothSeconds, onSuccess, onFailure)
    if not fileExists(GPU_ESTIMATOR_SCRIPT) then
        return false, "GPU estimator script was not found: " .. GPU_ESTIMATOR_SCRIPT
    end
    if not fileExists(SWIFT_RUNNER) then
        return false, "Swift runner was not found: " .. SWIFT_RUNNER
    end

    local cacheDir = parentDirectory(FXPLUG_CACHE_PATH)
    local ok, mkdirErr = ensureDirectory(cacheDir)
    if not ok then
        return false, mkdirErr
    end

    local token = tostring(timer.secondsSinceEpoch()):gsub("[^%d]", "") .. "-" .. tostring(math.random(100000, 999999))
    local progressPath = "/tmp/stabilizer-fxplug-cache-progress-" .. token .. ".json"
    local progress = progressUIStart(FXPLUG_CACHE_ACTION_TITLE)
    progressUIUpdate(progress, 0.0, "Starting cache analysis")

    local function updateProgressFromFile()
        local progressText = readTextFile(progressPath)
        if progressText and progressText ~= "" then
            local payload = nil
            pcall(function() payload = json.decode(progressText) end)
            if type(payload) == "table" then
                progressUIUpdate(progress, payload.percent, payload.message)
            end
        end
    end

    local function cleanup()
        local state = activeCacheTasks[token]
        if state and state.progressTimer then
            state.progressTimer:stop()
        end
        progressUIStop(progress)
        removeFile(progressPath)
        activeCacheTasks[token] = nil
    end

    local args = {
        "swift",
        "-suppress-warnings",
        GPU_ESTIMATOR_SCRIPT,
        "--media-path", source.mediaPath,
        "--source-start", source.sourceStart,
        "--duration", source.duration,
        "--clip-name", source.clipName or "selected timeline clip",
        "--duration-seconds", tostring(durationSeconds),
        "--fxplug-cache-output", FXPLUG_CACHE_PATH,
        "--fxplug-cache-fps", DEFAULT_FXPLUG_CACHE_FPS,
        "--fxplug-cache-max-samples", "7200",
        "--pan-smooth-seconds", tostring(panSmoothSeconds),
        "--progress-file", progressPath,
    }

    local estimatorTask = task.new(SWIFT_RUNNER, function(exitCode, stdOut, stdErr)
        updateProgressFromFile()
        local decoded = nil
        pcall(function() decoded = json.decode(stdOut or "") end)
        local failed = exitCode ~= 0
        local message = nil
        if failed then
            message = decoded and decoded.error or ((stdErr and stdErr ~= "") and stdErr or stdOut or "FxPlug cache estimator failed.")
        elseif type(decoded) ~= "table" then
            message = "FxPlug cache estimator did not return valid JSON."
            failed = true
        elseif decoded.error then
            message = decoded.error
            failed = true
        elseif not fileExists(FXPLUG_CACHE_PATH) then
            message = "FxPlug cache file was not written: " .. FXPLUG_CACHE_PATH
            failed = true
        end

        progressUIUpdate(progress, 1.0, failed and "FxPlug cache failed" or "FxPlug cache complete")
        local state = activeCacheTasks[token] or {}
        state.doneTimer = timer.doAfter(0.45, function()
            cleanup()
            if failed then
                onFailure(message)
            else
                onSuccess(decoded)
            end
        end)
        activeCacheTasks[token] = state
    end, args)

    if not estimatorTask then
        progressUIStop(progress)
        removeFile(progressPath)
        return false, "Could not create FxPlug cache estimator task."
    end

    local progressTimer = timer.doEvery(0.15, updateProgressFromFile)
    activeCacheTasks[token] = {
        task = estimatorTask,
        progressTimer = progressTimer,
        progress = progress,
    }
    estimatorTask:start()
    return true, nil
end

local function intervalFramesPrompt()
    local value = dialog.displayChooseFromList(
        "Choose the stabilizer keyframe interval in frames: 1,2,3,4.",
        {"1", "2", "3", "4"},
        {DEFAULT_INTERVAL_FRAMES}
    )
    if value == false then return nil, "cancelled" end
    if type(value) == "table" then value = value[1] end
    if value == nil or value == "" then
        return nil, "The keyframe interval prompt did not return a selection; stopping before processing."
    end
    local frames = tonumber(value)
    if not frames or frames < 1 or frames > 4 then
        return nil, "Invalid keyframe interval selection: " .. tostring(value)
    end
    return math.floor(frames)
end

local function panSmoothSecondsPrompt()
    local button, answer = hs.dialog.textPrompt(
        "FxPlug prerender smoothing",
        "Enter the smoothing window in seconds for the cache file.",
        DEFAULT_PAN_SMOOTH_SECONDS,
        "Analyze",
        "Cancel"
    )
    if button == "Cancel" then return nil, "cancelled" end
    if button ~= "Analyze" then
        return nil, "The smoothing prompt did not return Analyze; stopping before processing."
    end
    local normalized = (trim(answer):gsub(",", "."))
    local value = tonumber(normalized)
    if not value or value <= 0 then
        return nil, "Invalid smoothing window: " .. tostring(answer)
    end
    return value, nil
end

local function selectedClipContext(frameRate)
    local videoClips, selected = selectedTimelineVideoClips()
    if #videoClips < 1 then
        local selectedLabel = selected and selected[1] and clipLabel(selected[1]) or "none"
        return nil, "Select exactly one timeline video clip before running " .. ACTION_TITLE .. ". Current selection: " .. selectedLabel
    end
    if #videoClips > 1 then
        log.wf(
            "%s: selectedClipsUI(false) returned %d video clip candidates after filtering; using %s.",
            ACTION_TITLE,
            #videoClips,
            clipLabel(chooseBestVideoClip(videoClips))
        )
    end

    local clip = chooseBestVideoClip(videoClips)
    if not clip then
        return nil, "Select exactly one timeline video clip before running " .. ACTION_TITLE .. "."
    end

    local startFlicks, endFlicks, spanSource = clipTimecodeSpan(clip, frameRate)
    if not startFlicks or not endFlicks then
        startFlicks, endFlicks, spanSource = selectedClipTimelineSpanFromSelection(clip, frameRate)
    end
    if not startFlicks or not endFlicks then
        return nil, "Could not read the selected clip's timeline start/end timecode: " .. tostring(spanSource)
    end
    local durationSeconds = (endFlicks - startFlicks):toSeconds()
    if durationSeconds <= 0 then
        return nil, "Selected clip duration was not valid."
    end
    return {
        clip = clip,
        label = clipLabel(clip),
        startFlicks = startFlicks,
        endFlicks = endFlicks,
        durationSeconds = durationSeconds,
    }, nil
end

local function applyDynamicStrengthScale()
    local startedAt = timer.secondsSinceEpoch()
    local stage = "start"
    local function fail(message, fields)
        logStage("failed", tostring(message), fields or {
            { "stage", stage },
            { "elapsed", format("%.1fs", timer.secondsSinceEpoch() - startedAt) },
        })
        showFailure(ACTION_TITLE, tostring(message))
        displayError(ACTION_TITLE, tostring(message))
        return false
    end

    stage = "interval prompt"
    local intervalFrames, intervalErr = intervalFramesPrompt()
    if not intervalFrames then
        if intervalErr and intervalErr ~= "cancelled" then
            return fail(intervalErr)
        end
        log.i(ACTION_TITLE .. ": cancelled before interval selection.")
        return false
    end

    stage = "selected clip"
    local seedFrameRate = 30
    local context, contextErr = selectedClipContext(seedFrameRate)
    if not context then
        return fail(contextErr)
    end

    stage = "pasteboard source"
    local source, sourceErr = selectedClipPasteboardSource(context)
    if not source then
        return fail(sourceErr)
    end

    stage = "estimator"
    local estimate, estimateErr = runEstimator(source, intervalFrames, context.durationSeconds)
    if not estimate then
        return fail(estimateErr)
    end
    local sampleCount = #(estimate.samples or {})

    local frameRate = tonumber(estimate.frameRate) or seedFrameRate

    local originalPlayhead = playheadFlicks(frameRate)
    playheadMovePreferredMethod = nil

    stage = "prepare inspector"
    activateFinalCutPro()
    local video = fcp.inspector.video:show()
    local stabilization = video:stabilization()
    local transform = video:transform()
    local position = transform:position()
    local rotation = transform:rotation()
    local scaleAll = transform:scaleAll()
    local ok, err

    stabilization:show()
    ok, err = setCheckBox(stabilization.enabled, false, "Stabilization")
    if not ok then
        return fail(err)
    end

    transform:show()
    ok, err = setCheckBox(transform.enabled, true, "Transform")
    if not ok then
        return fail(err)
    end
    position:show()
    rotation:show()
    scaleAll:show()

    local applied = 0
    for index, sample in ipairs(estimate.samples) do
        local seconds = tonumber(sample.timelineSeconds) or 0
        if seconds <= context.durationSeconds + 0.05 then
            activateFinalCutPro()
            if index == 1 and seconds <= 0 then
                seconds = 1 / frameRate
            end
            stage = "sample " .. tostring(index) .. " move playhead"
            local target = offsetFrom(context.startFlicks, seconds)
            local moved, targetTimecode, moveReason = movePlayheadToFlicks(target, frameRate)
            if not moved then
                return fail("Could not move playhead to " .. tostring(targetTimecode) .. ": " .. tostring(moveReason), {
                    { "stage", stage },
                    { "sample", tostring(index) .. "/" .. tostring(sampleCount) },
                    { "timelineSeconds", tostring(seconds) },
                    { "elapsed", format("%.1fs", timer.secondsSinceEpoch() - startedAt) },
                })
            end
            stage = "sample " .. tostring(index) .. " write transform"
            ok, err = applyDynamicSample(transform, position, rotation, scaleAll, sample, targetTimecode)
            if not ok then
                return fail(err, {
                    { "stage", stage },
                    { "sample", tostring(index) .. "/" .. tostring(sampleCount) },
                    { "targetTimecode", tostring(targetTimecode) },
                    { "timelineSeconds", tostring(seconds) },
                    { "elapsed", format("%.1fs", timer.secondsSinceEpoch() - startedAt) },
                })
            end
            applied = applied + 1
            sleep(0.08)
        end
    end

    stage = "restore playhead"
    if originalPlayhead then
        movePlayheadToFlicks(originalPlayhead, frameRate)
    end

    local message = format("Applied %d Transform stabilization keyframe point(s) to %s.", applied, context.label)
    log.i(ACTION_TITLE .. ": " .. message)
    if hs and hs.notify then
        hs.notify.new({ title = ACTION_TITLE, informativeText = message }):send()
    else
        displayMessage(ACTION_TITLE, message)
    end
    return true
end

local function analyzeFxPlugCache()
    local startedAt = timer.secondsSinceEpoch()
    local stage = "start"
    local function fail(message, fields)
        logStage("failed", tostring(message), fields or {
            { "stage", stage },
            { "elapsed", format("%.1fs", timer.secondsSinceEpoch() - startedAt) },
        })
        showFailure(FXPLUG_CACHE_ACTION_TITLE, tostring(message))
        displayError(FXPLUG_CACHE_ACTION_TITLE, tostring(message))
        return false
    end

    stage = "smoothing prompt"
    local panSmoothSeconds, promptErr = panSmoothSecondsPrompt()
    if not panSmoothSeconds then
        if promptErr and promptErr ~= "cancelled" then
            return fail(promptErr)
        end
        log.i(FXPLUG_CACHE_ACTION_TITLE .. ": cancelled before smoothing selection.")
        return false
    end

    stage = "selected clip"
    local seedFrameRate = 30
    local context, contextErr = selectedClipContext(seedFrameRate)
    if not context then
        return fail(contextErr)
    end

    stage = "pasteboard source"
    local source, sourceErr = selectedClipPasteboardSource(context)
    if not source then
        return fail(sourceErr)
    end

    stage = "cache estimator"
    local started, startErr = startFxPlugCacheEstimator(
        source,
        context.durationSeconds,
        panSmoothSeconds,
        function(result)
            local message = format(
                "Wrote FxPlug stabilization cache for %s: %d sample(s), %.2fs smoothing.\n%s",
                context.label,
                tonumber(result.sampleCount) or 0,
                tonumber(result.panSmoothSeconds) or panSmoothSeconds,
                FXPLUG_CACHE_PATH
            )
            log.i(FXPLUG_CACHE_ACTION_TITLE .. ": " .. message:gsub("\n", " "))
            displayMessage(FXPLUG_CACHE_ACTION_TITLE, message)
        end,
        function(message)
            fail(message)
        end
    )
    if not started then
        return fail(startErr)
    end
    return true
end

local function runWithErrorBoundary(title, fn)
    local ok, result = xpcall(fn, debug.traceback)
    if not ok then
        logStage("exception", "Unhandled Stabilizer error.", {
            { "error", tostring(result) },
        })
        showFailure(title, tostring(result))
        displayError(title, result)
        return false
    end
    return result
end

mod.dependencies = {
    ["core.action.manager"] = "actionmanager",
    ["finalcutpro.commands"] = "fcpxCmds",
}

function mod.applyDynamicStrengthScale()
    return applyDynamicStrengthScale()
end

function mod.analyzeFxPlugCache()
    return analyzeFxPlugCache()
end

function mod.init(deps)
    if not fcp:isSupported() then return mod end

    deps.fcpxCmds
        :add(ACTION_ID)
        :groupedBy("video")
        :whenActivated(function()
            runWithErrorBoundary(ACTION_TITLE, mod.applyDynamicStrengthScale)
        end)
        :titled(ACTION_TITLE)

    deps.fcpxCmds
        :add(FXPLUG_CACHE_ACTION_ID)
        :groupedBy("video")
        :whenActivated(function()
            runWithErrorBoundary(FXPLUG_CACHE_ACTION_TITLE, mod.analyzeFxPlugCache)
        end)
        :titled(FXPLUG_CACHE_ACTION_TITLE)

    deps.actionmanager.addHandler("fcpx_stabilizer_dynamic_strength_scale", "fcpx")
        :onChoices(function(choices)
            choices:add(ACTION_TITLE)
                :subText("Analyze gimbal jitter and uneven pan rotation, then keyframe Transform Position, Rotation, and Scale")
                :params({ id = ACTION_ID })
                :id("stabilizer:" .. ACTION_ID)
        end)
        :onExecute(function()
            runWithErrorBoundary(ACTION_TITLE, mod.applyDynamicStrengthScale)
        end)
        :onActionId(function(action)
            return "stabilizer:" .. ((action and action.id) or ACTION_ID)
        end)

    deps.actionmanager.addHandler("fcpx_stabilizer_fxplug_cache", "fcpx")
        :onChoices(function(choices)
            choices:add(FXPLUG_CACHE_ACTION_TITLE)
                :subText("Precompute selected clip stabilization into the cache file read by Stabilizer Transform")
                :params({ id = FXPLUG_CACHE_ACTION_ID })
                :id("stabilizer:" .. FXPLUG_CACHE_ACTION_ID)
        end)
        :onExecute(function()
            runWithErrorBoundary(FXPLUG_CACHE_ACTION_TITLE, mod.analyzeFxPlugCache)
        end)
        :onActionId(function(action)
            return "stabilizer:" .. ((action and action.id) or FXPLUG_CACHE_ACTION_ID)
        end)

    return mod
end

return mod
