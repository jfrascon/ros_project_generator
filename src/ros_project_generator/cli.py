import argparse
import sys
from collections.abc import Sequence
from typing import Optional

from ros_project_generator import create_ros_project


def main(argv: Optional[Sequence[str]] = None) -> None:
    args = list(sys.argv[1:] if argv is None else argv)
    parser = _build_parser()

    if not args:
        parser.print_help()
        return

    command = args[0]
    if command in ('-h', '--help'):
        parser.print_help()
        return

    if command == 'new':
        create_ros_project.main(args[1:], prog='ros-project new')
        return

    parser.error(f'unknown command: {command}')


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog='ros-project', description='Manage ROS 2 development projects.', allow_abbrev=False
    )
    subparsers = parser.add_subparsers(dest='command', metavar='COMMAND')
    subparsers.add_parser('new', help='Create a new ROS 2 project.', add_help=False)
    return parser


if __name__ == '__main__':
    main()
