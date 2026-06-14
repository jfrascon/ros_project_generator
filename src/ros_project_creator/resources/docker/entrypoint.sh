#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status.
# set -e

# Variables HOST_UID and HOST_UPGID are defined in CLI or docker-compose.yml file.

LOG_FILE="/tmp/elog.log"
REMEMBER_MSG="The user-group adaptation is only possible if the selected user is 'root' (uid: 0) and both variables, HOST_UID and HOST_UPGID, are defined with a non-empty integer value greater than 1000"

add_render_group_to_user() {
    local user="${1}"

    # Check if the user with name ${user} exist.
    if ! getent passwd "${user}" >/dev/null; then
        return 1
    fi

    # If the user (no root) wants to access the devices /dev/dri/renderD*, the user must be in the
    # group of that device.

    # Iterate over every render node present in /dev/dri.
    for dev in /dev/dri/renderD*; do
        [ -e "${dev}" ] || continue # glob might not expand

        gid="$(stat -c %g "${dev}")" # numeric GID of the device

        if getent group "${gid}" >/dev/null; then
            group="$(getent group "${gid}" | cut -d: -f1)"

            if [ "${group}" != "render" ]; then
                log INFO "Using existing group id '${gid}', named '${group}' (different from 'render') for '${dev}', no problem"
            fi
        else
            group="render_${gid}"
            log INFO "Creating group '${group}' (GID ${gid}) for device ${dev}"
            groupadd --system --gid "${gid}" "${group}"
        fi

        # Add the group to the user ${user}.
        log INFO "Adding user '${user}' to group '${group}' (GID ${gid}) for ${dev}"
        usermod -aG "${gid}" "${user}"
    done
}

# Find first integer that can be used as uid and gid above >= 2000
find_free_id() {
    awk -F: '
        NR==FNR { uids[$3]=1; next }
        { uids[$3]=1 }
        END { for(i=2000;i<60000;++i) if(!(i in uids)) { print i; break } }
    ' /etc/passwd /etc/group
}

generate_unique_name() {
    local type="${1}"     # "user" or "group"
    local prefix="${2:-}" # optional prefix
    local getent_target
    local candidate

    case "${type}" in
    user)
        getent_target="passwd"
        ;;
    group)
        getent_target="group"
        ;;
    *)
        echo "Error: unknown type '${type}'. Use 'user' or 'group'." >&2
        return 1
        ;;
    esac

    while :; do
        candidate="${prefix}$(tr -dc 'a-z' </dev/urandom | head -c 8)"
        if ! getent "${getent_target}" "${candidate}" >/dev/null 2>&1; then
            echo "${candidate}"
            return
        fi
    done
}

log() {
    local level="INFO"
    local out_fd=1

    if [ "$#" -gt 0 ]; then
        case "$1" in
        INFO)
            level="INFO"
            shift
            out_fd=1 # stdout
            ;;
        ERROR)
            level="ERROR"
            shift
            out_fd=2 # stderr
            ;;
        *)
            level="INFO"
            out_fd=1 # stdout
            ;;
        esac
    fi

    local ts="$(date --utc '+%Y-%m-%d_%H-%M-%S')"
    local line="[${ts}] [${level}] $*"

    [ -n "${LOG_FILE-}" ] && printf '%s\n' "${line}" >>"${LOG_FILE}"

    printf '%s\n' "${line}" >&"${out_fd}"
}

