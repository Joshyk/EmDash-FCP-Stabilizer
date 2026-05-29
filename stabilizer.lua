--- === plugins.finalcutpro.stabilizer.workflow ===
---
--- Applies Final Cut Pro stabilization presets to selected timeline clips.

local require = require
local hs = _G.hs

local log = require "hs.logger".new "stabPreset"
local dialog = require "cp.dialog"
local fcp = require "cp.apple.finalcutpro"
local timer = require "hs.timer"

local usleep = timer.usleep

local mod = {}

local ACTION_SHAKE_TITLE = "Stabilizer: Walking Gimbal Shake"
local ACTION_SHAKE_ID = "stabilizerWalkingGimbalShake"
local ACTION_PAN_TITLE = "Stabilizer: Walking Gimbal Pan Smooth"
local ACTION_PAN_ID = "stabilizerWalkingGimbalPanSmooth"
local CONTROL_READY_TIMEOUT_SECONDS = 12

local PRESETS = {
    shake = {
        title = ACTION_SHAKE_TITLE,
        method = "FFStabilizationUseSmoothCam",
        rollingShutterAmount = "FFRollingShutterAmountMedium",
        translationSmooth = 2.4,
        rotationSmooth = 1.1,
        scaleSmooth = 0.8,
    },
    pan = {
        title = ACTION_PAN_TITLE,
        method = "FFStabilizationUseInertiaCam",
        rollingShutterAmount = "FFRollingShutterAmountLow",
        smoothing = 1.1,
        tripodMode = false,
    },
}

local function sleep(seconds)
    usleep((seconds or 0.1) * 1000000)
end

local function displayError(title, detail)
    dialog.displayErrorMessage(tostring(title or "Stabilizer") .. "\n\n" .. tostring(detail or ""))
end

local function displayMessage(title, detail)
    dialog.displayAlertMessage(tostring(title or "Stabilizer"), tostring(detail or ""))
end

local function selectedTimelineClipCount()
    fcp.timeline:show()
    fcp.timeline.contents:focus()
    local ok, selected = pcall(function()
        return fcp.timeline.contents:selectedClipsUI(false)
    end)
    if not ok or type(selected) ~= "table" then
        return nil, "Could not read selected timeline clips from Final Cut Pro."
    end
    return #selected, nil
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

local function ensureSelectedClips()
    local count, err = selectedTimelineClipCount()
    if err then return nil, err end
    if count < 1 then
        return nil, "Select one or more timeline clips before running Stabilizer."
    end
    return count, nil
end

local function applyPreset(preset)
    local selectedCount, selectedErr = ensureSelectedClips()
    if selectedErr then
        displayError(preset.title, selectedErr)
        return false
    end

    local video = fcp.inspector.video:show()
    local stabilization = video:stabilization()
    local rollingShutter = video:rollingShutter()
    local ok, err

    stabilization:show()
    ok, err = setCheckBox(stabilization.enabled, true, "Stabilization")
    if not ok then
        displayError(preset.title, err)
        return false
    end

    ok, err = setPopup(stabilization:method(), preset.method, "Stabilization Method")
    if not ok then
        displayError(preset.title, err)
        return false
    end

    if preset.tripodMode ~= nil then
        ok, err = setCheckBox(stabilization:tripodMode():show().value, preset.tripodMode, "Tripod Mode")
        if not ok then
            displayError(preset.title, err)
            return false
        end
    end

    if preset.smoothing then
        ok, err = setNumberRow(stabilization:smoothing(), preset.smoothing, "Smoothing")
        if not ok then
            displayError(preset.title, err)
            return false
        end
    end

    if preset.translationSmooth then
        ok, err = setNumberRow(stabilization:translationSmooth(), preset.translationSmooth, "Translation Smooth")
        if not ok then
            displayError(preset.title, err)
            return false
        end
    end

    if preset.rotationSmooth then
        ok, err = setNumberRow(stabilization:rotationSmooth(), preset.rotationSmooth, "Rotation Smooth")
        if not ok then
            displayError(preset.title, err)
            return false
        end
    end

    if preset.scaleSmooth then
        ok, err = setNumberRow(stabilization:scaleSmooth(), preset.scaleSmooth, "Scale Smooth")
        if not ok then
            displayError(preset.title, err)
            return false
        end
    end

    rollingShutter:show()
    ok, err = setCheckBox(rollingShutter.enabled, true, "Rolling Shutter")
    if not ok then
        displayError(preset.title, err)
        return false
    end

    ok, err = setPopup(rollingShutter:amount(), preset.rollingShutterAmount, "Rolling Shutter Amount")
    if not ok then
        displayError(preset.title, err)
        return false
    end

    local message = string.format("Applied to %d selected clip(s).", selectedCount)
    log.i(preset.title .. ": " .. message)
    if hs and hs.notify then
        hs.notify.new({ title = preset.title, informativeText = message }):send()
    else
        displayMessage(preset.title, message)
    end
    return true
end

function mod.applyWalkingGimbalShake()
    return applyPreset(PRESETS.shake)
end

function mod.applyWalkingGimbalPanSmooth()
    return applyPreset(PRESETS.pan)
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

function mod.init(deps)
    if not fcp:isSupported() then return mod end

    deps.fcpxCmds
        :add(ACTION_SHAKE_ID)
        :groupedBy("video")
        :whenActivated(function()
            runWithErrorBoundary(ACTION_SHAKE_TITLE, mod.applyWalkingGimbalShake)
        end)
        :titled(ACTION_SHAKE_TITLE)

    deps.fcpxCmds
        :add(ACTION_PAN_ID)
        :groupedBy("video")
        :whenActivated(function()
            runWithErrorBoundary(ACTION_PAN_TITLE, mod.applyWalkingGimbalPanSmooth)
        end)
        :titled(ACTION_PAN_TITLE)

    deps.actionmanager.addHandler("fcpx_stabilizer_walking_gimbal_shake", "fcpx")
        :onChoices(function(choices)
            choices:add(ACTION_SHAKE_TITLE)
                :subText("Final Cut Pro - SmoothCam preset for walking gimbal shake")
                :params({ id = ACTION_SHAKE_ID })
                :id("stabilizer:" .. ACTION_SHAKE_ID)
        end)
        :onExecute(function()
            runWithErrorBoundary(ACTION_SHAKE_TITLE, mod.applyWalkingGimbalShake)
        end)
        :onActionId(function(action)
            return "stabilizer:" .. ((action and action.id) or ACTION_SHAKE_ID)
        end)

    deps.actionmanager.addHandler("fcpx_stabilizer_walking_gimbal_pan_smooth", "fcpx")
        :onChoices(function(choices)
            choices:add(ACTION_PAN_TITLE)
                :subText("Final Cut Pro - InertiaCam preset for smoother walking gimbal pans")
                :params({ id = ACTION_PAN_ID })
                :id("stabilizer:" .. ACTION_PAN_ID)
        end)
        :onExecute(function()
            runWithErrorBoundary(ACTION_PAN_TITLE, mod.applyWalkingGimbalPanSmooth)
        end)
        :onActionId(function(action)
            return "stabilizer:" .. ((action and action.id) or ACTION_PAN_ID)
        end)

    return mod
end

return mod
