#!/bin/sh
set -eu

PLUGIN_IDENTIFIER="com.justadev.TokyoWalkingStabilizer.Plugin"
APP_NAME="TokyoWalkingStabilizer.app"
PLUGIN_RELATIVE_PATH="Contents/PlugIns/TokyoWalkingStabilizer XPC Service.pluginkit"
OLD_PLUGIN_IDENTIFIER="com.justadev.StabilizerFxPlug.Plugin"
OLD_APP_NAME="StabilizerFxPlug.app"
OLD_PLUGIN_RELATIVE_PATH="Contents/PlugIns/StabilizerFxPlug XPC Service.pluginkit"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)
MOTION_TEMPLATE_SOURCE="${PROJECT_DIR}/MotionTemplates/Effects.localized/Emdash Studios/Tokyo Walking Stabilizer"
MOTION_TEMPLATE_DEST="${HOME}/Movies/Motion Templates.localized/Effects.localized/Emdash Studios/Tokyo Walking Stabilizer"
MOTION_TEMPLATE_GROUP="${HOME}/Movies/Motion Templates.localized/Effects.localized/Emdash Studios"

unset SWIFT_DEBUG_INFORMATION_FORMAT
unset SWIFT_DEBUG_INFORMATION_VERSION

source_app="${1:-}"
if [ -z "$source_app" ]; then
	if [ -n "${BUILT_PRODUCTS_DIR:-}" ] && [ -n "${FULL_PRODUCT_NAME:-}" ]; then
		source_app="${BUILT_PRODUCTS_DIR}/${FULL_PRODUCT_NAME}"
	else
		echo "error: source app path is required, or BUILT_PRODUCTS_DIR/FULL_PRODUCT_NAME must be set." >&2
		exit 1
	fi
fi

if [ ! -d "$source_app" ]; then
	echo "error: built app not found: $source_app" >&2
	exit 1
fi

install_dir="/Applications"
install_app="${install_dir}/${APP_NAME}"
install_plugin="${install_app}/${PLUGIN_RELATIVE_PATH}"
source_plugin="${source_app}/${PLUGIN_RELATIVE_PATH}"
old_install_app="${install_dir}/${OLD_APP_NAME}"
old_install_plugin="${old_install_app}/${OLD_PLUGIN_RELATIVE_PATH}"
legacy_user_app="${HOME}/Applications/${APP_NAME}"
legacy_user_plugin="${legacy_user_app}/${PLUGIN_RELATIVE_PATH}"
old_legacy_user_app="${HOME}/Applications/${OLD_APP_NAME}"
old_legacy_user_plugin="${old_legacy_user_app}/${OLD_PLUGIN_RELATIVE_PATH}"

if pgrep -x "Final Cut Pro" >/dev/null 2>&1; then
	echo "error: Final Cut Pro is running. Quit Final Cut Pro before installing TokyoWalkingStabilizer." >&2
	echo "       Replacing a loaded FxPlug can leave Final Cut Pro holding a stale PlugInKit object and trigger P1000307 helper communication errors." >&2
	exit 1
fi

unregister_stale_plugins() {
	pluginkit -m -A -D -v -p FxPlug -i "$PLUGIN_IDENTIFIER" 2>/dev/null | while IFS= read -r line; do
		plugin_path=$(printf '%s\n' "$line" | sed -n 's/.*	//p')
		if [ -n "$plugin_path" ] && [ "$plugin_path" != "$install_plugin" ] && [ -d "$plugin_path" ]; then
			echo "Unregistering stale Tokyo Walking Stabilizer FxPlug: $plugin_path"
			pluginkit -r "$plugin_path" >/dev/null 2>&1 || true
		fi
	done
}

unregister_old_plugins() {
	pluginkit -m -A -D -v -p FxPlug -i "$OLD_PLUGIN_IDENTIFIER" 2>/dev/null | while IFS= read -r line; do
		plugin_path=$(printf '%s\n' "$line" | sed -n 's/.*	//p')
		if [ -n "$plugin_path" ] && [ -d "$plugin_path" ]; then
			echo "Unregistering old StabilizerFxPlug FxPlug: $plugin_path"
			pluginkit -r "$plugin_path" >/dev/null 2>&1 || true
		fi
	done
}

