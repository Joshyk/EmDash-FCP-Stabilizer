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
local timer = require "hs.timer"
local eventtap = require "hs.eventtap"

local format = string.format
local usleep = timer.usleep

local mod = {}

local ACTION_TITLE = "Stabilizer: Dynamic Strength Scale"
local ACTION_ID = "stabilizerDynamicStrengthScale"
local REPO_DIRECTORY = "/Users/justadev/Developer/EDT/Command-Post-Em_Dash/Stabilizer"
local ESTIMATOR_SCRIPT = REPO_DIRECTORY .. "/scripts/estimate_stabilization_scale.py"
local PYTHON_BINARY = os.getenv("STABILIZER_PYTHON") or "/Library/Frameworks/Python.framework/Versions/3.10/bin/python3"
local DEFAULT_INTERVAL_FRAMES = "10"
local MAX_SAMPLES = 240
local CONTROL_READY_TIMEOUT_SECONDS = 12
local PLAYHEAD_ENTRY_TIMEOUT_SECONDS = 1.0
local TIMECODE_PROPERTY_MOVE_TIMEOUT_SECONDS = 0.8

local playheadMovePreferredMethod = nil

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

local function pathIsDirectory(path)
    if not path or path == "" then return false end
    if hs and hs.fs and hs.fs.attributes then
        local ok, attributes = pcall(function() return hs.fs.attributes(path) end)
        return ok and attributes and attributes.mode == "directory"
    end
    local ok = os.execute("/bin/test -d " .. shellQuote(path))
    return ok == true or ok == 0
end

local function displayError(title, detail)
    dialog.displayErrorMessage(tostring(title or "Stabilizer") .. "\n\n" .. tostring(detail or ""))
end

local function displayMessage(title, detail)
    dialog.displayAlertMessage(tostring(title or "Stabilizer"), tostring(detail or ""))
end

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
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

local function parseTimecodePair(startTC, endTC, frameRate)
    if not startTC or not endTC then return nil, nil end
    local okStart, startFlicks = pcall(function() return flicks.parse(startTC, frameRate) end)
    local okEnd, endFlicks = pcall(function() return flicks.parse(endTC, frameRate) end)
    if okStart and okEnd then
        return startFlicks, endFlicks
    end
    return nil, nil
end

local function parseTimecodeValue(value, frameRate)
    if not value or value == "" then return nil end
    local ok, parsed = pcall(function() return flicks.parse(tostring(value), frameRate) end)
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
    local ok, parsed = pcall(function() return flicks.parse(timecode, frameRate) end)
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

    local selected = selectedClipsUI(false)
    return #selected == 1
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

local function movePlayheadWithTimecodeProperty(targetFlicks, frameRate)
    local targetTimecode = targetFlicks:toTimecode(frameRate, ":")
    local ok, err = pcall(function()
        fcp.timeline.playhead:timecode(targetTimecode)
    end)
    if not ok then
        return false, targetTimecode, "absolute playhead timecode property failed: " .. tostring(err)
    end

    local matched, current = waitForPlayhead(targetFlicks, frameRate, TIMECODE_PROPERTY_MOVE_TIMEOUT_SECONDS)
    if matched then
        return true, targetTimecode, "absolute playhead timecode property", current
    end
    return false, targetTimecode, "absolute playhead timecode property did not reach target", current
end

local function typeCleanTimecode(timecode, app)
    local cleanedTimecode = tostring(timecode):gsub(";", ""):gsub(":", "")
    for character in cleanedTimecode:gmatch(".") do
        eventtap.keyStroke({}, character, 0, app)
        sleep(0.01)
    end
end

