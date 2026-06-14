#!/usr/bin/env bash

log() { echo "[$(date --utc '+%Y-%m-%d_%H-%M-%S')]" "$@"; }

usage() {
    cat <<EOF
Usage:
  ${script_name} TARGET_USER [--help]

Positional arguments:
  TARGET_USER     Target system user name

Options:
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

# Pre-scan: show help if present in any position.
for arg in "$@"; do
    case "$arg" in
    --help | -h)
        usage
        exit 0
        ;;
    esac
done

if [ "$#" -lt 1 ]; then
    log "Error: missing required positional argument TARGET_USER" >&2
    usage
    exit 1
fi

TARGET_USER="${1:-}"
shift

[ "$#" -gt 0 ] && log "Warning: unexpected extra arguments: $*"

[ -z "${TARGET_USER}" ] && {
    log "Error: --target-user is required" >&2
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

root_home="/root"

[ ! -d "${root_home}" ] && {
    log "Error: Root home directory '${root_home}' does not exist" >&2
    exit 1
}

root_ros_home="/root/.ros"
root_colcon_home="/root/.colcon"

# Make sure both paths above exist.
mkdir --parent --verbose "${root_ros_home}"
mkdir --parent --verbose "${root_colcon_home}"

# Download the colcon mixin and metadata repositories.
log "Installing colcon mixin and metadata for ROS2"
log "Ownership of colcon databases will be fixed later "

HOME="${root_home}" ROS_HOME="${root_ros_home}" colcon mixin add default https://raw.githubusercontent.com/colcon/colcon-mixin-repository/master/index.yaml
HOME="${root_home}" ROS_HOME="${root_ros_home}" colcon mixin update default
HOME="${root_home}" ROS_HOME="${root_ros_home}" colcon metadata add default https://raw.githubusercontent.com/colcon/colcon-metadata-repository/master/index.yaml
HOME="${root_home}" ROS_HOME="${root_ros_home}" colcon metadata update default

[ "${TARGET_USER}" = "root" ] && {
    log "TARGET_USER is 'root', no need to move colcon databases"
    exit 0
}

# Move the rosdep databases to the user home directory, if the TARGET_USER is non root.
target_user_id="$(echo "${target_user_entry}" | cut -d: -f3)"
target_user_pri_group_id="$(echo "${target_user_entry}" | cut -d: -f4)"
target_user_home="$(echo "${target_user_entry}" | cut -d: -f6)"
target_user_colcon_home="${target_user_home}/.colcon"
[ -d "${target_user_colcon_home}" ] && rm -rf "${target_user_colcon_home}" &>/dev/null

log "Moving COLCON_HOME from '${root_colcon_home}' to '${target_user_colcon_home}'"
mv --verbose "${root_colcon_home}" "${target_user_colcon_home}"

chown --recursive "${target_user_id}:${target_user_pri_group_id}" "${target_user_colcon_home}"
