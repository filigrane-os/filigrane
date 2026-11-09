#!/bin/bash
# Issues of the fili-niri workflow (.github/workflows/niri.yml), so that a GitHub notification says what to do.
#
#   distro/niri/alert.sh failed PKGVER STATUS RUN_URL   build failed: open the "fili-niri-build" issue, or comment on it
#   distro/niri/alert.sh ok PKGVER                      build published: close the open "fili-niri-build" issue
#   distro/niri/alert.sh upstream VERSION               niri issue of the pin closed: open the "fili-niri-upstream"
#                                                       issue, then say once when niri VERSION (Void's) has the fix
#
# Needs gh (GH_TOKEN) and GITHUB_REPOSITORY (owner/name). FILI_ALERT_DRY=1 prints the changes instead of making them;
# FILI_NIRI_ISSUE=owner/name#N watches another issue (tests).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PIN="$ROOT/distro/niri/upstream"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required (owner/name)}"
BUILD_LABEL=fili-niri-build
UPSTREAM_LABEL=fili-niri-upstream

run() {
    if [ -n "${FILI_ALERT_DRY:-}" ]; then
        printf 'DRY:'; printf ' %q' "$@"; printf '\n'
    else
        "$@"
    fi
}
label() { run gh label create "$1" -R "$REPO" --color "$2" --description "$3" >/dev/null 2>&1 || true; }
open_issue() { gh issue list -R "$REPO" --label "$1" --state open --json number --jq '.[0].number // empty'; }

case "${1:-}" in
    failed)
        pkgver="${2:?PKGVER}"; status="${3:?STATUS}"; url="${4:?RUN_URL}"
        case "$status" in
            3) why="The Filigrane patch no longer applies to this niri release: rebase the \`filigrane\` branch of \
https://github.com/filigrane-os/niri on the new tag, fix the conflicts, push, then update \`ref=\` in \`distro/niri/upstream\`." ;;
            4) why="The patch applies but the package does not build: read the log, fix the \`filigrane\` branch of \
https://github.com/filigrane-os/niri, push, then update \`ref=\` in \`distro/niri/upstream\`." ;;
            0) why="The package was built but its publication failed (download, signature or upload): read the log, \
then run the workflow again (Actions > fili-niri > Run workflow, force)." ;;
            *) why="The workflow failed before or after the build (exit status $status): read the log." ;;
        esac
        body="**$pkgver** was not published. Machines keep the previous fili-niri: they still have the patch, on the \
previous niri release.

$why

Log: $url"
        label "$BUILD_LABEL" d73a4a "fili-niri: build or publication failed"
        n="$(open_issue "$BUILD_LABEL")"
        if [ -n "$n" ]; then
            run gh issue comment "$n" -R "$REPO" --body "$body"
        else
            run gh issue create -R "$REPO" --label "$BUILD_LABEL" --title "fili-niri: $pkgver failed" --body "$body"
        fi ;;
    ok)
        pkgver="${2:?PKGVER}"
        n="$(open_issue "$BUILD_LABEL")"
        [ -z "$n" ] || run gh issue close "$n" -R "$REPO" --comment "$pkgver is built and published."
        ;;
    upstream)
        version="${2:?VERSION}"
        issue="${FILI_NIRI_ISSUE:-$(sed -n 's/^issue=//p' "$PIN" | head -1)}"
        up_repo="${issue%#*}"; up_num="${issue#*#}"
        [ -n "$up_repo" ] && [ -n "$up_num" ] || { echo "alert.sh: issue=owner/name#N is required in $PIN" >&2; exit 1; }
        read -r state reason closed_at < <(gh api "repos/$up_repo/issues/$up_num" \
            --jq '"\(.state) \(.state_reason // "none") \(.closed_at // "none")"')
        [ "$state" = closed ] || { echo "$issue is still open: fili-niri is still needed"; exit 0; }
        # Commit that closed it (null when closed by hand)
        commit="$(gh api --paginate "repos/$up_repo/issues/$up_num/timeline" \
            --jq '.[] | select(.event == "closed") | .commit_id // empty' | tail -1)"
        label "$UPSTREAM_LABEL" 0e8a16 "fili-niri: niri may not need the patch any more"
        n="$(gh issue list -R "$REPO" --label "$UPSTREAM_LABEL" --state all --json number --jq '.[0].number // empty')"
        if [ -z "$n" ]; then
            if [ "$reason" = not_planned ]; then
                what="It was closed as **not planned**: niri will probably not fix it, fili-niri stays needed. Read the \
issue to be sure, then close this one."
            else
                what="It was closed as **$reason**${commit:+ by https://github.com/$up_repo/commit/$commit}. Once that fix \
is in the niri release Void ships, this issue says so, and plain niri can be tried again."
            fi
            run gh issue create -R "$REPO" --label "$UPSTREAM_LABEL" \
                --title "fili-niri: $issue was closed, niri may not need the patch any more" --body "https://github.com/$up_repo/issues/$up_num was closed on ${closed_at%T*}.

$what

To go back to plain niri (\`distro/niri/README.md\`): on the machine, \`sudo xbps-remove -y fili-niri && sudo xbps-install -y niri\`, log out and in, then try the three-monitor dock with the internal panel turned off. If it works: remove the fili-niri block of \`bootstrap.sh\`, \`distro/niri/\` and \`.github/workflows/niri.yml\` (details in \`distro/niri/README.md\`)."
            exit 0
        fi
        [ -n "$commit" ] || exit 0
        # Is the closing commit in the niri release Void ships? (compare: the tag is ahead of or equal to the commit)
        cmp="$(gh api "repos/$up_repo/compare/v$version...$commit" --jq .status 2>/dev/null || echo unknown)"
        case "$cmp" in behind|identical) ;; *) exit 0 ;; esac
        marker="<!-- fili-niri:released -->"
        gh issue view "$n" -R "$REPO" --json comments --jq '.comments[].body' | grep -qF "$marker" && exit 0
        run gh issue reopen "$n" -R "$REPO" >/dev/null 2>&1 || true
        run gh issue comment "$n" -R "$REPO" --body "niri $version, the release Void ships now, contains the fix \
(https://github.com/$up_repo/commit/$commit). Time to try plain niri (see the steps above).
$marker" ;;
    *) echo "usage: distro/niri/alert.sh failed PKGVER STATUS RUN_URL | ok PKGVER | upstream VERSION" >&2; exit 1 ;;
esac