local function movePlayheadWithPlayheadPositionCommand(targetFlicks, frameRate)
    local targetTimecode = targetFlicks:toTimecode(frameRate, ":")
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

    sleep(0.25)
    typeCleanTimecode(targetTimecode, app)
    eventtap.keyStroke({}, "return", 0, app)

    local matched, current = waitForPlayhead(targetFlicks, frameRate, PLAYHEAD_ENTRY_TIMEOUT_SECONDS)
    if matched then
        return true, targetTimecode, "Move Playhead Position", current
    end
    return false, targetTimecode, "Move Playhead Position did not reach target", current
end

local function movePlayheadToFlicks(targetFlicks, frameRate)
    local targetTimecode = targetFlicks:toTimecode(frameRate, ":")
    local current = playheadFlicks(frameRate)
    if flicksCloseEnough(current, targetFlicks) then
        return true, targetTimecode, "already at target", current
    end

    if playheadMovePreferredMethod == "property" then
        local moved, timecode, reason, currentAfter = movePlayheadWithTimecodeProperty(targetFlicks, frameRate)
        if moved then return true, timecode, reason, currentAfter end
        playheadMovePreferredMethod = nil
    elseif playheadMovePreferredMethod == "command" then
        local moved, timecode, reason, currentAfter = movePlayheadWithPlayheadPositionCommand(targetFlicks, frameRate)
        if moved then return true, timecode, reason, currentAfter end
        playheadMovePreferredMethod = nil
    end

    local moved, timecode, reason, currentAfter = movePlayheadWithTimecodeProperty(targetFlicks, frameRate)
    if moved then
        playheadMovePreferredMethod = "property"
        return true, timecode, reason, currentAfter
    end
    log.df("%s for %s; trying playhead entry.", tostring(reason), tostring(timecode))

    moved, timecode, reason, currentAfter = movePlayheadWithPlayheadPositionCommand(targetFlicks, frameRate)
    if moved then
        playheadMovePreferredMethod = "command"
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

local function addKeyframe(row, label)
    local ok, err = pcall(function()
        row:show():keyframe():addKeyframe()
    end)
    if not ok then
        return false, "Could not add " .. label .. " keyframe: " .. tostring(err)
    end
    return true, nil
end

local function resolveFCPXMLPath(path)
    if not path or path == "" then return nil, "No FCPXML file was selected." end
    local normalizedPath = tostring(path):gsub("/+$", "")
    if normalizedPath:match("%.fcpxmld$") then
        local packageInfoPath = normalizedPath .. "/Info.fcpxml"
        if fileExists(packageInfoPath) then return packageInfoPath end
        return nil, "The selected FCPXML package did not contain Info.fcpxml: " .. normalizedPath
    elseif pathIsDirectory(normalizedPath) then
        return nil, "The selected FCPXML path is a directory, not an .fcpxml file or .fcpxmld package: " .. normalizedPath
    elseif fileExists(normalizedPath) then
        return normalizedPath
    end
    return nil, "FCPXML file was not found: " .. normalizedPath
end

local function chooseFCPXML()
    local path = dialog.displayChooseFile("Choose the FCPXML exported from Final Cut Pro.", {"fcpxmld", "fcpxml", "xml"}, os.getenv("HOME") .. "/Documents")
    local resolvedPath, err = resolveFCPXMLPath(path)
    if not resolvedPath then
        return nil, err
    end
    return resolvedPath, nil
end

local function runEstimator(fcpxmlPath, intervalFrames, durationSeconds)
    if not fileExists(ESTIMATOR_SCRIPT) then
        return nil, "Estimator script was not found: " .. ESTIMATOR_SCRIPT
    end
    if not fileExists(PYTHON_BINARY) then
        return nil, "Python binary was not found: " .. PYTHON_BINARY
    end

    local command = table.concat({
        shellQuote(PYTHON_BINARY),
        shellQuote(ESTIMATOR_SCRIPT),
        "--fcpxml", shellQuote(fcpxmlPath),
        "--interval-frames", tostring(intervalFrames),
        "--duration-seconds", tostring(durationSeconds),
        "--max-samples", tostring(MAX_SAMPLES),
        "2>&1",
    }, " ")

    log.i("Running stabilizer estimator: " .. command)
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

