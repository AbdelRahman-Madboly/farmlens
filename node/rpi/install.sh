#!/usr/bin/env bash
# Kept so the old command still works. setup.sh installs and updates.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/setup.sh" "$@"
