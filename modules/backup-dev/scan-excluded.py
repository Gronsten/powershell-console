#!/usr/bin/env python3
"""
Scan backup directory for files/directories matching exclusion patterns.

This script walks the backup directory once and checks each item against
all exclusion patterns defined in config.json. Much faster than PowerShell's
Get-ChildItem for large directory trees.

Usage:
    python scan-excluded.py <backup_path> <config_path>
    python scan-excluded.py <backup_path> <config_path> --delete
    python scan-excluded.py --help

Output:
    JSON object with matched directories and files (relative paths)
    With --delete: Also includes deletion results (deleted_dirs, deleted_files, errors)
"""

import argparse
import fnmatch
import json
import os
import shutil
import sys
from pathlib import Path


def load_exclusions(config_path: str) -> tuple[list[str], list[str]]:
    """Load exclusion patterns from config.json."""
    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)

        exclude_dirs = []
        exclude_files = []

        if 'backupDev' in config and 'exclusions' in config['backupDev']:
            exclusions = config['backupDev']['exclusions']
            exclude_dirs = exclusions.get('directories', [])
            exclude_files = exclusions.get('files', [])

        return exclude_dirs, exclude_files
    except Exception as e:
        print(f"Error loading config: {e}", file=sys.stderr)
        return [], []


def scan_backup(backup_path: str, exclude_dirs: list[str], exclude_files: list[str]) -> dict:
    """
    Walk backup directory and find items matching exclusion patterns.

    Returns dict with:
        - directories: list of relative paths to matched directories
        - files: list of relative paths to matched files
    """
    matched_dirs = []
    matched_files = []

    backup_path = Path(backup_path)

    # Convert exclude_dirs to a set for O(1) lookup
    exclude_dirs_set = set(exclude_dirs)

    for root, dirs, files in os.walk(backup_path):
        rel_root = Path(root).relative_to(backup_path)

        # Check directories
        for d in dirs:
            if d in exclude_dirs_set:
                rel_path = str(rel_root / d) if str(rel_root) != '.' else d
                matched_dirs.append(rel_path)

        # Check files against patterns (supports wildcards like *.log)
        for f in files:
            for pattern in exclude_files:
                if fnmatch.fnmatch(f, pattern):
                    rel_path = str(rel_root / f) if str(rel_root) != '.' else f
                    matched_files.append(rel_path)
                    break  # Don't add same file multiple times

    return {
        'directories': matched_dirs,
        'files': matched_files,
        'directory_count': len(matched_dirs),
        'file_count': len(matched_files)
    }


def remove_readonly(func, path, excinfo):
    """
    Error handler for shutil.rmtree to handle read-only files.
    Git pack files and index files are often read-only.
    """
    import stat
    # Clear the read-only flag and retry
    os.chmod(path, stat.S_IWRITE)
    func(path)


def delete_excluded(backup_path: str, directories: list[str], files: list[str], show_progress: bool = True) -> dict:
    """
    Delete matched directories and files from the backup.

    Returns dict with:
        - deleted_dirs: count of successfully deleted directories
        - deleted_files: count of successfully deleted files
        - errors: list of error messages
    """
    import stat
    import time
    backup_path = Path(backup_path)
    deleted_dirs = 0
    deleted_files = 0
    errors = []

    total_dirs = len(directories)
    total_files = len(files)
    total_items = total_dirs + total_files
    last_progress_time = time.time()

    # Delete directories first (they may contain matched files)
    for i, dir_path in enumerate(directories):
        full_path = backup_path / dir_path
        if full_path.exists() and full_path.is_dir():
            try:
                # Use onerror handler to deal with read-only files (common in .git)
                shutil.rmtree(full_path, onerror=remove_readonly)
                deleted_dirs += 1
            except Exception as e:
                errors.append(f"Dir: {dir_path} - {str(e)}")

        # Output progress to stderr every 500ms
        if show_progress:
            current_time = time.time()
            if current_time - last_progress_time >= 0.5:
                processed = i + 1
                pct = int((processed / total_items) * 100) if total_items > 0 else 0
                print(f"PROGRESS:{pct}:{deleted_dirs}:{deleted_files}:{processed}:{total_items}", file=sys.stderr, flush=True)
                last_progress_time = current_time

    # Delete files
    for i, file_path in enumerate(files):
        full_path = backup_path / file_path
        if full_path.exists() and full_path.is_file():
            try:
                # Handle read-only files
                if not os.access(full_path, os.W_OK):
                    os.chmod(full_path, stat.S_IWRITE)
                full_path.unlink()
                deleted_files += 1
            except Exception as e:
                errors.append(f"File: {file_path} - {str(e)}")

        # Output progress to stderr every 500ms
        if show_progress:
            current_time = time.time()
            if current_time - last_progress_time >= 0.5:
                processed = total_dirs + i + 1
                pct = int((processed / total_items) * 100) if total_items > 0 else 0
                print(f"PROGRESS:{pct}:{deleted_dirs}:{deleted_files}:{processed}:{total_items}", file=sys.stderr, flush=True)
                last_progress_time = current_time

    return {
        'deleted_dirs': deleted_dirs,
        'deleted_files': deleted_files,
        'errors': errors
    }


def main():
    parser = argparse.ArgumentParser(
        description='Scan backup directory for files matching exclusion patterns'
    )
    parser.add_argument('backup_path', help='Path to backup directory')
    parser.add_argument('config_path', help='Path to config.json')
    parser.add_argument('--pretty', action='store_true', help='Pretty-print JSON output')
    parser.add_argument('--delete', action='store_true', help='Delete matched files and directories')
    parser.add_argument('--output', '-o', help='Save scan result to file (for use with delete-excluded.py)')

    args = parser.parse_args()

    # Validate paths
    if not os.path.isdir(args.backup_path):
        print(json.dumps({'error': f'Backup path not found: {args.backup_path}'}))
        sys.exit(1)

    if not os.path.isfile(args.config_path):
        print(json.dumps({'error': f'Config file not found: {args.config_path}'}))
        sys.exit(1)

    # Load exclusions
    exclude_dirs, exclude_files = load_exclusions(args.config_path)

    if not exclude_dirs and not exclude_files:
        print(json.dumps({
            'directories': [],
            'files': [],
            'directory_count': 0,
            'file_count': 0,
            'message': 'No exclusion patterns configured'
        }))
        sys.exit(0)

    # Scan backup
    result = scan_backup(args.backup_path, exclude_dirs, exclude_files)

    # Delete if requested
    if args.delete:
        delete_result = delete_excluded(
            args.backup_path,
            result['directories'],
            result['files']
        )
        result.update(delete_result)

    # Output JSON
    output_json = json.dumps(result, indent=2) if args.pretty else json.dumps(result)

    if args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(output_json)
        print(f"Scan result saved to: {args.output}", file=sys.stderr)
    else:
        print(output_json)


if __name__ == '__main__':
    main()