local function intervalFramesPrompt()
    local value = dialog.displayChooseFromList(
        "Choose the stabilizer keyframe interval in frames.",
        {"5", "10", "15", "30", "60"},
        {DEFAULT_INTERVAL_FRAMES}
    )
    if value == false then return nil end
    if type(value) == "table" then value = value[1] end
    local frames = tonumber(value or DEFAULT_INTERVAL_FRAMES) or tonumber(DEFAULT_INTERVAL_FRAMES)
    if frames < 1 then frames = tonumber(DEFAULT_INTERVAL_FRAMES) end
    return math.floor(frames)
end

local function selectedClipContext(frameRate)
    local selected = selectedClipsUI()
    if #selected ~= 1 then
        return nil, "Select exactly one timeline video clip before running " .. ACTION_TITLE .. "."
    end

    local startFlicks, endFlicks, spanSource = clipTimecodeSpan(selected[1], frameRate)
    if not startFlicks or not endFlicks then
        startFlicks, endFlicks, spanSource = selectedClipTimelineSpanFromSelection(selected[1], frameRate)
    end
    if not startFlicks or not endFlicks then
        return nil, "Could not read the selected clip's timeline start/end timecode: " .. tostring(spanSource)
    end
    local durationSeconds = (endFlicks - startFlicks):toSeconds()
    if durationSeconds <= 0 then
        return nil, "Selected clip duration was not valid."
    end
    log.df("Selected clip timeline span resolved via %s.", tostring(spanSource))

    return {
        clip = selected[1],
        label = clipLabel(selected[1]),
        startFlicks = startFlicks,
        endFlicks = endFlicks,
        durationSeconds = durationSeconds,
    }, nil
end

local function applyDynamicSample(video, stabilization, scaleAll, sample)
    local ok, err
    local strength = tonumber(sample.strength) or 0

    ok, err = setNumberRow(stabilization:translationSmooth(), sample.translationSmooth, "Translation Smooth")
    if not ok then return false, err end
    ok, err = addKeyframe(stabilization:translationSmooth(), "Translation Smooth")
    if not ok then return false, err end

    ok, err = setNumberRow(stabilization:rotationSmooth(), sample.rotationSmooth, "Rotation Smooth")
    if not ok then return false, err end
    ok, err = addKeyframe(stabilization:rotationSmooth(), "Rotation Smooth")
    if not ok then return false, err end

    ok, err = setNumberRow(stabilization:scaleSmooth(), sample.scaleSmooth, "Scale Smooth")
    if not ok then return false, err end
    ok, err = addKeyframe(stabilization:scaleSmooth(), "Scale Smooth")
    if not ok then return false, err end

    ok, err = setNumberRow(scaleAll, sample.scale, "Transform Scale All")
    if not ok then return false, err end
    ok, err = addKeyframe(scaleAll, "Transform Scale All")
    if not ok then return false, err end

    log.df(
        "Dynamic sample seconds=%.3f strength=%.3f gimbal=%.3f panRotation=%.3f scale=%.3f translation=%.3f rotation=%.3f scaleSmooth=%.3f dx=%.3f dy=%.3f residual=%.4f",
        tonumber(sample.timelineSeconds) or 0,
        strength,
        tonumber(sample.gimbalStrength) or 0,
        tonumber(sample.panRotationStrength) or 0,
        tonumber(sample.scale) or 100,
        tonumber(sample.translationSmooth) or 0,
        tonumber(sample.rotationSmooth) or 0,
        tonumber(sample.scaleSmooth) or 0,
        tonumber(sample.globalDx) or 0,
        tonumber(sample.globalDy) or 0,
        tonumber(sample.residualMotion) or 0
    )
    return true, nil
end

