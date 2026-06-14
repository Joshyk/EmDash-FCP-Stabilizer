#!/usr/bin/osascript
use AppleScript version "2.4"
use scripting additions

property fcpProcessName : "Final Cut Pro"
property maxSearchDepth : 14
property allowedSampleSizes : {"100%", "75%", "50%", "25%", "10%"}

on run argv
	if (count of argv) is 0 then my failWithUsage()

	set commandName to item 1 of argv
	if commandName is "set-sample-size" then
		if (count of argv) < 2 then my fail("Usage: set-sample-size SAMPLE_PERCENT")
		my setSampleSize(item 2 of argv)
	else if commandName is "start-analysis-at-sample" then
		if (count of argv) < 2 then my fail("Usage: start-analysis-at-sample SAMPLE_PERCENT")
		my setSampleSize(item 2 of argv)
		my startHostAnalysis()
	else if commandName is "queue-open-timeline-clips" then
		if (count of argv) < 2 then my fail("Usage: queue-open-timeline-clips SAMPLE_PERCENT [MAX_CLIPS]")
		set sampleSizeText to item 2 of argv
		set maxClips to 200
		if (count of argv) > 2 then set maxClips to my parsePositiveInteger(item 3 of argv, "MAX_CLIPS")
		my queueOpenTimelineClips(sampleSizeText, maxClips)
	else if commandName is "queue-current-event-compounds" then
		if (count of argv) < 2 then my fail("Usage: queue-current-event-compounds SAMPLE_PERCENT [MAX_ITEMS] [MAX_CLIPS_PER_ITEM]")
		set sampleSizeText to item 2 of argv
		set maxItems to 0
		set maxClipsPerItem to 200
		if (count of argv) > 2 then set maxItems to my parseNonNegativeInteger(item 3 of argv, "MAX_ITEMS")
		if (count of argv) > 3 then set maxClipsPerItem to my parsePositiveInteger(item 4 of argv, "MAX_CLIPS_PER_ITEM")
		my queueCurrentEventCompounds(sampleSizeText, maxItems, maxClipsPerItem)
	else
		my failWithUsage()
	end if
end run

on failWithUsage()
	my fail("Usage: osascript fcp_batch_stabilizer.applescript set-sample-size SAMPLE_PERCENT|start-analysis-at-sample SAMPLE_PERCENT|queue-open-timeline-clips SAMPLE_PERCENT [MAX_CLIPS]|queue-current-event-compounds SAMPLE_PERCENT [MAX_ITEMS] [MAX_CLIPS_PER_ITEM]")
end failWithUsage

on queueCurrentEventCompounds(sampleSizeText, maxItems, maxClipsPerItem)
	set normalizedSampleSize to my normalizedSampleSizeText(sampleSizeText)
	my activateFinalCutPro()
	my focusBrowser()

	set itemCount to maxItems
	if itemCount is 0 then set itemCount to my visibleBrowserItemCount()
	if itemCount < 1 then my fail("Could not determine a positive current-event Browser item count. Select the first visible compound clip in the target Event, or pass MAX_ITEMS explicitly.")

	log "Queueing visible current-event Browser items: " & itemCount & " item(s), sample " & normalizedSampleSize & "."
	set totalStarted to 0
	set totalSkipped to 0
	repeat with itemIndex from 1 to itemCount
		log "Opening Browser item " & itemIndex & " of " & itemCount & "."
		my openSelectedClipThroughMenu()
		delay 0.8
		set itemSummary to my queueOpenTimelineClips(normalizedSampleSize, maxClipsPerItem)
		set totalStarted to totalStarted + (item 1 of itemSummary)
		set totalSkipped to totalSkipped + (item 2 of itemSummary)

		if itemIndex < itemCount then
			my focusBrowser()
			tell application "System Events"
				tell process fcpProcessName
					key code 125
				end tell
			end tell
			delay 0.25
		end if
	end repeat
	log "Queued current-event Browser items. Started " & totalStarted & " clip(s); skipped " & totalSkipped & " clip(s) without accessible Stabilizer controls."
end queueCurrentEventCompounds

