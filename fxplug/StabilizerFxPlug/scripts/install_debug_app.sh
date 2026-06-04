#!/bin/sh
set -eu

PLUGIN_IDENTIFIER="com.justadev.CommandPostEmDash.StabilizerFxPlug.Plugin"
APP_NAME="StabilizerFxPlug.app"
PLUGIN_RELATIVE_PATH="Contents/PlugIns/StabilizerFxPlug XPC Service.pluginkit"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)
MOTION_TEMPLATE_SOURCE="${PROJECT_DIR}/MotionTemplates/Effects.localized/CommandPost Em Dash/Stabilizer Transform"
MOTION_TEMPLATE_DEST="${HOME}/Movies/Motion Templates.localized/Effects.localized/CommandPost Em Dash/Stabilizer Transform"

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
legacy_user_app="${HOME}/Applications/${APP_NAME}"
legacy_user_plugin="${legacy_user_app}/${PLUGIN_RELATIVE_PATH}"

unregister_stale_plugins() {
	pluginkit -m -A -D -v -p FxPlug -i "$PLUGIN_IDENTIFIER" 2>/dev/null | while IFS= read -r line; do
		plugin_path=$(printf '%s\n' "$line" | sed -n 's/.*	//p')
		if [ -n "$plugin_path" ] && [ "$plugin_path" != "$install_plugin" ] && [ -d "$plugin_path" ]; then
			pluginkit -r "$plugin_path" >/dev/null 2>&1 || true
		fi
	done
}

install_motion_template() {
	if [ ! -d "$MOTION_TEMPLATE_SOURCE" ]; then
		echo "error: Motion Template source not found: $MOTION_TEMPLATE_SOURCE" >&2
		exit 1
	fi

	mkdir -p "$(dirname "$MOTION_TEMPLATE_DEST")"
	rm -rf "$MOTION_TEMPLATE_DEST"
	ditto "$MOTION_TEMPLATE_SOURCE" "$MOTION_TEMPLATE_DEST"
}

mkdir -p "$install_dir"

if [ -d "$install_plugin" ]; then
	pluginkit -r "$install_plugin" >/dev/null 2>&1 || true
fi

if [ -d "$legacy_user_plugin" ] && [ "$legacy_user_plugin" != "$install_plugin" ]; then
	pluginkit -r "$legacy_user_plugin" >/dev/null 2>&1 || true
	"$LSREGISTER" -u "$legacy_user_app" >/dev/null 2>&1 || true
fi

unregister_stale_plugins

ditto "$source_app" "$install_app"
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