print_banner() {
    local message="${1}"
    local fd="${2:-1}"          # default to 1 (stdout) if not provided
    local border_char="${3:--}" # default to '=' if not provided

    # Validate that fd is either 1 (stdout) or 2 (stderr)
    if [[ "${fd}" != "1" && "${fd}" != "2" ]]; then
        fd=1
    fi

    local line=" ${message} "
    local len=${#line}

    printf "%s\n" "$(printf "%${len}s" | tr ' ' "${border_char}")" >&"${fd}"
    printf "%s\n" "${line}" >&"${fd}"
    printf "%s\n" "$(printf "%${len}s" | tr ' ' "${border_char}")" >&"${fd}"
}

#---------------------------------------------------------------------------------------------------
# Script execution
#---------------------------------------------------------------------------------------------------
current_user_id="$(id --user)"
current_user_entry="$(getent passwd "${current_user_id}" 2>/dev/null)"

[ -z "${current_user_entry}" ] && echo "Error: User with id '${current_user_id}' does not exist" >&2 && exit 1

current_user="$(echo "${current_user_entry}" | cut -d: -f1)"
current_user_pri_group_id="$(echo "${current_user_entry}" | cut -d: -f4)"
current_user_pri_group="$(getent group "${current_user_pri_group_id}" | cut -d: -f1)"
current_user_home="$(echo "${current_user_entry}" | cut -d: -f6)"

script="${BASH_SOURCE:-${0}}"
script_name="$(basename "${script}")"

log INFO "Executing script '${script}' with user '${current_user}' (UID '${current_user_id}') and primary group '${current_user_pri_group}' (UPGID '${current_user_pri_group_id}')"

# If the variables HOST_UID and HOST_UPGID DO NOT EXIST (not talking about being empty), the container is started with
# the current_user, which can be root or a non-root user.
# The current user is the selected based on priorities:
# Option 1: '--user' in the 'docker container run --user <user>' is more important than the last user activated in the
#           Dockerfile.
# Option 2: 'user' field in the docker-compose file is more important than the last user activated in the Dockerfile.
# Option 3: If no docker run command or docker-compose file is used to start the container, the active user is the last
#           user activated in the Dockerfile.
# When the variables HOST_UID and HOST_UPGID are not defined the user-group adaptation is not possible.
if [ -z "${HOST_UID+x}" ] && [ -z "${HOST_UPGID+x}" ]; then
    # If the curret_user is root, no need to added render group to root user.
    # If the current_user is not root, we can add the render group to the current_user.
    # Either way, we can't use the 'add_render_group_to_user' function in this case.

    [ -s "${current_user_home}/.environment.sh" ] && . "${current_user_home}/.environment.sh"
    exec "$@"
fi

# Cases we may have here:
# 1. Both variables, HOST_UID and HOST_UPGID, exist (they can be empty or non-empty).
# 2. HOST_UID exists (empty or non-empty) and HOST_UPGID does not exist.
# 3. HOST_UID does not exist and HOST_UPGID exists (empty or non-empty).

# The only allowed case is:
# Both variables HOST_UID and HOST_UPGID exist and have a non-empty integer value greater than 1000.

# From now on, we must filter out the cases that do not fit the allowed case.

if [ -z "${HOST_UID}" ]; then
    log ERROR "Error: HOST_UID variable does not exist or is empty. Either HOST_UID and HOST_UPGID are undefined or both are defined with non-empty integer values greater than 1000"

    if [ "${current_user_id}" -ne 0 ]; then
        log INFO "${REMEMBER_MSG}"
    fi

    exit 1
fi

if [ -z "${HOST_UPGID}" ]; then
    log ERROR "Error: HOST_UPGID variable does not exit or is empty. Either HOST_UID and HOST_UPGID are undefined or both are defined with non-empty integer values greater than 1000"

    if [ "${current_user_id}" -ne 0 ]; then
        log INFO "${REMEMBER_MSG}"
    fi

    exit 1
fi

# From here on, both enviroment variables, HOST_UID and HOST_UPGID, are defined and have a non-empty value.
# Check if both variables have an integer value.
if ! [[ "${HOST_UID}" =~ ^-?[0-9]+$ ]]; then
    log ERROR "Error: HOST_UID variable must be an integer greater than 1000, given '${HOST_UID}'"

    if [ "${current_user_id}" -ne 0 ]; then
        log INFO "${REMEMBER_MSG}"
    fi

    exit 1
fi

if ! [[ "${HOST_UPGID}" =~ ^-?[0-9]+$ ]]; then
    log ERROR "Error: HOST_UPGID variable must be an integer greater than 1000, given '${HOST_UPGID}'"

    if [ "${current_user_id}" -ne 0 ]; then
        log INFO "${REMEMBER_MSG}"
    fi

    exit 1
fi

# To exeute user-group adaptation it is required that the user in the host system, defined by
# the variables, HOST_UID and HOST_UPGID, has values greater than 1000 in these variables. Integer
# values lower than 1000 are reserve for the operating system.
if [ "${HOST_UID}" -lt 1000 ] || [ "${HOST_UPGID}" -lt 1000 ]; then
    log ERROR "Error: HOST_UPGID ('${HOST_UPGID}') and HOST_UID ('${HOST_UID}') must be greater than 1000"

    if [ "${current_user_id}" -ne 0 ]; then
        log INFO "${REMEMBER_MSG}"
    fi

    exit 1
fi

# If the execution reaches this point, both variables, HOST_UID and HOST_UPGID, exist and have a non-empty integer value
# greater than 1000.
log INFO "Current user: ${current_user}' (UID '${current_user_id}'), HOST_UID: ${HOST_UID}, HOST_UPGID: ${HOST_UPGID}"

if [ "${current_user_id}" -ne 0 ]; then
    # Current user is not root, so no user-group adaptation is possible, even if both variables, HOST_UID and
    # HOST_UPGID, exist and have a non-empty integer value greater than 1000.
    log INFO "${REMEMBER_MSG}"
    [ -s "${current_user_home}/.environment.sh" ] && . "${current_user_home}/.environment.sh"
    exec "$@"
fi

# If the execution reaches this point, the current user is root and both variables, HOST_UID and HOST_UPGID, are defined
# with an integer value greaer than 1000, so user-group adaptation is possible.
# Adapt the user ${IMAGE_MAIN_USER} to use the id ${HOST_UID} and the primary group id ${HOST_UPGID}.

# Check if the enviroment variable 'IMAGE_MAIN_USER' exists and it is not empty.
if [ -z "${IMAGE_MAIN_USER}" ]; then
    log ERROR "Error: IMAGE_MAIN_USER variable not set"
    exit 1
fi

main_user_entry="$(getent passwd "${IMAGE_MAIN_USER}" 2>/dev/null)"

# Check if the user with name ${IMAGE_MAIN_USER} exists in the image.
if [ -z "${main_user_entry}" ]; then
    print_banner "Error: User '${IMAGE_MAIN_USER}' does not exist" 2 "!"
    exit 1
fi

main_user_id="$(echo "${main_user_entry}" | cut -d: -f3)"
main_user_home="$(echo "${main_user_entry}" | cut -d: -f6)"
main_user_pri_group_id="$(echo "${main_user_entry}" | cut -d: -f4)"
main_user_pri_group="$(getent group "${main_user_pri_group_id}" | cut -d: -f1)"

if [ ! -d "${main_user_home}" ]; then
    log ERROR "Error: The home directory '${main_user_home}' does no exist"
    exit 1
fi

# Check if the primary group id for the user '${IMAGE_MAIN_USER}' exists in the system.
if [ -z "${main_user_pri_group}" ]; then
    log ERROR "Error: Group '${main_user_pri_group_id}' does not exist (Primary group of user '${IMAGE_MAIN_USER}')"
    exit 1
fi

# If the user ${IMAGE_MAIN_USER} is root, no need to adapt the user and group ids.
if [ "${IMAGE_MAIN_USER}" = "root" ]; then
    log INFO "The IMAGE_MAIN_USER in the Docker image is root, no user-group adaption is possible. Variables HOST_UID and HOST_UPGID are discarded"
    [ -s "${main_user_home}/.environment.sh" ] && . "${main_user_home}/.environment.sh"
    exec "$@"
fi

# The user ${IMAGE_MAIN_USER} is not root, we need to adapt the id and pri_gid of this user to the provided HOST_UID and
# HOST_UPGID.

log INFO "User '${IMAGE_MAIN_USER}' has UID '${main_user_id}' and primary group '${main_user_pri_group}' (GID '${main_user_pri_group_id}') (${main_user_entry})"

user_entry="$(getent passwd "${HOST_UID}")"

# Check if the id ${HOST_UID} is not used by any user in the Docker image.
if [ -z "${user_entry}" ]; then
    # If the execution reaches this point, it means that the id ${HOST_UID} is not in use.
    # We can set the id ${HOST_UID} to the user ${IMAGE_MAIN_USER}.
    log INFO "Setting id '${HOST_UID}' to user '${IMAGE_MAIN_USER}'"
    usermod --uid "${HOST_UID}" "${IMAGE_MAIN_USER}"
    log INFO "($(getent passwd "${IMAGE_MAIN_USER}"))"

    # Update the variable to reflect the new user id.
    main_user_id="${HOST_UID}"
# Conflicting case:
# Check if the id ${HOST_UID} is already in use by another user that is not the user ${IMAGE_MAIN_USER}.
# If this is the case, it is not so obvious which action to take.
# Option 1:
# - Step 1. Find a free id and assign it to the user that is currently using the id ${HOST_UID}. This way, the id
# ${HOST_UID} will be available to be set to the user ${IMAGE_MAIN_USER}.
# - Step 2. Set the ownership of the home directory of the user that was using the id ${HOST_UID} to reflect the new id.
# - Step 3. Set the id ${HOST_UID} to the user ${IMAGE_MAIN_USER}.
# Option 2: Throw an error and exit, leaving the user the responsibility to solve the conflict. We give the user
# the responsibility to investigate which user is using the id ${HOST_UID} and decide what to do. The user can
# always use the steps in Option 1 to solve the conflict manually, if needed.
elif [ "${HOST_UID}" != "${main_user_id}" ]; then
    # If the execution reaches this point, it means that the id ${HOST_UID} is in use in the Docker image by another
    # user that is not the user ${IMAGE_MAIN_USER}.

    # Option 2 is implemented here.
    # Option 2 is what vscode.remote-containers extension does when usin the field "updateRemoteUserUID": true.
    # Observing the logs of the extension you see it tries to change the user id of the user ${IMAGE_MAIN_USER} to
    # ${HOST_UID}, and it will fail if the id ${HOST_UID} is already in use by another user.
    # Check the Dockerfile 'updateUID.Dockerfile' in your vscode installation:
    # ${HOME}/.vscode/extensions/ms-vscode-remote.remote-containers-x.y.z/scripts/updateUID.Dockerfile
    # The difference is this script fails with a clear error message, while the extension does not fail, but it
    # starts the container with ${IMAGE_MAIN_USER} but with the original user id, not with ${HOST_UID}, which will give
    # you permission problems when accessing files created in the host system with the user that has the id ${HOST_UID}
    # and viceversa.
    log ERROR "Error: The id '${HOST_UID}' is already in use by user '$(echo "${user_entry}" | cut -d: -f1)' (${user_entry})"
    log ERROR "Either change the HOST_UID variable to another value or solve the conflict manually"
    exit 1

    # Option 1 is implemented here for reference.
    # We need to set the id ${HOST_UID} to the user ${IMAGE_MAIN_USER}.
    # user="$(echo "${user_entry}" | cut -d: -f1)"
    # user_pri_group_id="$(echo "${user_entry}" | cut -d: -f4)"
    # user_home="$(echo "${user_entry}" | cut -d: -f6)"
    # log INFO "The user '${user}' is using the id '${HOST_UID}' (${user_entry})"

    # To do this, first, we find a free id and assign it to the user ${user}, that currently has the id ${HOST_UID}.
    # This way, the id ${HOST_UID} will be available to be set to the user ${IMAGE_MAIN_USER}.
    # new_user_id="$(find_free_id)"
    # log INFO "Setting id '${new_user_id}' to user '${user}'"
    # usermod --uid "${new_user_id}" "${user}"
    # log INFO "($(getent passwd "${user}"))"

    # Since the user ${user} has a different id now, just in case, we need to change the
    # ownership of the home directory of the user ${user} to reflect the new id.
    # log INFO "Setting ownership of home directory '${user_home}' to '${new_user_id}:${user_pri_group_id}'"
    # chown -R "${new_user_id}":"${user_pri_group_id}" "${user_home}"

    # Now we can set the id ${HOST_UID} to the user ${IMAGE_MAIN_USER}.
    # log INFO "Setting id '${HOST_UID}' to user '${IMAGE_MAIN_USER}'"
    # usermod --uid "${HOST_UID}" "${IMAGE_MAIN_USER}"
    # log INFO "($(getent passwd "${IMAGE_MAIN_USER}"))"
fi

# The case where "${HOST_UID}" = "${main_user_id}" means that the user ${IMAGE_MAIN_USER} is already using the id
# ${HOST_UID}, so no action is needed.

# From here on, the user ${IMAGE_MAIN_USER} has the id ${HOST_UID}.

# Detect if a group in the Docker image is already using the id ${HOST_UPGID}.
group_entry="$(getent group "${HOST_UPGID}")"

# Check if the id ${HOST_UPGID} is not in use.
if [ -z "${group_entry}" ]; then
    # Since the id ${HOST_UPGID} is not in use, we can assign that id to the existing group in the Docker image with
    # name ${main_user_pri_group}.
    log INFO "Group id '${HOST_UPGID}' is not in use in the image"
    log INFO "Setting id '${HOST_UPGID}' to group '${main_user_pri_group}'"
    groupmod --gid "${HOST_UPGID}" "${main_user_pri_group}"

    # Next, we need to set the primary group id of the user ${IMAGE_MAIN_USER} to the group id ${HOST_UPGID}.
    # We do this action outise this if-elif structure.
# Tricky case:
# Same situation as with the user id. Check if the id ${HOST_UPGID} is already in use by another group that is not the
# primary group of the user ${IMAGE_MAIN_USER}.
# In this occasion, the solution is not so radical as with the user id. Let's see below.
elif [ "${HOST_UPGID}" != "${main_user_pri_group_id}" ]; then
    # If the execution reaches this point, it means that the id ${HOST_UPGID} is in use in the Docker image by another
    # group that is not the group ${main_user_pri_group}.
    group="$(echo "${group_entry}" | cut -d: -f1)"
    log INFO "The group '${group}' is using the id '${HOST_UPGID}' (${group_entry})"

    # Since the id ${HOST_UPGID} is in use by another existing group in the Docker image, we are set the name
    # ${main_user_pri_group} to the group with id ${HOST_UPGID}.

    # First, we need the name ${main_user_pri_group} to be available to be set to the group with id ${HOST_UPGID}.
    # To do this, we need to set a new unique name to the group with id ${main_user_pri_group_id}.
    new_group_name="$(generate_unique_name group "${main_user_pri_group}_")"
    log INFO "Setting name '${new_group_name}' to group '${main_user_pri_group_id}'. Name '${main_user_pri_group}' will be available'"
    groupmod --new-name "${new_group_name}" "${main_user_pri_group}"
    log INFO "($(getent group "${new_group_name}"))"

    # Now, we can set the name ${main_user_pri_group} to the group with id ${HOST_UPGID}.
    log INFO "Setting name '${main_user_pri_group}' to group '${HOST_UPGID}'"
    groupmod --new-name "${main_user_pri_group}" "${group}"
    log INFO "($(getent group "${main_user_pri_group}"))"

    # Next, we need to set the primary group id of the user ${IMAGE_MAIN_USER} to the group id ${HOST_UPGID}.
    # We do this action outise this if-elif structure.
fi

# The case where "${HOST_UPGID}" = "${main_user_pri_group_id}" means that the primary group id of the user
# ${IMAGE_MAIN_USER} is already set to the group with id ${HOST_UPGID}, so no need to change it.

log INFO "Setting primary group id '${HOST_UPGID}' to user '${IMAGE_MAIN_USER}'"
usermod --gid "${HOST_UPGID}" "${IMAGE_MAIN_USER}"
log INFO "($(getent passwd "${IMAGE_MAIN_USER}"))"

# It is still pending to update the ownership of the home directory of the user ${IMAGE_MAIN_USER} to the group id
# ${HOST_UPGID}. This action will be done at the end of the script.

# Now, we set the ownership of the home directory of the user ${IMAGE_MAIN_USER}, to be sure that, independtly of the
# previous operations, the home directory of the user ${IMAGE_MAIN_USER} is owned by the user ${IMAGE_MAIN_USER} and the
# primary group of the user ${IMAGE_MAIN_USER}.
# At this point, the user ${IMAGE_MAIN_USER} has the id ${HOST_UID} and the primary group id ${HOST_UPGID}, so we can
# use these values to set the ownership of the home directory.
log INFO "Setting ownership of home directory '${main_user_home}' to '${HOST_UID}:${HOST_UPGID}'"
chown -R "${HOST_UID}":"${HOST_UPGID}" "${main_user_home}"

add_render_group_to_user "${IMAGE_MAIN_USER}"

# We use gosu here to start a new session with the new user and group ids.
exec gosu "${IMAGE_MAIN_USER}" bash -c '
    [ -s "${HOME}/.environment.sh" ] && . "${HOME}/.environment.sh"
    exec "$@"
' bash "$@"
