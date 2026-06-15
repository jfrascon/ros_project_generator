#!/usr/bin/env python3
import argparse
import os
import sys
from pathlib import Path

import argcomplete

from ros_project_creator.ros_project_creator import RosProjectCreator, RosProjectCreatorException
from ros_project_creator.utilities import Utilities


def main():
    try:
        if os.geteuid() == 0:
            raise RuntimeError('This script must not be run with sudo or as root')

        resources_dir = Path(__file__).parent.joinpath('resources')
        ros_variants = Utilities.load_yaml(resources_dir.joinpath('ros', 'ros_variants.yaml'))
        Utilities.assert_non_empty(
            ros_variants, f"No ROS variants found in the resource path '{resources_dir.resolve()}'"
        )
        supported_ros_distros = ', '.join(
            f'{ros_distro} (ros{data["ros_version"]})' for ros_distro, data in ros_variants.items()
        )

        parser = argparse.ArgumentParser(
            description='Creates a new ROS project based on templates',
            allow_abbrev=False,  # Disable prefix matching
            add_help=False,  # Add custom help message
            formatter_class=lambda prog: argparse.RawTextHelpFormatter(prog, max_help_position=40),
            # formatter_class=lambda prog: argparse.HelpFormatter(prog, max_help_position=35),
        )

        parser.add_argument(
            'project_id', type=str, help="Short, descriptive project identifier for internal reference (e.g. 'robproj')"
        )

        parser.add_argument(
            'project_dir', type=str, help="Path where the project will be created (e.g. '~/projects/robproj')"
        )

        parser.add_argument('base_img', type=str, help="Base Docker image to use (e.g. 'eutrob/eut_ros:humble')")

        parser.add_argument('img_user', type=str, help='Active user to use in the resulting Docker image')

        parser.add_argument('ros_distro', type=str, help=f'ROS distro to use: {supported_ros_distros}')

        parser.add_argument(
            '--img-id',
            type=str,
            default=None,
            help=(
                "ID of the resulting Docker image (e.g. 'robproj:humble'). If not set, defaults to "
                "'<project-id>:latest'"
            ),
        )

        parser.add_argument(
            '--nvidia', action='store_true', dest='use_host_nvidia_driver', help="Use host's NVIDIA driver"
        )

        parser.add_argument('--no-vscode', action='store_true', help='Do not create VS Code project')

        parser.add_argument('--no-pre-commit', action='store_true', help='Do not use pre-commit hooks')

        parser.add_argument(
            '--no-console-log',
            action='store_true',
            help='Disable logging to console. Console logging is enabled by default',
        )

        parser.add_argument('--log-file', type=str, help='File to log output', default='')

        parser.add_argument('--log-level', type=str, help='Logging level (Default is DEBUG)', default='DEBUG')

        parser.add_argument(
            '-h', '--help', action='help', default=argparse.SUPPRESS, help='Show this help message and exit'
        )

        argcomplete.autocomplete(parser)
        args = parser.parse_args()

        RosProjectCreator(
            project_id=args.project_id,
            project_dir=Path(args.project_dir),
            ros_distro=args.ros_distro,
            base_img=args.base_img,
            image_main_user=args.img_user,
            img_id=args.img_id,
            use_host_nvidia_driver=args.use_host_nvidia_driver,
            use_vscode_project=not args.no_vscode,
            use_pre_commit=not args.no_pre_commit,
            use_console_log=not args.no_console_log,
            log_file=args.log_file,
            log_level=args.log_level,
        )
    except RosProjectCreatorException:
        sys.exit(1)
    except Exception as e:
        print(f'{e}', file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
