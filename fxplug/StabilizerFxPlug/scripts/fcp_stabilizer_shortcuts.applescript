#!/usr/bin/osascript
use AppleScript version "2.4"
use scripting additions

property fcpProcessName : "Final Cut Pro"
property stabilizerEffectName : "Stabilizer Transform"
property effectsSearchText : "Stabilizer Transform"
property maxSearchDepth : 12

on run argv
	if (count of argv) is 0 then
		my failWithUsage()
	end if

	set commandName to item 1 of argv
	if commandName is "apply" then
		my applyStabilizerTransform()
	else if commandName is "start-analysis" then
		my startHostAnalysis()
	else if commandName is "toggle-debug-overlay" then
		my toggleDebugOverlay()
	else if commandName is "focus-inspector" then
		my focusInspector()
	else if commandName is "dump-front-window" then
		my dumpFrontWindow()
	else
		my failWithUsage()
	end if
end run

on failWithUsage()
	my fail("Usage: osascript fcp_stabilizer_shortcuts.applescript apply|start-analysis|toggle-debug-overlay|focus-inspector|dump-front-window")
end failWithUsage

on applyStabilizerTransform()
	my activateFinalCutPro()
	my openEffectsBrowser()
	my setEffectsSearch(effectsSearchText)
	delay 0.35
	my pressEffectResult(stabilizerEffectName)
	log "Applied " & stabilizerEffectName & " to the selected Final Cut Pro clip."
end applyStabilizerTransform

on startHostAnalysis()
	my activateFinalCutPro()
	my focusInspector()

	set frontWindow to my frontFinalCutProWindow()
	set startButton to my firstDescendant(frontWindow, "AXButton", "Start Host Analysis", maxSearchDepth)
	if startButton is missing value then
		my fail("Could not find the Start Host Analysis button. Select a clip with Stabilizer Transform applied, then open the Video Inspector.")
	end if

	my pressElement(startButton, "Start Host Analysis")
	log "Pressed Start Host Analysis."
end startHostAnalysis

on toggleDebugOverlay()
	my activateFinalCutPro()
	my focusInspector()

	set frontWindow to my frontFinalCutProWindow()
	set overlayCheckbox to my firstDescendant(frontWindow, "AXCheckBox", "Debug Overlay", maxSearchDepth)
	if overlayCheckbox is missing value then
		my fail("Could not find the Debug Overlay checkbox. Select a clip with Stabilizer Transform applied, then open the Video Inspector.")
	end if

	my pressElement(overlayCheckbox, "Debug Overlay")
	log "Toggled Debug Overlay."
end toggleDebugOverlay

on focusInspector()
	my activateFinalCutPro()
	tell application "System Events"
		tell process fcpProcessName
			keystroke "4" using {command down}
		end tell
	end tell
	delay 0.2
	log "Focused or revealed the Final Cut Pro Inspector with Command-4."
end focusInspector

on dumpFrontWindow()
	my activateFinalCutPro()
	set frontWindow to my frontFinalCutProWindow()
	my dumpElement(frontWindow, 0, 7)
end dumpFrontWindow

on activateFinalCutPro()
	tell application fcpProcessName to activate
	delay 0.2
	tell application "System Events"
		if not (exists process fcpProcessName) then
			my fail("Final Cut Pro is not running.")
		end if
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
				if exists window 1 then
					return window 1
				end if
				delay 0.1
			end repeat
		end tell
	end tell
	my fail("Final Cut Pro has no accessible front window.")
end frontFinalCutProWindow

on openEffectsBrowser()
	tell application "System Events"
		tell process fcpProcessName
			keystroke "5" using {command down}
		end tell
	end tell
	delay 0.35
	log "Focused or revealed the Final Cut Pro Effects Browser with Command-5."
end openEffectsBrowser