on queueOpenTimelineClips(sampleSizeText, maxClips)
	set normalizedSampleSize to my normalizedSampleSizeText(sampleSizeText)
	my activateFinalCutPro()
	my focusTimeline()
	my goToTimelineBeginning()
	delay 0.2

	set previousTimecode to ""
	set startedCount to 0
	set skippedCount to 0
	repeat with clipIndex from 1 to maxClips
		set currentTimecode to my currentTimecodeText()
		if clipIndex > 1 and currentTimecode is previousTimecode then exit repeat
		set previousTimecode to currentTimecode

		my selectPlayheadClip()
		delay 0.2
		if my selectedClipHasStabilizerControls() then
			my setSampleSize(normalizedSampleSize)
			my startHostAnalysis()
			set startedCount to startedCount + 1
			log "Queued timeline clip " & clipIndex & " at " & currentTimecode & " with Sample Size " & normalizedSampleSize & "."
		else
			set skippedCount to skippedCount + 1
			log "Skipped timeline clip " & clipIndex & " at " & currentTimecode & ": Tokyo Walking Stabilizer controls were not accessible in the Video Inspector."
		end if

		my focusTimeline()
		my goToNextEdit()
		delay 0.25
	end repeat

	if startedCount is 0 then
		my fail("No timeline clips with accessible Tokyo Walking Stabilizer controls were queued.")
	end if

	log "Queued open timeline clips. Started " & startedCount & "; skipped " & skippedCount & "."
	return {startedCount, skippedCount}
end queueOpenTimelineClips

on selectedClipHasStabilizerControls()
	try
		set inspectorArea to my inspectorSearchRoot()
		if my directButton(inspectorArea, "Start Host Analysis") is not missing value then return true
	end try
	return false
end selectedClipHasStabilizerControls

on setSampleSize(sampleSizeText)
	set normalizedSampleSize to my normalizedSampleSizeText(sampleSizeText)
	my activateFinalCutPro()
	my focusInspector()

	set inspectorArea to my inspectorSearchRoot()
	set samplePopup to my popUpNearLabel(inspectorArea, "Sample Size", maxSearchDepth)
	if samplePopup is missing value then
		my fail("Could not find the Sample Size pop-up in the selected clip's Video Inspector.")
	end if

	my choosePopUpMenuItem(samplePopup, normalizedSampleSize, "Sample Size")
	log "Set Sample Size to " & normalizedSampleSize & "."
end setSampleSize

on startHostAnalysis()
	my activateFinalCutPro()
	my focusInspector()

	set inspectorArea to my inspectorSearchRoot()
	set startButton to my directButton(inspectorArea, "Start Host Analysis")
	if startButton is missing value then
		my fail("Could not find the Start Host Analysis button. Select a clip with Tokyo Walking Stabilizer applied, then open the Video Inspector.")
	end if

	my pressElement(startButton, "Start Host Analysis")
	log "Pressed Start Host Analysis."
end startHostAnalysis

on choosePopUpMenuItem(popUpElement, menuItemText, labelText)
	tell application "System Events"
		try
			perform action "AXPress" of popUpElement
		on error pressError
			my fail("Found " & labelText & " pop-up, but could not open it: " & pressError)
		end try
	end tell
	delay 0.25

	tell application "System Events"
		tell process fcpProcessName
			try
				click menu item menuItemText of menu 1 of popUpElement
				return
			end try
			try
				click menu item menuItemText of menu 1 of window 1
				return
			end try
			try
				click menu item menuItemText of menu 1
				return
			end try
		end tell
	end tell
	my fail("Opened " & labelText & " pop-up, but could not choose " & menuItemText & ".")
end choosePopUpMenuItem

on popUpNearLabel(rootElement, labelText, remainingDepth)
	if remainingDepth < 0 then return missing value

	if my elementTextEquals(rootElement, labelText) then
		set popupCandidate to my firstPopUpInAncestorChain(rootElement, 5)
		if popupCandidate is not missing value then return popupCandidate
	end if

	set childElements to {}
	tell application "System Events"
		try
			set childElements to UI elements of rootElement
		on error
			return missing value
		end try
	end tell

	repeat with childElement in childElements
		set foundElement to my popUpNearLabel(childElement, labelText, remainingDepth - 1)
		if foundElement is not missing value then return foundElement
	end repeat
	return missing value
end popUpNearLabel

