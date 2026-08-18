#!/usr/bin/env bash
# Local equivalent of the notify-sdks.yml -> generate.yml chain: regenerate the language SDKs from a
# spec without going through GitHub Actions. Always reads the *working copy* of openapi.yaml next to
# this script, so a spec edit can be tried out before it is pushed.
#
#   ./update-sdk.sh                     # regenerate all SDKs from ./openapi.yaml, no git writes
#   ./update-sdk.sh sdk-node sdk-go     # only these repos
#   ./update-sdk.sh --commit            # also commit, on whatever branch the repo is already on
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The sdk-* checkouts live next to this repo; override if your layout differs.
SDK_ROOT="${SDK_ROOT:-$(dirname "$SCRIPT_DIR")}"
GENERATOR_IMAGE="${OPENAPI_GENERATOR_IMAGE:-openapitools/openapi-generator-cli}"
SPEC="$SCRIPT_DIR/openapi.yaml"

ALL_REPOS=(sdk-node sdk-php sdk-go sdk-python)
COMMIT_MESSAGE="chore: regenerate from latest OpenAPI spec"

mode="generate" # generate | commit
repos=()

usage() {
  sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --commit) mode="commit" ;;
    -h|--help) usage 0 ;;
    -*) echo "unknown flag: $1" >&2; usage 1 ;;
    *) repos+=("$1") ;;
  esac
  shift
done
[ ${#repos[@]} -gt 0 ] || repos=("${ALL_REPOS[@]}")

# Sets GENERATOR and GEN_ARGS for a repo. Must stay identical to that repo's generate.yml.
generator_args() {
  case "$1" in
    sdk-node)
      GENERATOR="typescript-fetch"
      GEN_ARGS=(--additional-properties=npmName=@otp.com/sdk-node,npmVersion=1.0.0,supportsES6=true) ;;
    sdk-php)
      GENERATOR="php"
      GEN_ARGS=('--additional-properties=invokerPackage=OtpCom\Sdk,composerVendorName=otp-com,composerPackageName=sdk-php,artifactVersion=1.0.0') ;;
    sdk-go)
      GENERATOR="go"
      GEN_ARGS=(--git-user-id otp-com --git-repo-id sdk-go --additional-properties=packageName=otp,isGoSubmodule=false) ;;
    sdk-python)
      GENERATOR="python"
      # pyproject.toml holds the released package version and the generator no longer owns it
      # (.openapi-generator-ignore). Feed it back in so the version stamped into setup.py and
      # otp_sdk/__init__.py follows the release instead of drifting back to a hardcoded one.
      local version
      version=$(sed -n 's/^version = "\(.*\)"/\1/p' "$SDK_ROOT/$1/pyproject.toml" | head -1)
      [ -n "$version" ] || { echo "no version line in $SDK_ROOT/$1/pyproject.toml" >&2; return 1; }
      GEN_ARGS=(--git-user-id otp-com --git-repo-id sdk-python \
        --additional-properties=packageName=otp_sdk,projectName=otp-sdk,packageUrl=https://github.com/otp-com/sdk-python,packageVersion="$version") ;;
    *)
      echo "unknown SDK repo: $1 (expected one of: ${ALL_REPOS[*]})" >&2
      return 1 ;;
  esac
}

command -v docker >/dev/null || { echo "docker is required" >&2; exit 1; }
[ -f "$SPEC" ] || { echo "spec not found: $SPEC" >&2; exit 1; }
echo "==> using spec $SPEC"

regenerate() {
  local repo="$1" dir="$SDK_ROOT/$repo" is_git=0

  echo
  echo "==> $repo"
  [ -d "$dir" ] || { echo "    skipped: $dir does not exist"; return 0; }
  generator_args "$repo"
  git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 && is_git=1

  # Branches are the human's call: commit lands on the checked-out branch, whatever it is.
  if [ "$mode" = "commit" ]; then
    [ "$is_git" = 1 ] || { echo "    skipped: $dir is not a git repo, --commit needs one"; return 0; }
    if [ -n "$(git -C "$dir" status --porcelain)" ]; then
      echo "    skipped: working tree is dirty, commit or stash first"
      return 0
    fi
  fi

  # Delete everything the previous run generated before generating again. The generator never
  # removes an output that fell out of the spec (removed schemas linger as orphans: the
  # Error/ErrorError cleanup of 2026-08-13), and on a case-insensitive filesystem a case-only class
  # rename overwrites the old file in place instead of replacing it (OtpApi.ts vs OTPApi.ts, same
  # day). Anything still current is rewritten by the generate step right after; hand-maintained
  # files (README + everything in .openapi-generator-ignore) are not in the manifest and survive.
  # Must stay identical to the "Prune previous outputs" step in each repo's generate.yml.
  if [ -f "$dir/.openapi-generator/FILES" ]; then
    while IFS= read -r f; do
      case "$f" in ''|/*|*..*) continue ;; esac
      rm -f "$dir/$f"
    done < "$dir/.openapi-generator/FILES"
  fi

  # The generator reads the spec from inside the repo, exactly as CI does, then it is removed again.
  cp "$SPEC" "$dir/openapi.yaml"
  docker run --rm -v "$dir":/local "$GENERATOR_IMAGE" generate \
    -i /local/openapi.yaml -g "$GENERATOR" -o /local "${GEN_ARGS[@]}"
  rm -f "$dir/openapi.yaml"

  if [ "$is_git" = 0 ]; then
    echo "    generated (not a git repo, review $dir by hand)"
    return 0
  fi

  local changes
  changes="$(git -C "$dir" status --porcelain | wc -l | tr -d ' ')"
  if [ "$changes" = "0" ]; then
    echo "    no changes"
    return 0
  fi
  echo "    $changes changed path(s)"

  case "$mode" in
    generate) git -C "$dir" status --short | head -20 ;;
    commit)
      git -C "$dir" add -A
      git -C "$dir" commit -q -m "$COMMIT_MESSAGE"
      echo "    committed on $(git -C "$dir" rev-parse --abbrev-ref HEAD) (not pushed)" ;;
  esac
}

for repo in "${repos[@]}"; do
  regenerate "$repo"
done

echo
echo "==> done (${mode} mode)"