on setEffectsSearch(searchText)
	set frontWindow to my frontFinalCutProWindow()
	set searchField to my firstDescendant(frontWindow, "AXSearchField", "Search", maxSearchDepth)
	if searchField is missing value then
		set searchField to my firstDescendant(frontWindow, "AXTextField", "Search", maxSearchDepth)
	end if
	if searchField is missing value then
		my fail("Could not find the Effects Browser search field. Open the Effects Browser and confirm the Search field is visible.")
	end if

	tell application "System Events"
		try
			set focused of searchField to true
		end try
		try
			set value of searchField to searchText
		on error searchError
			my fail("Found the Effects Browser search field, but could not set it: " & searchError)
		end try
		keystroke return
	end tell
end setEffectsSearch

on pressEffectResult(effectName)
	set frontWindow to my frontFinalCutProWindow()
	set effectElement to my firstEffectResult(frontWindow, effectName, maxSearchDepth)
	if effectElement is missing value then
		my fail("Could not find the " & effectName & " effect result. Confirm the installed Motion Template appears under Emdash Studios in Final Cut Pro.")
	end if

	tell application "System Events"
		try
			perform action "AXPress" of effectElement
			return
		on error pressError
			log "AXPress on effect result failed: " & pressError
		end try

		try
			click effectElement
			delay 0.1
			keystroke return
			return
		on error clickError
			my fail("Found the " & effectName & " effect result, but could not apply it: " & clickError)
		end try
	end tell
end pressEffectResult

on firstEffectResult(rootElement, effectName, remainingDepth)
	if remainingDepth < 0 then return missing value

	if my elementMatches(rootElement, "", effectName) then
		set pressableElement to my nearestPressableElement(rootElement, 5)
		if pressableElement is not missing value then return pressableElement
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
		set foundElement to my firstEffectResult(childElement, effectName, remainingDepth - 1)
		if foundElement is not missing value then return foundElement
	end repeat

	return missing value
end firstEffectResult

on nearestPressableElement(elementReference, remainingAncestors)
	if remainingAncestors < 0 then return missing value

	if my isDisallowedEffectResultElement(elementReference) then return missing value
	if my isPressableElement(elementReference) then return elementReference

	tell application "System Events"
		try
			set parentElement to parent of elementReference
		on error
			return missing value
		end try
	end tell

	return my nearestPressableElement(parentElement, remainingAncestors - 1)
end nearestPressableElement

on isDisallowedEffectResultElement(elementReference)
	tell application "System Events"
		set roleText to ""
		try
			set roleText to role of elementReference as text
		end try
	end tell

	if roleText is "AXSearchField" then return true
	if roleText is "AXTextField" then return true
	if roleText is "AXTextArea" then return true
	if roleText is "AXWindow" then return true
	if roleText is "AXApplication" then return true
	return false
end isDisallowedEffectResultElement

on isPressableElement(elementReference)
	tell application "System Events"
		set roleText to ""
		try
			set roleText to role of elementReference as text
		end try

		try
			set actionNames to name of actions of elementReference
			if actionNames contains "AXPress" then return true
		end try
	end tell

	if roleText is "AXButton" then return true
	if roleText is "AXCell" then return true
	if roleText is "AXGroup" then return true
	if roleText is "AXImage" then return true
	return false
end isPressableElement

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

on textContains(haystackText, needleText)
	ignoring case
		return haystackText contains needleText
	end ignoring
end textContains

on dumpElement(elementReference, indentLevel, remainingDepth)
	if remainingDepth < 0 then return

	set indentText to ""
	repeat indentLevel times
		set indentText to indentText & "  "
	end repeat

	tell application "System Events"
		set roleText to ""
		set nameText to ""
		set descriptionText to ""
		set valueText to ""
		try
			set roleText to role of elementReference as text
		end try
		try
			set nameText to name of elementReference as text
		end try
		try
			set descriptionText to description of elementReference as text
		end try
		try
			set valueText to value of elementReference as text
		end try
		log indentText & roleText & " | name=" & nameText & " | desc=" & descriptionText & " | value=" & valueText

		set childElements to {}
		try
			set childElements to UI elements of elementReference
		end try
	end tell

	repeat with childElement in childElements
		my dumpElement(childElement, indentLevel + 1, remainingDepth - 1)
	end repeat
end dumpElement

on fail(messageText)
	error "Stabilizer FCP shortcut failed: " & messageText number 9001
end fail