on firstPopUpInAncestorChain(elementReference, remainingAncestors)
	if remainingAncestors < 0 then return missing value
	set popupCandidate to my firstControl(elementReference, "AXPopUpButton", "", 5)
	if popupCandidate is not missing value then return popupCandidate

	tell application "System Events"
		try
			set parentElement to parent of elementReference
		on error
			return missing value
		end try
	end tell
	return my firstPopUpInAncestorChain(parentElement, remainingAncestors - 1)
end firstPopUpInAncestorChain

on directButton(rootElement, buttonName)
	tell application "System Events"
		with timeout of 4 seconds
			try
				return first button of rootElement whose name is buttonName
			end try
		end timeout
	end tell
	return missing value
end directButton

on inspectorSearchRoot()
	tell application "System Events"
		with timeout of 4 seconds
			try
				set frontWindow to my frontFinalCutProWindow()
				return scroll area 1 of group 1 of group 1 of group 3 of splitter group 1 of group 2 of splitter group 1 of group 1 of splitter group 1 of frontWindow
			end try
		end timeout
	end tell
	set inspectorArea to missing value
	with timeout of 4 seconds
		set inspectorArea to my firstDescendant(my frontFinalCutProWindow(), "AXScrollArea", "inspector", 8)
	end timeout
	if inspectorArea is missing value then
		my fail("Could not resolve the Final Cut Pro Inspector area. Select a timeline clip with Tokyo Walking Stabilizer applied, then retry.")
	end if
	return inspectorArea
end inspectorSearchRoot

on focusInspector()
	my activateFinalCutPro()
	set inspectorToggle to my inspectorToolbarToggle()
	if inspectorToggle is not missing value then
		if my checkboxIsOn(inspectorToggle) then
			log "Final Cut Pro Inspector is already visible."
			return
		end if
	end if
	tell application "System Events"
		tell process fcpProcessName
			keystroke "4" using {command down}
		end tell
	end tell
	delay 0.2
	log "Focused or revealed the Final Cut Pro Inspector with Command-4."
end focusInspector

on focusBrowser()
	my activateFinalCutPro()
	my clickFirstMenuPath({{"Window", "Go To", "Browser"}}, "focus the Final Cut Pro Browser")
	delay 0.2
	log "Focused the Final Cut Pro Browser through Window > Go To > Browser."
end focusBrowser

on focusTimeline()
	my activateFinalCutPro()
	my clickFirstMenuPath({{"Window", "Go To", "Timeline"}}, "focus the Final Cut Pro Timeline")
	delay 0.2
	log "Focused the Final Cut Pro Timeline through Window > Go To > Timeline."
end focusTimeline

on openSelectedClipThroughMenu()
	my clickFirstMenuPath({{"Clip", "Open Clip"}}, "run Final Cut Pro Clip > Open Clip")
	delay 0.5
end openSelectedClipThroughMenu

on clickFirstMenuPath(menuPaths, actionDescription)
	set triedPaths to {}
	repeat with menuPathRef in menuPaths
		set menuPath to contents of menuPathRef
		try
			my clickMenuPath(menuPath)
			log actionDescription & " via " & my joinedMenuPath(menuPath) & "."
			return
		on error menuError
			set end of triedPaths to my joinedMenuPath(menuPath) & " (" & menuError & ")"
		end try
	end repeat
	my fail("Could not " & actionDescription & ". Tried: " & my joinTextList(triedPaths, "; "))
end clickFirstMenuPath

on clickMenuPath(menuPath)
	tell application "System Events"
		tell process fcpProcessName
			set currentMenu to menu (item 1 of menuPath) of menu bar 1
			repeat with pathIndex from 2 to count of menuPath
				set currentMenuItem to menu item (item pathIndex of menuPath) of currentMenu
				if pathIndex is (count of menuPath) then
					click currentMenuItem
				else
					set currentMenu to menu 1 of currentMenuItem
				end if
			end repeat
		end tell
	end tell
end clickMenuPath

on goToTimelineBeginning()
	tell application "System Events"
		tell process fcpProcessName
			key code 115
		end tell
	end tell
	delay 0.2
	log "Moved to the beginning of the open Final Cut Pro timeline with Home."
end goToTimelineBeginning

on goToNextEdit()
	tell application "System Events"
		tell process fcpProcessName
			key code 125
		end tell
	end tell
	delay 0.15
	log "Moved to the next Final Cut Pro edit with Down Arrow."
