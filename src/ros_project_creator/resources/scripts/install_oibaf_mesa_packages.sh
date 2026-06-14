#!/usr/bin/env bash
set -e

log() { echo "[$(date --utc '+%Y-%m-%d_%H-%M-%S')]" "$@"; }

script="${BASH_SOURCE:-${0}}"
script_name="$(basename "${script}")"

# This script is run by root when building the Docker image.
[ "$(id --user)" -ne 0 ] && {
    log "Error: root user must be active to run the script '${script_name}'" 2
    exit 1
}

log "Adding Oibaf PPA to install Mesa packages"
add-apt-repository -y ppa:oibaf/graphics-drivers

log "Resolving candidate versions for Mesa packages"

packages=(
    mesa-utils
    mesa-vulkan-drivers
    libgl1-mesa-dri
    libgl1-mesa-glx
    libegl1-mesa
)

for pkg in "${packages[@]}"; do
    candidate=$(apt-cache policy "${pkg}" | grep Candidate | awk '{print $2}')
    installed=$(dpkg-query -W -f='${Version}' "${pkg}" 2>/dev/null || echo "none")

    log "Package: ${pkg}"
    log "    Installed: ${installed}"
    log "    Candidate: ${candidate}"
done

log "Installing Mesa packages from Oibaf PPA"

apt-get update --yes --quiet --quiet || {
    log "apt-get update failed" >&2
    exit 1
}

install_pkgs "${packages[@]}" || {
    log "Installation of Mesa packages failed" >&2
    exit 1
}
