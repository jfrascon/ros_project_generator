#!/usr/bin/env bash
set -e

log() { echo "[$(date --utc '+%Y-%m-%d_%H-%M-%S')]" "$@"; }

script="${BASH_SOURCE:-${0}}"
script_name="$(basename "${script}")"

# This script is run by root when building the Docker image.
[ "$(id --user)" -ne 0 ] && {
    log "Error: root user must be active to run the script '${script_name}'" >&2
    exit 1
}

log "Using system repositories to install locked versions of Mesa packages"
apt-get update

# Puedes editar las versiones concretas según las que hayan funcionado bien para tu caso de uso.
# Estas versiones son solo ejemplos y deben ser revisadas antes de usar.
packages=(
    mesa-utils=8.4.0-1ubuntu1
    mesa-vulkan-drivers:amd64=23.2.1-1ubuntu3.1~22.04.3
    libgl1-mesa-dri:amd64=23.2.1-1ubuntu3.1~22.04.3
    libgl1-mesa-glx:amd64=23.0.4-0ubuntu1~22.04.1
    libegl1-mesa:amd64=23.0.4-0ubuntu1~22.04.1
)

log "Candidate versions will be forced:"

for entry in "${packages[@]}"; do
    pkg="${entry%%=*}"
    ver="${entry##*=}"

    log "Package: ${pkg}"
    log "    Version: ${ver}"
done

log "Installing Mesa packages"

apt-get update --yes --quiet --quiet || {
    log "apt-get update failed" >&2
    exit 1
}

install_pkgs "${packages[@]}" || {
    log "Installation of locked Mesa packages failed" >&2
    exit 1
}
