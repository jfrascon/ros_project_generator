#!/usr/bin/env bash

append_keys_to_ignore() {
    [ "$#" -lt 2 ] && {
        log "Error: ${FUNCNAME[0]} requires at least 2 arguments: <file> <key1> [<key2> ...]"
        return 0
    }

    local rosdep_ignored_keys_file="${1}"
    shift

    local keys=("$@")

    [ ! -f "${rosdep_ignored_keys_file}" ] && {
        log "Rosdep ignored keys file '${rosdep_ignored_keys_file}' does not exist"
        return 0
    }

    for key in "${keys[@]}"; do
        # -q, --quiet: Suppress normal output.
        # -x, --line-regexp: Select only those matches that exactly match the whole line.
        # -F, --fixed-strings: Interpret the pattern as fixed strings, not regular expressions.
        if ! grep -qxF "${key}" "${rosdep_ignored_keys_file}"; then
            printf '%s\n' "${key}" >>"${rosdep_ignored_keys_file}"

        fi
    done
}

install_pkgs() {
    local pkgs=("$@")
    local valid=()
    local bad=()
    local already=()
    local pkg
    local verb

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

usage() {
    cat <<EOF
Usage:
  ${script_name} [--ignored-keys-file <file> --pkgs-dir <dir> --ros-distro <distro> --target-user <user> --help]

Options:
  --ignored-keys-file <file> File to store rosdep keys to ignore
  --pkgs-dir <dir>           Directory containing packages
  --ros-distro <distro>      ROS distribution (e.g., humble, jazzy)
  --target-user <user>       Target system user name
  --help                     Show this help and exit
EOF
}

script="${BASH_SOURCE:-${0}}"
script_name="$(basename "${script}")"

# This script is run by root when building the Docker image.
[ "$(id --user)" -ne 0 ] && {
    log "Error: root user must be active to run the script '${script_name}'" >&2
    usage
    exit 1
}

# Normalize arguments with GNU getopt.
# -o ''     -> no short options
# -l ...    -> long options; ":" ⇒ option requires a value
# --        -> end of getopt's own flags; after this, pass script args to parse
# "$@"      -> forward all original args verbatim (keeps spaces/quotes)
# getopt    -> normalizes: reorders options first, splits values, appends a final "--"
# on error  -> exits non-zero; we show usage and exit 2
PARSED=$(getopt -o '' -l ignored-keys-file:,pkgs-dir:,ros-distro:,target-user:,help -- "$@") || {
    usage
    exit 1
}

# Replace $@ with the normalized list; eval preserves quoting from getopt’s output
eval set -- "${PARSED}"

# After eval set -- ... we get:
# --ignored-keys-file file --pkgs-dir dir --ros-distro distro --target-user user --
# -- is the end of options marker

rosdep_ignored_keys_file=""
pkgs_dir=""
ros_distro=""
target_user=""

while true; do
    case "${1:-}" in
    --ignored-keys-file)
        rosdep_ignored_keys_file="$2"
        shift 2
        ;;
    --pkgs-dir)
        pkgs_dir="$2"
        shift 2
        ;;
    --ros-distro)
        ros_distro="$2"
        shift 2
        ;;
    --target-user)
        target_user="$2"
        shift 2
        ;;
    --help)
        usage
        exit 0
        ;;
    --)
        shift
        break
        ;; # end of options, positionals follow
    *)
        usage
        exit 2
        ;;
    esac
done

[ "$#" -gt 0 ] && {
    log "Error: unexpected extra arguments: $*" >&2
    usage
    exit 1
}

. /etc/os-release

# apt-get update --yes --quiet --quiet || {
#     log "Error: apt-get update failed" 2
#     exit 1
# }

# Install the apt-utils package first, to avoid warnings when installing packages if this package
# is not installed previously.
# install_pkgs apt-utils || {
#     log "Installation of package 'apt-utils' failed" >&2
#     exit 1
# }

# Install the package that allow us to add repositories.
# install_pkgs python3-software-properties software-properties-common || {
#     log "Installation of packages 'python3-software-properties' and 'software-properties-common' failed" >&2
#     exit 1
# }

# install_pkgs curl gpg lsb-release || {
#     log "Installation of packages 'curl', 'gpg', and 'lsb-release' failed" >&2
#     exit 1
# }

# + ------------------------+
# | Install system packages |
# + ------------------------+

# IT IS STRONGLY ADVISED TO DECLARE REQUIRED SYSTEM DEPENDENCIES IN THE APPROPRIATE
# PACKAGE'S package.xml FILE UNDER THE <depend> OR <build_depend> OR <exec_depend> TAGS.
# THIS ENSURES PROPER DEPENDENCY MANAGEMENT AND COMPATIBILITY ACROSS DIFFERENT ENVIRONMENTS.

# IF YOU ABSOLUTELY NEED TO INSTALL SYSTEM PACKAGES MANUALLY, ENSURE THAT THEY ARE
# NECESSARY AND CANNOT BE RESOLVED VIA rosdep. IMPROPER USE OF THIS SCRIPT FOR
# SYSTEM PACKAGE INSTALLATION MAY LEAD TO INCONSISTENCIES IN DEPENDENCY RESOLUTION.

#packages=(
# pkg1
# pkg2
# pkg3
#)

# install_pkgs "${packages[@]}" || {
#    log "Error: Failed to install system packages" >&2
#    exit 1
#}

# + ---------------------+
# | Install ROS packages |
# + ---------------------+

# IT IS STRONGLY ADVISED TO DECLARE REQUIRED ROS DEPENDENCIES IN THE APPROPRIATE PACKAGE'S
# package.xml FILE UNDER THE <depend>, <build_depend>, OR <exec_depend> TAGS.
# THIS ENSURES PROPER DEPENDENCY MANAGEMENT, AUTOMATIC RESOLUTION VIA rosdep,
# AND COMPATIBILITY ACROSS DIFFERENT ENVIRONMENTS.

# Check if ${ROS_DISTRO} is installed properly, otherwise abort the installation.
# found_ros_distro="$(dpkg-query -W -f='${binary:Package}\n' 'ros-*-ros-core' | cut -d'-' -f2 | paste -sd' ' -)"
# echo "ROS_DISTRO(s) found: '${found_ros_distro}'"
# num_distros=$(echo "${found_ros_distro}" | wc -w)

# [ "${num_distros}" -eq 0 ] && {
#     log "No ROS distribution found. Please install a ROS distribution before running the script '${script_name}'" >&2
#     exit 1
# }

# [ "${num_distros}" -gt 1 ] && {
#     log "Error: Multiple ROS distributions detected" >&2
#     exit 1
# }

# [ -n "${ros_distro}" ] && [ "${ros_distro}" != "${found_ros_distro}" ] && {
#     log "Error: Mismatch between the specified ROS distribution '${ros_distro}' and the installed one '${found_ros_distro}'" >&2
#     exit 1
# }

# ...

# install_pkgs ...

# +--------------------------------------------------------------------------------------------------------------------+

# +---------------------+
# | Custom instructions |
# +---------------------+

# apt-get autoclean
# apt-get autoremove --purge -y
# apt-get clean
# rm -rf /var/lib/apt/lists/* 1>/dev/null 2>&1
