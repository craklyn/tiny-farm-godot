#!/usr/bin/env bash
# Keep the commit a tablet build was made from on GitHub, so a session the tablet
# records can always be replayed on the build that recorded it.
#
#   tools/save_build_marker.sh [commit]      (default: HEAD)
#
# Why (2026-10-09): three sessions from 2026-09-25 were recorded on 894089c, a commit
# on this desktop that was rebased before it was pushed. Its id was never on GitHub,
# so HQ could no longer tie them to a build. Tablet builds are often made from
# branches that are not merged yet, and refusing those was judged a real cost, so the
# deploy does not demand a pushed commit. It saves one instead.
#
# Pushes refs/builds/<full commit id>. Nothing fetches that ref by default and no
# workflow runs on it, but GitHub keeps the commit for as long as the ref exists. It is
# never a v* tag: a pushed v* tag publishes a release (docs/DEPLOY.md).
#
# Never stops a deploy. If the push fails (no network, GitHub down), it says so loudly,
# lists the commit in build/unsaved_build_markers.txt, and exits 0. Every run retries
# whatever that list holds first, so the next deploy with a network catches up.
set -uo pipefail

cd "$(dirname "$0")/.."

REMOTE="${BUILD_MARKER_REMOTE:-origin}"
PENDING="build/unsaved_build_markers.txt"
# Run unattended from HQ's deploy button: never wait on a password prompt or a dead link.
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=15}"
export GIT_TERMINAL_PROMPT=0

commit=$(git rev-parse --verify --quiet "${1:-HEAD}^{commit}") || {
	echo "WARNING: no commit '${1:-HEAD}' to save on GitHub." >&2
	exit 0
}

mkdir -p "$(dirname "$PENDING")"
todo=()
if [[ -f "$PENDING" ]]; then
	while IFS= read -r line; do
		[[ -n "$line" && "$line" != "$commit" ]] && todo+=("$line")
	done < "$PENDING"
fi
todo+=("$commit")

unsaved=()
for c in "${todo[@]}"; do
	if ! git cat-file -e "$c^{commit}" 2>/dev/null; then
		echo "WARNING: build $c was never saved on GitHub and is gone from this checkout too." >&2
		continue
	fi
	if timeout 90 git push --quiet "$REMOTE" "$c:refs/builds/$c" 2>/dev/null; then
		echo "Saved build $c on GitHub as refs/builds/$c"
	else
		unsaved+=("$c")
	fi
done

if ((${#unsaved[@]})); then
	printf '%s\n' "${unsaved[@]}" > "$PENDING"
	echo "" >&2
	echo "WARNING: could not save these builds on GitHub (no network?):" >&2
	printf '  %s\n' "${unsaved[@]}" >&2
	echo "The install goes ahead. Each is listed in $PENDING and the next deploy retries it;" >&2
	echo "or run tools/save_build_marker.sh once the network is back. Until then a session" >&2
	echo "recorded on this build can only be replayed from this checkout." >&2
	echo "" >&2
else
	rm -f "$PENDING"
fi
exit 0