local function applyDynamicStrengthScale()
    local intervalFrames = intervalFramesPrompt()
    if not intervalFrames then
        log.i(ACTION_TITLE .. ": cancelled before interval selection.")
        return false
    end
    local fcpxmlPath, fcpxmlErr = chooseFCPXML()
    if not fcpxmlPath then
        displayError(ACTION_TITLE, fcpxmlErr)
        return false
    end

    local seedFrameRate = 30
    local context, contextErr = selectedClipContext(seedFrameRate)
    if not context then
        displayError(ACTION_TITLE, contextErr)
        return false
    end

    local estimate, estimateErr = runEstimator(fcpxmlPath, intervalFrames, context.durationSeconds)
    if not estimate then
        displayError(ACTION_TITLE, estimateErr)
        return false
    end

    local frameRate = tonumber(estimate.frameRate) or seedFrameRate
    context, contextErr = selectedClipContext(frameRate)
    if not context then
        displayError(ACTION_TITLE, contextErr)
        return false
    end

    local originalPlayhead = playheadFlicks(frameRate)
    playheadMovePreferredMethod = nil

    local video = fcp.inspector.video:show()
    local stabilization = video:stabilization()
    local transform = video:transform()
    local scaleAll = transform:scaleAll()
    local ok, err

    stabilization:show()
    ok, err = setCheckBox(stabilization.enabled, true, "Stabilization")
    if not ok then
        displayError(ACTION_TITLE, err)
        return false
    end

    ok, err = setPopup(stabilization:method(), "FFStabilizationUseSmoothCam", "Stabilization Method")
    if not ok then
        displayError(ACTION_TITLE, err)
        return false
    end

    transform:show()
    scaleAll:show()

    local applied = 0
    for _, sample in ipairs(estimate.samples) do
        local seconds = tonumber(sample.timelineSeconds) or 0
        if seconds <= context.durationSeconds + 0.05 then
            local target = offsetFrom(context.startFlicks, seconds)
            local moved, targetTimecode, moveReason = movePlayheadToFlicks(target, frameRate)
            if not moved then
                displayError(ACTION_TITLE, "Could not move playhead to " .. tostring(targetTimecode) .. ": " .. tostring(moveReason))
                return false
            end

            ok, err = applyDynamicSample(video, stabilization, scaleAll, sample)
            if not ok then
                displayError(ACTION_TITLE, err)
                return false
            end
            applied = applied + 1
            sleep(0.08)
        end
    end

    if originalPlayhead then
        movePlayheadToFlicks(originalPlayhead, frameRate)
    end

    local message = format("Applied %d dynamic strength/scale keyframe point(s) to %s.", applied, context.label)
    log.i(ACTION_TITLE .. ": " .. message)
    if hs and hs.notify then
        hs.notify.new({ title = ACTION_TITLE, informativeText = message }):send()
    else
        displayMessage(ACTION_TITLE, message)
    end
    return true
end

local function runWithErrorBoundary(title, fn)
    local ok, result = xpcall(fn, debug.traceback)
    if not ok then
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

function mod.init(deps)
    if not fcp:isSupported() then return mod end

    deps.fcpxCmds
        :add(ACTION_ID)
        :groupedBy("video")
        :whenActivated(function()
            runWithErrorBoundary(ACTION_TITLE, mod.applyDynamicStrengthScale)
        end)
        :titled(ACTION_TITLE)

    deps.actionmanager.addHandler("fcpx_stabilizer_dynamic_strength_scale", "fcpx")
        :onChoices(function(choices)
            choices:add(ACTION_TITLE)
                :subText("Analyze gimbal jitter and uneven pan rotation, then keyframe stabilization plus Transform Scale")
                :params({ id = ACTION_ID })
                :id("stabilizer:" .. ACTION_ID)
        end)
        :onExecute(function()
            runWithErrorBoundary(ACTION_TITLE, mod.applyDynamicStrengthScale)
        end)
        :onActionId(function(action)
            return "stabilizer:" .. ((action and action.id) or ACTION_ID)
        end)

    return mod
end

return mod
