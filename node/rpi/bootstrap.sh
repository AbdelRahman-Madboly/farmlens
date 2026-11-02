#!/usr/bin/env bash
# FarmLens node: one command to install or update from GitHub.
#
#   curl -fsSL https://raw.githubusercontent.com/AbdelRahman-Madboly/farmlens/main/node/rpi/bootstrap.sh | bash
#
# Clones the repo to ~/farmlens (or updates it if it is already there), then
# runs node/rpi/setup.sh. Options after "bash -s --" go to setup.sh, e.g.
#   curl -fsSL .../bootstrap.sh | bash -s -- --ssid "My Phone" --password "secret123"
#
# Everything is inside main(), so bash has read the whole script before any
# command runs. Otherwise a command that reads stdin could swallow the rest of
# the piped script.
set -euo pipefail

main() {
    local repo_url="${FARMLENS_REPO:-https://github.com/AbdelRahman-Madboly/farmlens.git}"
    local dir="${FARMLENS_DIR:-$HOME/farmlens}"

    if ! command -v git >/dev/null; then
        sudo apt-get update -qq < /dev/null
        sudo apt-get install -y -qq git < /dev/null
    fi

    if [ -d "$dir/.git" ]; then
        echo "Updating $dir"
        git -C "$dir" remote set-url origin "$repo_url"
        git -C "$dir" pull --ff-only < /dev/null \
            || echo "git pull failed, continuing with the code already there"
    else
        if [ -e "$dir" ]; then
            local old
            old="$dir.old-$(date +%Y%m%d-%H%M%S)"
            echo "$dir exists but is not a git checkout, moving it to $old"
            mv "$dir" "$old"
        fi
        git clone "$repo_url" "$dir" < /dev/null
    fi

    # Give setup.sh the terminal, not the pipe this script arrived on.
    if (exec < /dev/tty) 2>/dev/null; then
        exec bash "$dir/node/rpi/setup.sh" --no-pull "$@" < /dev/tty
    else
        exec bash "$dir/node/rpi/setup.sh" --no-pull "$@" < /dev/null
    fi
}

main "$@"
