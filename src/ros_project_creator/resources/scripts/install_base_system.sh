#!/usr/bin/env bash

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

script="${BASH_SOURCE:-${0}}"
script_name="$(basename "${script}")"

log() { echo "[$(date --utc '+%Y-%m-%d_%H-%M-%S')]" "$@"; }

usage() {
    cat <<EOF
Usage:
  ${script_name} TARGET_USER [--help]

Positional arguments:
  TARGET_USER  Target system user name

Options:
  --help          Show this help and exit
EOF
}

# This script must be run by root.
[ "$(id --user)" -ne 0 ] && {
    log "Error: root user must be active to run the script '${script_name}'" >&2
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

TARGET_USER="${1:-}"
target_user_shell="/bin/bash"

[ -z "${TARGET_USER}" ] && {
    log "Error: User not provided" >&2
    exit 1
}

# Update the package list and upgrade all packages to their latest versions.
apt-get update --yes --quiet --quiet || {
    log "apt-get update failed" >&2
    exit 1
}

# Install the apt-utils package first, to avoid warnings when installing packages if this package
# is not installed previously.
install_pkgs apt-utils || {
    log "Installation of package 'apt-utils' failed" >&2
    exit 1
}

# Install the package that allow us to add repositories.
install_pkgs python3-software-properties software-properties-common || {
    log "Installation of packages 'python3-software-properties' and 'software-properties-common' failed" >&2
    exit 1
}

# Now add-apt-repository is available, and we can add the universe repository that contains many
# of the packages we need. Next, the index is updated, and the system is upgraded to ensure all packages are up to date.
add-apt-repository --yes universe || {
    log "Adding universe repository failed" >&2
    exit 1
}

# Upgrade the system to ensure all packages are up to date, now that apt-utils is installed.
apt-get dist-upgrade --yes --no-install-recommends || {
    log "Upgrade of the system failed" >&2
    exit 1
}

#-----------------------------------------------------------------------------------------------------------------------
# Unminimize the system
#-----------------------------------------------------------------------------------------------------------------------

# In a development environment, man pages are useful for understanding commands and their options, so we install them.
# Up to Ubuntu:22.04, the command 'unminimize' was already included in the Ubuntu base image provided by Docker Hub.
# Starting with Ubuntu:24.04, the 'unminimize' command is no longer included by default. However, it is available in the
# system repositories and must be installed before it can be used.

# Check if the command exists; if not, install it if available in apt sources.
# if ! command -v unminimize &>/dev/null; then
#     if apt-cache policy unminimize | grep --quiet 'Candidate:'; then
#         install_pkgs unminimize || {
#             log "Installation of package 'unminimize' failed" >&2
#             exit 1
#         }
#     else
#         log "Warning: Package 'unminimize' is missing in apt sources! Skipping installation"
#     fi
# fi

# Unminimize the system if the command unminimize is available.
# command -v unminimize &>/dev/null && {
#     log "Unminimizing the system"
#     echo y | unminimize || {
#         log "Unminimize command failed" >&2
#         exit 1
#     }
# }

. /etc/os-release

# Install core packages.
packages=(
    apt-rdepends
    automake
    bash-completion
    build-essential
    ca-certificates
    clang
    clang-format
    clang-tidy
    cmake
    cmake-data
    cppcheck
    curl
    gawk
    gdb
    git
    gnupg2
    gosu
    htop
    iproute2
    iputils-ping
    jq
    lcov
    less
    libcppunit-dev
    libtool-bin
    lldb
    lsb-release
    nano
    net-tools
    openssh-client
    procps
    python3-dev
    python3-numpy
    python3-pip
    python3-pytest
    python3-setuptools
    rsync
    sed
    sudo
    tree
    valgrind
    vim
    wget
)

install_pkgs "${packages[@]}" || {
    log "Installation of core packages failed" >&2
    exit 1
}

update-alternatives --install /usr/bin/python python /usr/bin/python3 100

# Set the system timezone to UTC to ensure consistent timekeeping across environments.
# Handle timezone configuration explicitly and separately from the main package installation to avoid tzdata's
# interactive prompts. Even with DEBIAN_FRONTEND=noninteractive, tzdata might still try to launch its dialog if the
# timezone config files are missing or improperly set.
# The /etc/timezone file and the /etc/localtime symlink must be created before installing tzdata.
# The file /etc/localtime must point to a valid file under /usr/share/zoneinfo/, which is provided by the tzdata
# package.

log "Configuring UTC time"
echo "Etc/UTC" >/etc/timezone
ln --symbolic --force "/usr/share/zoneinfo/Etc/UTC" /etc/localtime

if ! dpkg --status tzdata >/dev/null 2>&1; then
    TZ=Etc/UTC DEBIAN_FRONTEND=noninteractive install_pkgs tzdata || {
        log "Installation of package 'tzdata' failed" 2
        exit 1
    }
fi

dpkg-reconfigure --frontend noninteractive tzdata
export TZ=Etc/UTC # In case any command in this script after this line needs it.

log "Configuring locales to en_US.UTF-8"
# Install the locales package to support UTF-8 encoding.
install_pkgs locales || {
    log "Installation of package 'locales' failed" 2
    exit 1
}

tmp="$(mktemp)"
printf 'en_US.UTF-8 UTF-8\n' >"${tmp}"
install --owner=root --group=root --mode=0644 "${tmp}" /etc/locale.gen || {
    log "Failed to install /etc/locale.gen" 2
    exit 1
}
rm -f "${tmp}"

locale-gen en_US.UTF-8 || {
    log "locale-gen failed" 2
    exit 1
}

update-locale LANG=en_US.UTF-8
export LANG=en_US.UTF-8 # In case any command in this script after this line needs it.

#-----------------------------------------------------------------------------------------------------------------------
# Create the requested user
#-----------------------------------------------------------------------------------------------------------------------
# Starting with Ubuntu 24.04, a default non-root user named 'ubuntu' exists with UID 1000 and primary group 'ubuntu'
# with GID 1000.
# Reference: https://bugs.launchpad.net/cloud-images/+bug/2005129

# Check if the user '${TARGET_USER}' exists
if ! getent passwd "${TARGET_USER}" >/dev/null 2>&1; then
    [ "${TARGET_USER}" = root ] && {
        log "Error: User '${TARGET_USER}' should already exist in the image"
        exit 1
    }

    # Create the user with the specified home directory and shell. Home is created physically.
    # when no option --home-dir is specified, the home directory is created in /home/<username>.
    useradd --create-home --shell "${target_user_shell}" "${TARGET_USER}" || {
        log "Error: Failed to create user '${TARGET_USER}'!" 2
        exit 1
    }

    target_user_entry="$(getent passwd "${TARGET_USER}")"
    target_user_id="$(echo "${target_user_entry}" | cut -d: -f3)"
    target_user_pri_group_id="$(echo "${target_user_entry}" | cut -d: -f4)"
    target_user_pri_group="$(getent group "${target_user_pri_group_id}" | cut -d: -f1)"

    log "Created user '${TARGET_USER}' (UID '${target_user_id}') with primary group '${target_user_pri_group}' (GID '${target_user_pri_group_id}')"
else
    # If the user already exists, check if the shell match the requested ones.
    target_user_entry="$(getent passwd "${TARGET_USER}")"
    target_user_id="$(echo "${target_user_entry}" | cut -d: -f3)"
    target_user_pri_group_id="$(echo "${target_user_entry}" | cut -d: -f4)"
    target_user_pri_group="$(getent group "${target_user_pri_group_id}" | cut -d: -f1)"
    current_shell="$(echo "${target_user_entry}" | cut -d: -f7)"

    log "User '${TARGET_USER}' (UID '${target_user_id}') with primary group '${target_user_pri_group}' (GID '${target_user_pri_group_id}') already exists, verifying properties"

    if [ "${current_shell}" != "${target_user_shell}" ]; then
        log "Updating shell of user '${TARGET_USER}' (UID '${target_user_id}') from '${current_shell}' to '${target_user_shell}'"
        usermod --shell "${target_user_shell}" "${TARGET_USER}" || {
            log "Error: Failed to set shell of user '${TARGET_USER}' (UID '${target_user_id}') to '${target_user_shell}'!" >&2
            exit 1
        }
    fi

    # Check if the home directory exists.
    current_home="$(echo "${target_user_entry}" | cut -d: -f6)"

    if [ -z "${current_home}" ]; then
        usermod --home "/home/${TARGET_USER}" "${TARGET_USER}" || {
            log "Error: Failed to set home directory of user '${TARGET_USER}' (UID '${target_user_id}') to '/home/${TARGET_USER}'!" >&2
            exit 1
        }
    elif [ "${current_home}" != "/home/${TARGET_USER}" ]; then
        log "Updating home directory of user '${TARGET_USER}' (UID '${target_user_id}') from '${current_home}' to '/home/${TARGET_USER}'"
        #--move-home: Move the content of the user's home directory to the new location
        usermod --home "/home/${TARGET_USER}" --move-home "${TARGET_USER}" || {
            log "Error: Failed to set home directory of user '${TARGET_USER}' (UID '${target_user_id}') to '/home/${TARGET_USER}'!" >&2
            exit 1
        }
    fi
fi

# Ensure user is member of secondary groups dialout, sudo and video.
# dialout group is used to access serial ports (devices like /dev/ttyusb<x>).
# video group is used to access video devices (like /dev/video<x>, /dev/dri/card<x>).
for group in dialout sudo video; do
    group_entry="$(getent group "${group}")"

    if [ -z "${group_entry}" ]; then
        log "################ Warning: group '${group}' does not exist! ################"
    # Check if the user is not already a member of the group.
    elif ! id -nG "${TARGET_USER}" | grep --quiet --word-regexp "${group}"; then
        group_id="$(echo "${group_entry}" | cut -d: -f3)"
        log "Adding user '${TARGET_USER}' (UID '${target_user_id}') to group '${group}' (GID '${group_id}')"
        usermod --append --groups "${group}" "${TARGET_USER}" || {
            log "Error: Failed to add user '${TARGET_USER}' (UID '${target_user_id}') to group '${group}' (GID '${group_id}')!" >&2
            exit 1
        }
    else
        log "User '${TARGET_USER}' (UID '${target_user_id}') is already a member of group '${group}' (GID '${group_id}')"
    fi
done

# Set password for the non-root user.
# The non-root user can run commands with sudo without a password.
if [ "${TARGET_USER}" != root ]; then
    # Set password equal to username
    log "Setting password for user '${TARGET_USER}' (UID '${target_user_id}') to '${TARGET_USER}'"
    password="${TARGET_USER}"

    if ! echo "${TARGET_USER}:${password}" | chpasswd; then
        log "Error: failed to set password for '${TARGET_USER}' (UID '${target_user_id}')" >&2
        exit 1
    fi

    # The following block is disabled and is left here for reference.
    # It is not recommended to configure passwordless sudo in a Docker image, as it can lead to
    # security issues.

    # Configure passwordless sudo.
    # log "Configuring passwordless sudo for user '${TARGET_USER}' (UID '${target_user_id}')"
    # sudoers_file="/etc/sudoers.d/${TARGET_USER}"
    # echo "${TARGET_USER} ALL=(ALL) NOPASSWD:ALL" >"${sudoers_file}"
    # chmod 0440 "${sudoers_file}"

    # # Check if the sudoers file is valid.
    # if ! visudo --check --file "${sudoers_file}" >/dev/null 2>&1; then
    #     log "Error: Invalid sudoers file '${sudoers_file}'!"
    #     exit 1
    # fi
fi

# It should be /home/${TARGET_USER}, but just in case, we get it from /etc/passwd
target_user_home="$(echo "${target_user_entry}" | cut -d: -f6)"

# Let's verify that the home directory is correct.
[ "${target_user_home}" != "/home/${TARGET_USER}" ] && {
    log "Error: Home directory for user '${TARGET_USER}' is '${target_user_home}' instead of '/home/${TARGET_USER}'" >&2
    exit 1
}

# Create basic folders for configuration and binaries.
dirs_to_create=(
    "${target_user_home}/.config"
    "${target_user_home}/.local/bin"
    "${target_user_home}/.local/lib"
    "${target_user_home}/.local/share"
)

for dir in "${dirs_to_create[@]}"; do
    if [ ! -d "${dir}" ]; then
        log "Creating directory '${dir}'"
        install --directory --mode 755 --owner "${TARGET_USER}" --group "${target_user_pri_group}" "${dir}"
    else
        log "Directory '${dir}' already exists"
    fi
done

# Create the .bashrc file if it does not exist.
if [ ! -s "${target_user_home}/.bashrc" ]; then
    log "File '${target_user_home}/.bashrc' does not exist. Copying file /etc/skel/.bashrc to '${target_user_home}/.bashrc'"
    sudo -H -u "${TARGET_USER}" cp --verbose /etc/skel/.bashrc "${target_user_home}/.bashrc"
fi

#-----------------------------------------------------------------------------------------------------------------------
# Install Python packages for the user that are commonly used for development
#-----------------------------------------------------------------------------------------------------------------------
python_packages=(argcomplete ruff cmake-format pre-commit jinja2 python-rapidjson)

log "Installing Python packages for the user '${TARGET_USER}': ${python_packages[*]}"

pip_args=(--no-cache-dir --disable-pip-version-check)

# Asegurar permisos correctos sobre el home (solo si no es root)
if [ "${TARGET_USER}" != root ]; then
    pip_args+=(--user)

    # The '--break-system-packages', described in PEP 668, was introduced in Python 3.11+ from Debian Bookworm and
    # Ubuntu 24.04 (Noble Numbat), onwards. PEP 668 prevents installing packages with  'pip install --user' in
    # system-managed environments. To work around this, the '--break-system-packages' flag is used to allow the
    # installation of packages in user-managed environments.
    # Ubuntu 22.04 (Jammy), and below, does NOT have this restriction, so 'pip install --user' should work fine.
    if python3 -m pip install --help | grep --quiet 'break-system-packages'; then
        pip_args+=("--break-system-packages")
    fi

    # -H flag is used to set the HOME environment variable to the home directory of the target user.
    # The HOME environment variable is used by pip to determine the location of the user's home directory.
    # The --no-cache-dir flag is used to avoid caching the downloaded packages.
    # The --user flag is used to install the packages in the user's home directory.
    # To avoid warning messages when installing packages we set the environment variable PATH to include
    # the user's local bin directory. Next, an ENV variable is set to include the user's local bin
    # directory in the PATH variable, in the Dockerfile.
    # Build pip install arguments robustly (avoid empty args and expand arrays safely).

    sudo -H -u "${TARGET_USER}" env PATH="${target_user_home}/.local/bin:${PATH}" \
        python3 -m pip install "${pip_args[@]}" "${python_packages[@]}"
else
    python3 -m pip install "${pip_args[@]}" "${python_packages[@]}"
fi

#-----------------------------------------------------------------------------------------------------------------------
# Cleanup
#-----------------------------------------------------------------------------------------------------------------------
log "Removing installation residues from apt cache"
apt-get autoclean
apt-get autoremove --purge -y
apt-get clean
rm -rf /var/lib/apt/lists/* 1>/dev/null 2>&1
