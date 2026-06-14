#!/usr/bin/env bash

log() { echo "[$(date --utc '+%Y-%m-%d_%H-%M-%S')]" "$@"; }

usage() {
    cat <<EOF
Usage:
  ${script_name} ROS_DISTRO TARGET_USER [--pkgs-dir DIR --help]

Positional arguments:
  ROS_DISTRO      Target ROS2 distribution (e.g., humble, jazzy)
  TARGET_USER     Target system user name

Options:
  --pkgs-dir DIR  Directory containing packages (optional)
  --help          Show this help and exit
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
PARSED=$(getopt -o '' -l pkgs-dir:,help -- "$@") || {
    usage
    exit 1
}

# Replace $@ with the normalized list; eval preserves quoting from getopt’s output
eval set -- "${PARSED}"

# After eval set -- ... we get:
# --pkgs-dir dir -- ROS_DISTRO TARGET_USER
# -- is the end of options marker

pkgs_dir="" # optional

while true; do
    case "${1:-}" in
    --pkgs-dir)
        pkgs_dir="$2"
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

if [ "$#" -lt 2 ]; then
    log "Error: missing required positionals: ROS_DISTRO and TARGET_USER" >&2
    usage
    exit 1
fi

ROS_DISTRO="${1}"
TARGET_USER="${2}"
shift 2

[ "$#" -gt 0 ] && log "Warning: unexpected extra arguments: $*"

[ -z "${ROS_DISTRO}" ] && {
    log "Error: ROS_DISTRO is empty" >&2
    exit 2
}

[ -z "${TARGET_USER}" ] && {
    log "Error: TARGET_USER is empty" >&2
    exit 1
}

target_user_entry="$(getent passwd "${TARGET_USER}")"

[ -z "${target_user_entry}" ] && {
    log "Error: User '${TARGET_USER}' does not exist" 2
    exit 1
}

target_user_home="$(echo "${target_user_entry}" | cut -d: -f6)"

[ -z "${target_user_home}" ] && {
    log "Error: Home directory for user '${TARGET_USER}' could not be determined" >&2
    exit 1
}

[ -n "${pkgs_dir}" ] && [ ! -d "${pkgs_dir}" ] && {
    log "Wargning: pkgs_dir '${pkgs_dir}' does not exist, ignoring it"
    pkgs_dir="" # Ignore it
}

log "Initializing rosdep"

rosdep_sources_dir="/etc/ros/rosdep/sources.list.d"

# To run rosdep init, the file 20-default.list must not exist.

[ -f "${rosdep_sources_dir}/20-default.list" ] && {
    log "File '${rosdep_sources_dir}/20-default.list' already exists, removing it"
    rm --verbose --force "${rosdep_sources_dir}/20-default.list"
}

. /opt/ros/"${ROS_DISTRO}"/setup.bash || {
    log "Error: sourcing ROS setup.bash failed" >&2
    exit 1
}

rosdep init || {
    log "Error: rosdep init failed" >&2
    exit 1
}

log "Executing rosdep update as root. Ignore the warning about running as root"
log "rosdep database ownership will be fixed later"

# If the command 'rosdep update' is run as root, the rosdep database is located at
# /root/.ros/rosdep.
# Ref: rosdep --help
root_home="/root"
root_ros_home="${root_home}/.ros"
# Make sure the ROS home directory exists.
mkdir --parent --verbose "${root_ros_home}"

HOME="${root_home}" ROS_HOME="${root_ros_home}" rosdep update --rosdistro "${ROS_DISTRO}"

# At this point if pkg_dir is set, it is a valid directory.
if [ -n "${pkgs_dir}" ]; then
    log "Installing dependencies with rosdep for packages located at '${pkgs_dir}'"

    # Update cache to ensure the latest package information is available.
    apt-get update

    HOME="${root_home}" ROS_HOME="${root_ros_home}" rosdep install -y --rosdistro "${ROS_DISTRO}" --from-paths "${pkgs_dir}" --ignore-src || {
        log "Error: rosdep install failed" >&2
        exit 1
    }
fi

[ "${TARGET_USER}" = "root" ] && {
    log "TARGET_USER is 'root', no need to move the rosdep databases"
    exit 0
}

# Move rosdep directory to target_user_ros_home.
target_user_id="$(echo "${target_user_entry}" | cut -d: -f3)"
target_user_pri_group_id="$(echo "${target_user_entry}" | cut -d: -f4)"
target_user_ros_home="${target_user_home}/.ros"

if [ ! -d "${target_user_ros_home}" ]; then
    mkdir --verbose --parent "${target_user_ros_home}"
elif [ -d "${target_user_ros_home}/rosdep" ]; then
    # Remove any existing rosdep database in the user home directory.
    rm -rf "${target_user_ros_home}/rosdep" &>/dev/null
fi

log "Moving '${root_ros_home}/rosdep' to '${target_user_ros_home}/rosdep'"
mv --verbose "${root_ros_home}/rosdep" "${target_user_ros_home}/rosdep"

chown --recursive "${target_user_id}:${target_user_pri_group_id}" "${target_user_ros_home}"

log "Removing installation residues from apt cache"
apt-get autoclean
apt-get autoremove --purge -y
apt-get clean
rm -rf /var/lib/apt/lists/* &>/dev/null
