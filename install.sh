#!/usr/bin/env bash
# FarmLens: short install command for the Raspberry Pi.
#
#   curl -fsSL https://raw.githubusercontent.com/AbdelRahman-Madboly/farmlens/main/install.sh | bash
#
# Runs node/rpi/bootstrap.sh, which clones or updates ~/farmlens and runs
# node/rpi/setup.sh. Options after "bash -s --" are passed on.
set -euo pipefail

main() {
    curl -fsSL https://raw.githubusercontent.com/AbdelRahman-Madboly/farmlens/main/node/rpi/bootstrap.sh \
        | bash -s -- "$@"
}

main "$@"