end goToNextEdit

on selectPlayheadClip()
	my activateFinalCutPro()
	tell application "System Events"
		tell process fcpProcessName
			keystroke "c"
		end tell
	end tell
	delay 0.2
	log "Selected the Final Cut Pro timeline clip under the playhead."
end selectPlayheadClip

on currentTimecodeText()
	set frontWindow to my frontFinalCutProWindow()
	set timecodeElement to my firstDescendant(frontWindow, "AXStaticText", "Timecode LCD", maxSearchDepth)
	if timecodeElement is missing value then my fail("Could not find the Final Cut Pro Timecode LCD while walking timeline edits.")
	tell application "System Events"
		try
			return value of timecodeElement as text
		end try
		try
			return name of timecodeElement as text
		end try
	end tell
	my fail("Found the Final Cut Pro Timecode LCD, but could not read its value.")
end currentTimecodeText

on visibleBrowserItemCount()
	set frontWindow to my frontFinalCutProWindow()
	set summaryElement to my firstDescendant(frontWindow, "AXStaticText", " selected", maxSearchDepth)
	if summaryElement is missing value then return 0
	set summaryText to ""
	tell application "System Events"
		try
			set summaryText to value of summaryElement as text
		end try
		if summaryText is "" then
			try
				set summaryText to name of summaryElement as text
			end try
		end if
	end tell
	return my itemCountFromSelectionSummary(summaryText)
end visibleBrowserItemCount

on itemCountFromSelectionSummary(summaryText)
	if summaryText does not contain " of " then return 0
	if summaryText does not contain " selected" then return 0
	set previousDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to " of "
	set afterOf to text item 2 of summaryText
	set AppleScript's text item delimiters to " selected"
	set totalText to text item 1 of afterOf
	set AppleScript's text item delimiters to ","
	set totalText to text item 1 of totalText
	set AppleScript's text item delimiters to previousDelimiters
	try
		return totalText as integer
	on error
		return 0
	end try
end itemCountFromSelectionSummary

on activateFinalCutPro()
	tell application fcpProcessName to activate
	delay 0.2
	tell application "System Events"
		if not (exists process fcpProcessName) then my fail("Final Cut Pro is not running.")
		tell process fcpProcessName
			set frontmost to true
		end tell
	end tell
	delay 0.15
end activateFinalCutPro

on frontFinalCutProWindow()
	tell application "System Events"
		tell process fcpProcessName
			repeat with attemptNumber from 1 to 20
				repeat with candidateWindow in windows
					try
						if subrole of candidateWindow is "AXStandardWindow" then return candidateWindow
					end try
				end repeat
				repeat with candidateWindow in windows
					if my hasUsableBounds(candidateWindow) then return candidateWindow
				end repeat
				delay 0.1
			end repeat
		end tell
	end tell
	my fail("Final Cut Pro has no accessible front window.")
end frontFinalCutProWindow

on inspectorToolbarToggle()
	tell application "System Events"
		try
			return first checkbox of toolbar 1 of my frontFinalCutProWindow() whose description is "Show or hide the Inspector"
		end try
	end tell
	return missing value
end inspectorToolbarToggle

on checkboxIsOn(elementReference)
	tell application "System Events"
		try
			set checkboxValue to value of elementReference
			if checkboxValue is 1 then return true
			if checkboxValue is "1" then return true
			if checkboxValue is true then return true
		end try
	end tell
	return false
end checkboxIsOn

on firstDescendant(rootElement, requiredRole, requiredText, remainingDepth)
	if remainingDepth < 0 then return missing value
	if my elementMatches(rootElement, requiredRole, requiredText) then return rootElement

	set childElements to {}
	tell application "System Events"
		try
			set childElements to UI elements of rootElement
		on error
			return missing value
		end try
	end tell

	repeat with childElement in childElements
		set foundElement to my firstDescendant(childElement, requiredRole, requiredText, remainingDepth - 1)
		if foundElement is not missing value then return foundElement
	end repeat
	return missing value
end firstDescendant

