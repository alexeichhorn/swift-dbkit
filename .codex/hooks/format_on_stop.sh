#!/usr/bin/env bash

# Stop hook for Codex and Claude Code: formats the Swift files that git reports as changed and, if that
# changed any of them or the formatter failed, blocks the stop so the agent reviews the diff or the error.
# Reads the hook's JSON on stdin and prints a block decision on stdout, or nothing.

set -euo pipefail

input="$(cat)"
cwd="$(jq -r '.cwd // empty' <<< "$input")"
stop_hook_active="$(jq -r '.stop_hook_active // false' <<< "$input")"

[[ -n "$cwd" ]] || exit 0
repo_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$repo_root"

file_hash() {
  shasum < "$1" | cut -d ' ' -f 1
}

swift_files=()
while IFS= read -r -d '' path; do
  case "$path" in
    .build/* | */.build/*) ;;
    *.swift)
      if [[ -f "$path" ]]; then
        swift_files+=("$path")
      fi
      ;;
  esac
done < <(
  {
    git diff --name-only -z
    git diff --cached --name-only -z
    git ls-files --others --exclude-standard -z
  } | sort -zu
)

[[ ${#swift_files[@]} -gt 0 ]] || exit 0

hashes_before=()
for path in "${swift_files[@]}"; do
  hashes_before+=("$(file_hash "$path")")
done

# swift format reads .swift-format by itself and still formats the other files when one fails to parse.
formatter_failed=false
formatter_output="$(swift format --in-place -- "${swift_files[@]}" 2>&1)" || formatter_failed=true

changed_files=""
for i in "${!swift_files[@]}"; do
  if [[ "$(file_hash "${swift_files[$i]}")" != "${hashes_before[$i]}" ]]; then
    changed_files+="${changed_files:+, }${swift_files[$i]}"
  fi
done

reason=""
if [[ -n "$changed_files" ]]; then
  reason="Auto-formatting changed Swift files: $changed_files. Review the updated diff, then finish the turn."
fi
# Reported only on the first stop: blocking again could loop when the agent cannot fix the file.
if [[ "$formatter_failed" == true && "$stop_hook_active" != true ]]; then
  reason="Auto-formatting failed. Fix or report this swift format error: $formatter_output${reason:+$'\n'$reason}"
fi

if [[ -n "$reason" ]]; then
  jq -n --arg reason "$reason" '{decision: "block", reason: $reason}'
fi
