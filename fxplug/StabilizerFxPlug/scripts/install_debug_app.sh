#!/bin/sh
set -eu

PLUGIN_IDENTIFIER="com.justadev.CommandPostEmDash.StabilizerFxPlug.Plugin"
APP_NAME="StabilizerFxPlug.app"
PLUGIN_RELATIVE_PATH="Contents/PlugIns/StabilizerFxPlug XPC Service.pluginkit"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

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

install_dir="${HOME}/Applications"
install_app="${install_dir}/${APP_NAME}"
install_plugin="${install_app}/${PLUGIN_RELATIVE_PATH}"
source_plugin="${source_app}/${PLUGIN_RELATIVE_PATH}"

mkdir -p "$install_dir"

if [ -d "$install_plugin" ]; then
	pluginkit -r "$install_plugin" >/dev/null 2>&1 || true
fi

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

pluginkit -a "$install_plugin"

if ! pluginkit -m -A -p FxPlug -i "$PLUGIN_IDENTIFIER" | grep -q "$PLUGIN_IDENTIFIER"; then
	echo "error: PluginKit did not report registered FxPlug: $PLUGIN_IDENTIFIER" >&2
	exit 1
fi

"$LSREGISTER" -f -R -trusted "$install_app"

echo "Installed and registered FxPlug app: $install_app"
