import logging

import pytest

from ros_project_generator.resource_installer import ResourceInstaller, ResourceSpec


def test_resource_installer_creates_directories_copies_files_and_renders_templates(tmp_path) -> None:
    resources_dir = tmp_path / 'resources'
    target_dir = tmp_path / 'target'
    resources_dir.mkdir()
    target_dir.mkdir()

    resources_dir.joinpath('plain.txt').write_text('plain resource\n')
    resources_dir.joinpath('template.j2').write_text('project={{ project_id }}\n')

    ResourceInstaller(
        resources_dir=resources_dir, target_dir=target_dir, logger=logging.getLogger('test_resource_installer')
    ).install(
        [
            ResourceSpec.directory('src/config'),
            ResourceSpec.file('copied/plain.txt', 'plain.txt'),
            ResourceSpec.template('rendered/project.txt', 'template.j2', {'project_id': 'demo'}),
        ]
    )

    assert target_dir.joinpath('src/config').is_dir()
    assert target_dir.joinpath('copied/plain.txt').read_text() == 'plain resource\n'
    assert target_dir.joinpath('rendered/project.txt').read_text() == 'project=demo'


def test_resource_installer_can_replace_existing_files(tmp_path) -> None:
    resources_dir = tmp_path / 'resources'
    target_dir = tmp_path / 'target'
    resources_dir.mkdir()
    target_dir.mkdir()

    resources_dir.joinpath('template.j2').write_text('new={{ value }}\n')
    target_dir.joinpath('existing.txt').write_text('old\n')

    ResourceInstaller(
        resources_dir=resources_dir,
        target_dir=target_dir,
        logger=logging.getLogger('test_resource_installer_replace'),
        replace_existing=True,
    ).install([ResourceSpec.template('existing.txt', 'template.j2', {'value': 'content'})])

    assert target_dir.joinpath('existing.txt').read_text() == 'new=content'


def test_resource_installer_rejects_file_resource_with_directory_source(tmp_path) -> None:
    resources_dir = tmp_path / 'resources'
    target_dir = tmp_path / 'target'
    resources_dir.mkdir()
    target_dir.mkdir()
    resources_dir.joinpath('directory_source').mkdir()

    installer = ResourceInstaller(
        resources_dir=resources_dir,
        target_dir=target_dir,
        logger=logging.getLogger('test_resource_installer_invalid_file_source'),
    )

    with pytest.raises(Exception, match='is not a file'):
        installer.install([ResourceSpec.file('copied/path', 'directory_source')])