on firstControl(rootElement, requiredRole, requiredText, remainingDepth)
	if remainingDepth < 0 then return missing value
	if my controlMatches(rootElement, requiredRole, requiredText) then return rootElement

	set childElements to {}
	tell application "System Events"
		try
			set childElements to UI elements of rootElement
		on error
			return missing value
		end try
	end tell

	repeat with childElement in childElements
		set foundElement to my firstControl(childElement, requiredRole, requiredText, remainingDepth - 1)
		if foundElement is not missing value then return foundElement
	end repeat
	return missing value
end firstControl

on controlMatches(candidateElement, requiredRole, requiredText)
	tell application "System Events"
		set candidateRole to ""
		try
			set candidateRole to role of candidateElement as text
		end try
		if candidateRole is not requiredRole then return false
	end tell
	return my elementMatches(candidateElement, "", requiredText)
end controlMatches

on elementMatches(candidateElement, requiredRole, requiredText)
	tell application "System Events"
		if requiredRole is not "" then
			set candidateRole to ""
			try
				set candidateRole to role of candidateElement as text
			end try
			if candidateRole is not requiredRole then return false
		end if
		if requiredText is "" then return true

		set labelsToCheck to {}
		try
			set end of labelsToCheck to name of candidateElement as text
		end try
		try
			set end of labelsToCheck to description of candidateElement as text
		end try
		try
			set end of labelsToCheck to value of candidateElement as text
		end try
	end tell

	repeat with labelText in labelsToCheck
		if my textContains(labelText as text, requiredText) then return true
	end repeat
	return false
end elementMatches

on elementTextEquals(candidateElement, requiredText)
	set labelsToCheck to {}
	tell application "System Events"
		try
			set end of labelsToCheck to name of candidateElement as text
		end try
		try
			set end of labelsToCheck to description of candidateElement as text
		end try
		try
			set end of labelsToCheck to value of candidateElement as text
		end try
	end tell

	repeat with labelText in labelsToCheck
		ignoring case
			if (labelText as text) is requiredText then return true
		end ignoring
	end repeat
	return false
end elementTextEquals

on hasUsableBounds(elementReference)
	tell application "System Events"
		try
			set elementSize to size of elementReference
			if (item 1 of elementSize) < 4 then return false
			if (item 2 of elementSize) < 4 then return false
			set elementPosition to position of elementReference
			item 1 of elementPosition
			item 2 of elementPosition
			return true
		on error
			return false
		end try
	end tell
end hasUsableBounds

on pressElement(elementReference, labelText)
	tell application "System Events"
		try
			perform action "AXPress" of elementReference
			return
		on error pressError
			log "AXPress failed for " & labelText & ": " & pressError
		end try

		try
			click elementReference
			return
		on error clickError
			my fail("Found " & labelText & ", but could not click it: " & clickError)
		end try
	end tell
end pressElement

on joinedMenuPath(menuPath)
	return my joinTextList(menuPath, " > ")
end joinedMenuPath

on joinTextList(textItems, separatorText)
	set previousDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to separatorText
	set joinedText to textItems as text
	set AppleScript's text item delimiters to previousDelimiters
	return joinedText
end joinTextList

on normalizedSampleSizeText(sampleSizeText)
	set normalizedText to sampleSizeText as text
	if normalizedText does not end with "%" then set normalizedText to normalizedText & "%"
	if allowedSampleSizes does not contain normalizedText then
		my fail("Sample Size must be one of 100%, 75%, 50%, 25%, or 10%; got " & sampleSizeText & ".")
	end if
	return normalizedText
end normalizedSampleSizeText

on parsePositiveInteger(valueText, labelText)
	try
		set parsedValue to valueText as integer
	on error
		my fail(labelText & " must be a positive integer: " & valueText)
	end try
	if parsedValue < 1 then my fail(labelText & " must be a positive integer: " & valueText)
	return parsedValue
end parsePositiveInteger

on parseNonNegativeInteger(valueText, labelText)
	try
		set parsedValue to valueText as integer
	on error
		my fail(labelText & " must be a non-negative integer: " & valueText)
	end try
	if parsedValue < 0 then my fail(labelText & " must be a non-negative integer: " & valueText)
	return parsedValue
end parseNonNegativeInteger

on textContains(haystackText, needleText)
	ignoring case
		return haystackText contains needleText
	end ignoring
end textContains

on fail(messageText)
	error "Final Cut Pro batch stabilizer failed: " & messageText number 9002
end fail
