# ROS PROJECT CREATION TOOL

- [ROS PROJECT CREATION TOOL](#ros-project-creation-tool)
  - [Description](#description)
  - [Installation of the package `ros_project_creator` as a user](#installation-of-the-package-ros_project_creator-as-a-user)
    - [Prerequisites](#prerequisites)
    - [Installation Steps](#installation-steps)
  - [Running the scripts inside the package `ros_project_creator` as a user](#running-the-scripts-inside-the-package-ros_project_creator-as-a-user)
    - [**create\_ros\_project**](#create_ros_project)
    - [**create\_vscode\_project**](#create_vscode_project)
  - [Uninstalling the package `ros_project_creator` as a user](#uninstalling-the-package-ros_project_creator-as-a-user)
  - [Installation of the package `ros_project_creator` as a developer](#installation-of-the-package-ros_project_creator-as-a-developer)
    - [1. Install `uv`](#1-install-uv)
    - [2. Install the package `ros_project_creator` using `uv`](#2-install-the-package-ros_project_creator-using-uv)
    - [3. Verify the installation of the package `ros_project_creator`](#3-verify-the-installation-of-the-package-ros_project_creator)
  - [Uninstalling the package `ros_project_creator` as a developer](#uninstalling-the-package-ros_project_creator-as-a-developer)
  - [Notes on project layout](#notes-on-project-layout)
  - [Contact](#contact)

## Description

The `ros_project_creator` package provides scripts for creating and configuring ROS projects and setting up VSCode development environments.

## Installation of the package `ros_project_creator` as a user

The package `ros_project_creator` is installed using **[`uv`](https://docs.astral.sh/uv/)**, an extremely fast Python package and project manager written in Rust. `uv` provides better dependency resolution, caching, and performance compared to traditional `pip`.

This tool helps you create reproducible ROS projects with Docker and VSCode integration.

### Prerequisites

* Linux (tested on Ubuntu)
* Git installed
* Python ≥ 3.8
* `curl` installed
* A Bash or Zsh shell

### Installation Steps

1. **Clone this repository** (if you haven't already):

   ```bash
   git clone https://github.com/jfrascon/ros_project_creator.git
   cd ros_project_creator
   ```

2. **Install `uv` and `uvx`**
   These tools are used to manage isolated Python environments and install packages cleanly:

   ```bash
   mkdir -vp "${HOME}/.local/bin"
   curl -LsSf https://astral.sh/uv/install.sh | env XDG_BIN_HOME="${HOME}/.local/bin" UV_NO_MODIFY_PATH=1 sh
   ```

3. **Add `${HOME}/.local/bin` to your shell's `PATH`**
   (Only once, if not already present):

   ```bash
   # For Bash
   echo '[[ -d "${HOME}/.local/bin" && ":${PATH}:" != *":${HOME}/.local/bin:"* ]] && export PATH="${HOME}/.local/bin:${PATH}"' >> ~/.bashrc

   # For Zsh
   echo '[[ -d "${HOME}/.local/bin" && ":${PATH}:" != *":${HOME}/.local/bin:"* ]] && export PATH="${HOME}/.local/bin:${PATH}"' >> ~/.zshrc
   ```

4. **Install `ros_project_creator` locally**:

   This installs the tool under `${HOME}/.local`:

   ```bash
   uv pip install --system --prefix "${HOME}/.local" ./ros_project_creator
   ```

5. **Restart your terminal**:

   Close and reopen your terminal to apply changes to your environment.

Check if the scripts inside the package `ros_project_creator` are found in your system.

```sh
pip list --user | grep ros_project_creator
ros_project_creator        1.0.0

which create_ros_project
~/.local/bin/create_ros_project

which create_vscode_project
~/.local/bin/create_vscode_project
```

## Running the scripts inside the package `ros_project_creator` as a user

Once installed, you can run the scripts inside the package `ros_project_creator` directly from the command line.

### **create_ros_project**

This script creates a structured ROS project based on predefined templates.

```sh
> create_ros_project -h
usage: create_ros_project [--img-id IMG_ID] [--use-base-img-entrypoint] [--no-environment] [--use-host-nvidia-driver]
                          [--no-vscode] [--no-pre-commit] [--no-console-log] [--log-file LOG_FILE]
                          [--log-level LOG_LEVEL] [-h]
                          project_id project_dir base_img image_main_user ros_distro

Creates a new ROS project based on templates

positional arguments:
  project_id                Short, descriptive project identifier for internal reference (e.g. 'robproj')
  project_dir               Path where the project will be created (e.g. '~/projects/robproj')
  base_img                  Base Docker image to use (e.g. 'eutrob/eut_ros:humble')
  image_main_user           Active user to use in the resulting Docker image
  ros_distro                ROS distro to use: humble (ros2), jazzy (ros2)

options:
  --img-id IMG_ID           ID of the resulting Docker image (e.g. 'robproj:humble'). If not set, defaults to '<project-id>:latest'
  --use-base-img-entrypoint
                            Inherit the base image's entrypoint (if any)
  --no-environment          Do not create an environment script (use only if you provide your own)
  --use-host-nvidia-driver
                            Use host's NVIDIA driver inside the container
  --no-vscode               Do not create VSCode project
  --no-pre-commit           Do not use pre-commit hooks
  --no-console-log          Disable logging to console. Console logging is enabled by default
  --log-file LOG_FILE       File to log output
  --log-level LOG_LEVEL     Logging level (Default is DEBUG)
  -h, --help                Show this help message and exit
```

### **create_vscode_project**

This script initializes a VSCode workspace.

```sh
> create_vscode_project -h
usage: create_vscode_project [-h] [--image-main-user-home IMAGE_MAIN_USER_HOME] [--use-host-nvidia-driver]
                             [--no_console_log] [--log_file LOG_FILE] [--log_level LOG_LEVEL]
                             project_id ros_distro img_id image_main_user workspace_dir img_workspace_dir

Creates a new VSCode project based on templates

positional arguments:
  project_id            Short project identifier (e.g. 'robproj')
  ros_distro            ROS distro to use: humble (ros2), jazzy (ros2)
  img_id                ID of the Docker image that VSCode will use to create a container
  image_main_user       User to use inside the container
  workspace_dir         Path to the VSCode workspace on host (created if missing)
  img_workspace_dir     Absolute path to the workspace in the image (e.g. '/home/dev/workspace')

options:
  --image-main-user-home IMAGE_MAIN_USER_HOME
                         Absolute home path of 'image_main_user' inside the image (defaults to /home/<image_main_user> or /root)
  --use-host-nvidia-driver
                         Use host's NVIDIA driver (compose runtime, env vars)
  --no_console_log       Disable logging to console (enabled by default)
  --log-file LOG_FILE    File to log output
  --log-level LOG_LEVEL  Logging level (Default is DEBUG)
  -h, --help             Show this help message and exit
```

## Uninstalling the package `ros_project_creator` as a user

If you need to uninstall the package `ros_project_creator`, run the following command:

```sh
uv pip uninstall --system --prefix ~/.local ros_project_creator
```

To ensure the package is completely uninstalled, run:

```sh
pip list --user | grep ros_project_creator
```

If no output appears, the package has been successfully removed.

If the commands `create_ros_project` or `create_vscode_project` are still available after uninstallation, remove them manually:

```sh
rm -f ~/.local/bin/create_ros_project
rm -f ~/.local/bin/create_vscode_project
```

Then, verify that the scripts are no longer accessible:

```sh
which create_ros_project

which create_vscode_project

```

## Installation of the package `ros_project_creator` as a developer

### 1. Install [`uv`](https://docs.astral.sh/uv/)

```sh
curl -LsSf https://astral.sh/uv/install.sh | sh
```

### 2. Install the package `ros_project_creator` using [`uv`](https://docs.astral.sh/uv/)

Install the package `ros_project_creator` in a virtual environment, using the `--editable` flag, so the installed scripts will be linked to the source scripts.
This way, any change in the source code will be reflected when executing the scripts for debugging purposes.

```sh
git clone https://github.com/jfrascon/ros_project_creator.git ~/ros_project_creator
uv venv ~/.venv
source ~/.venv/bin/activate
uv pip install --editable ~/ros_project_creator
deactivate
```

### 3. Verify the installation of the package `ros_project_creator`

Check if the scripts inside the package `ros_project_creator` are found in your virtual environment.

```sh
source ~/.venv/bin/activate
which create_ros_project
  ~/.venv/bin/create_ros_project

which create_vscode_project
  ~/.venv/bin/create_vscode_project
deactivate
```

## Uninstalling the package `ros_project_creator` as a developer

If you need to uninstall the package `ros_project_creator`, run the following commands:

```sh
source ~/.venv/bin/activate
uv pip uninstall ros_project_creator
which create_ros_project

which create_vscode_project

deactivate
```

## Notes on project layout

- Root `pyproject.toml`: packaging metadata and build configuration (Hatchling), dependencies and CLI entry points for this tool.
- `src/ros_project_creator/pyproject.toml`: Ruff configuration (formatter/linter) scoped to the source tree of this repository; it is not used for packaging.

Pre-commit
- Hooks are installed by default when creating a project (unless `--no-pre-commit` is passed). This encourages consistent style across developers.
- If pre-commit is requested but not installed in the environment, the creation will fail, making the requirement explicit.

## Contact

For any questions or suggestions, please reach out to:

- **Juan Francisco Rascon**
- Email: [jfrascon@gmail.com](mailto:jfrascon@gmail.com)