install_motion_template() {
	if [ ! -d "$MOTION_TEMPLATE_SOURCE" ]; then
		echo "error: Motion Template source not found: $MOTION_TEMPLATE_SOURCE" >&2
		exit 1
	fi

	mkdir -p "$MOTION_TEMPLATE_GROUP"

	for template_group in \
		"$MOTION_TEMPLATE_GROUP" \
		"${HOME}/Movies/Motion Templates.localized/Effects.localized/Stabilizer" \
		"${HOME}/Movies/Motion Templates.localized/Effects.localized/CommandPost Em Dash"
	do
		if [ -d "$template_group" ]; then
			find "$template_group" -maxdepth 1 -type d -name 'Stabilizer Transform*' -print | while IFS= read -r duplicate_template; do
				echo "Removing old Stabilizer Transform Motion Template: $duplicate_template"
				rm -rf "$duplicate_template"
			done
			find "$template_group" -maxdepth 1 -type d -name 'Tokyo Walking Stabilizer*' -print | while IFS= read -r duplicate_template; do
				if [ "$duplicate_template" != "$MOTION_TEMPLATE_DEST" ]; then
					echo "Removing stale Motion Template duplicate: $duplicate_template"
					rm -rf "$duplicate_template"
				fi
			done
		fi
	done

	rm -rf "$MOTION_TEMPLATE_DEST"
	ditto "$MOTION_TEMPLATE_SOURCE" "$MOTION_TEMPLATE_DEST"
	touch "$MOTION_TEMPLATE_DEST" "$MOTION_TEMPLATE_DEST/Tokyo Walking Stabilizer.moef"

	for legacy_group in \
		"${HOME}/Movies/Motion Templates.localized/Effects.localized/Stabilizer" \
		"${HOME}/Movies/Motion Templates.localized/Effects.localized/CommandPost Em Dash"
	do
		if [ -d "$legacy_group" ]; then
			rm -f "$legacy_group/.DS_Store"
			rmdir "$legacy_group" 2>/dev/null || true
		fi
	done
}

mkdir -p "$install_dir"

if [ -d "$install_plugin" ]; then
	pluginkit -r "$install_plugin" >/dev/null 2>&1 || true
fi

if [ -d "$legacy_user_plugin" ] && [ "$legacy_user_plugin" != "$install_plugin" ]; then
	echo "Unregistering stale user Tokyo Walking Stabilizer FxPlug: $legacy_user_plugin"
	pluginkit -r "$legacy_user_plugin" >/dev/null 2>&1 || true
	"$LSREGISTER" -u "$legacy_user_app" >/dev/null 2>&1 || true
fi

if [ -d "$legacy_user_app" ] && [ "$legacy_user_app" != "$install_app" ]; then
	echo "Removing stale user Tokyo Walking Stabilizer app: $legacy_user_app"
	rm -rf "$legacy_user_app"
fi

if [ -d "$old_install_plugin" ]; then
	echo "Unregistering old StabilizerFxPlug install: $old_install_plugin"
	pluginkit -r "$old_install_plugin" >/dev/null 2>&1 || true
fi

if [ -d "$old_install_app" ]; then
	echo "Removing old StabilizerFxPlug app: $old_install_app"
	"$LSREGISTER" -u "$old_install_app" >/dev/null 2>&1 || true
	rm -rf "$old_install_app"
fi

if [ -d "$old_legacy_user_plugin" ]; then
	echo "Unregistering old user StabilizerFxPlug install: $old_legacy_user_plugin"
	pluginkit -r "$old_legacy_user_plugin" >/dev/null 2>&1 || true
fi

if [ -d "$old_legacy_user_app" ]; then
	echo "Removing old user StabilizerFxPlug app: $old_legacy_user_app"
	"$LSREGISTER" -u "$old_legacy_user_app" >/dev/null 2>&1 || true
	rm -rf "$old_legacy_user_app"
fi

unregister_old_plugins
unregister_stale_plugins

if [ "$source_app" != "$install_app" ]; then
	ditto "$source_app" "$install_app"
fi
touch "$install_app" "$install_plugin"
xattr -dr com.apple.quarantine "$install_app" >/dev/null 2>&1 || true

codesign --verify --deep --strict "$install_app"

if [ ! -d "$install_plugin" ]; then
	echo "error: embedded pluginkit not found after install: $install_plugin" >&2
	exit 1
fi

if [ -d "$source_plugin" ] && [ "$source_plugin" != "$install_plugin" ]; then
	pluginkit -r "$source_plugin" >/dev/null 2>&1 || true
fi

if [ "$source_app" != "$install_app" ]; then
	"$LSREGISTER" -u "$source_app" >/dev/null 2>&1 || true
fi

"$LSREGISTER" -f -R -trusted "$install_app"
pluginkit -a "$install_plugin"
unregister_stale_plugins
install_motion_template

attempt=1
registered=""
while [ "$attempt" -le 10 ]; do
	if pluginkit -m -A -D -v -p FxPlug -i "$PLUGIN_IDENTIFIER" | grep -q "$install_plugin"; then
		registered="yes"
		break
	fi
	sleep 0.5
	attempt=$((attempt + 1))
done

if [ "$registered" != "yes" ]; then
	echo "error: PluginKit did not report registered FxPlug: $PLUGIN_IDENTIFIER" >&2
	exit 1
fi

echo "Installed and registered FxPlug app: $install_app"
echo "Installed Motion Template effect: $MOTION_TEMPLATE_DEST"
