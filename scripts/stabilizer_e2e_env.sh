#!/usr/bin/env bash

# Load machine-local E2E paths without committing them to the repository.
# Callers may set STABILIZER_E2E_ENV_FILE to use a different file. Existing
# process environment values remain authoritative over values in the file.
stabilizer_load_e2e_env() {
	local root_dir="$1"
	local explicit_env_file="${STABILIZER_E2E_ENV_FILE:-}"
	local env_file="${explicit_env_file:-${root_dir}/.env.e2e.local}"
	local had_allexport=0
	local index
	local name
	local existing_names=()
	local existing_values=()

	if [[ -n "$explicit_env_file" && ! -f "$env_file" ]]; then
		printf 'E2E environment file does not exist: %s\n' "$env_file" >&2
		return 2
	fi
	if [[ ! -f "$env_file" ]]; then
		return 0
	fi

	for name in \
		STABILIZER_FCP_HELPER \
		STABILIZER_E2E_LIBRARY \
		STABILIZER_UI_TEST_LIBRARY \
		STABILIZER_UI_TEST_EVENT \
		STABILIZER_E2E_ARTIFACT_DIR; do
		if [[ -n "${!name:-}" ]]; then
			existing_names+=("$name")
			existing_values+=("${!name}")
		fi
	done

	case "$-" in
		*a*) had_allexport=1 ;;
	esac
	set -a
	# This is a user-owned local shell environment file, equivalent to sourcing
	# a project .env file from a trusted checkout.
	# shellcheck disable=SC1090
	source "$env_file"
	if [[ "$had_allexport" == "0" ]]; then
		set +a
	fi

	for ((index = 0; index < ${#existing_names[@]}; index++)); do
		name="${existing_names[$index]}"
		printf -v "$name" '%s' "${existing_values[$index]}"
		export "${name?}"
	done
}

stabilizer_resolve_e2e_case() {
	local root_dir="$1"
	local source_case="$2"
	local output_case="$3"

	python3 "${root_dir}/scripts/resolve_stabilizer_e2e_case.py" \
		--input "$source_case" \
		--output "$output_case"
}
