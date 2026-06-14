#!/usr/bin/env bash
set -e

# Install only resolvable Debian packages.
install_pkgs() {
    local pkgs=("$@")
    local valid=()
    local bad=()
    local already=()
    local pkg
    local result

    [ ${#pkgs[@]} -eq 0 ] && {
        log "No packages given" >&2
        return 0
    }

    for pkg in "${pkgs[@]}"; do
        # If it is already installed, skip it.
        if dpkg-query -W -f='${Status}\n' "$pkg" 2>/dev/null | grep -q '^install ok installed$'; then
            log "Checking package '${pkg}': already installed"
            already+=("${pkg}")
            continue
        fi

        if apt-get --simulate --option=Dpkg::Use-Pty=0 --no-install-recommends install "${pkg}" >/dev/null 2>&1; then
            valid+=("${pkg}")
            verb="installable"
        else
            bad+=("${pkg}")
            verb="not installable"
        fi

        log "Checking package '${pkg}': ${verb}"
    done

    # Every package is already installed, nothing to do.
    if [ ${#already[@]} -eq ${#pkgs[@]} ]; then
        log "All requested packages are already installed"
        return 0
    fi

    # No valid packages to install.
    if [ ${#valid[@]} -eq 0 ]; then
        log "No installable packages" 2
        return 1
    fi

    apt-get install --yes --no-install-recommends "${valid[@]}" || {
        log "Installation failed: ${valid[*]}" >&2
        return 1
    }

    return 0
}

log() { echo "[$(date --utc '+%Y-%m-%d_%H-%M-%S')]" "$@"; }

#-----------------------------------------------------------------------------------------------------------------------
# Start execution of the script
#-----------------------------------------------------------------------------------------------------------------------
script="${BASH_SOURCE:-${0}}"
script_name="$(basename "${script}")"

# This script is run by root when building the Docker image.
[ "$(id --user)" -ne 0 ] && {
    log "Error: root user must be active to run the script '${script_name}'" 2
    exit 1
}

log "Using system repositories to install Mesa packages"
apt-get update

log "Resolving candidate versions for Mesa packages"

packages=(
    libgl1
    libgl1-mesa-dri
    mesa-utils
    x11-xserver-utils
)

for pkg in "${packages[@]}"; do
    candidate=$(apt-cache policy "${pkg}" | grep Candidate | awk '{print $2}')
    installed=$(dpkg-query -W -f='${Version}' "${pkg}" 2>/dev/null || echo "none")

    log "Package: ${pkg}"
    log "    Installed: ${installed}"
    log "    Candidate: ${candidate}"
done

apt-get update --yes --quiet --quiet || {
    log "apt-get update failed" >&2
    exit 1
}

install_pkgs "${packages[@]}" || {
    log "Installation of Mesa packages failed" >&2
    exit 1
}
