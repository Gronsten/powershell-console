#!/usr/bin/env python3
"""
Delete files/directories from a backup based on a scan result file.

This script reads a JSON file containing directories and files to delete,
then deletes them with real-time console progress.

Usage:
    python delete-excluded.py <backup_path> <scan_result.json>
    python delete-excluded.py <backup_path> <scan_result.json> --dry-run

The scan result JSON should have:
    {
        "directories": ["path/to/dir1", "path/to/dir2"],
        "files": ["path/to/file1.txt", "path/to/file2.log"]
    }
"""

import argparse
import json
import os
import shutil
import stat
import sys
import time
from pathlib import Path


def remove_readonly(func, path, excinfo):
    """Error handler for shutil.rmtree to handle read-only files."""
    os.chmod(path, stat.S_IWRITE)
    func(path)


def print_progress(current: int, total: int, deleted_dirs: int, deleted_files: int,
                   start_time: float, item_type: str = ""):
    """Print progress bar to console."""
    elapsed = time.time() - start_time
    pct = int((current / total) * 100) if total > 0 else 100

    # Calculate ETA
    if current > 0 and elapsed > 0:
        rate = current / elapsed
        remaining = (total - current) / rate if rate > 0 else 0
        eta_str = f"ETA: {int(remaining)}s"
    else:
        eta_str = "ETA: --"

    # Progress bar (ASCII-safe characters)
    bar_width = 30
    filled = int(bar_width * pct / 100)
    bar = '#' * filled + '-' * (bar_width - filled)

    status = f"\r[{bar}] {pct:3d}% | {current}/{total} | Dirs: {deleted_dirs} Files: {deleted_files} | {eta_str}   "
    print(status, end='', flush=True)


def delete_items(backup_path: Path, directories: list, files: list, dry_run: bool = False) -> dict:
    """
    Delete directories and files with progress indication.

    Returns dict with deletion counts and errors.
    """
    deleted_dirs = 0
    deleted_files = 0
    errors = []

    total_items = len(directories) + len(files)
    current = 0
    start_time = time.time()

    if total_items == 0:
        print("Nothing to delete.")
        return {'deleted_dirs': 0, 'deleted_files': 0, 'errors': []}

    print(f"Deleting {len(directories)} directories and {len(files)} files...")
    print()

    # Delete directories first
    for dir_path in directories:
        current += 1
        full_path = backup_path / dir_path

        if full_path.exists() and full_path.is_dir():
            if dry_run:
                deleted_dirs += 1
            else:
                try:
                    shutil.rmtree(full_path, onerror=remove_readonly)
                    deleted_dirs += 1
                except Exception as e:
                    errors.append(f"Dir: {dir_path} - {str(e)}")

        print_progress(current, total_items, deleted_dirs, deleted_files, start_time)

    # Delete files
    for file_path in files:
        current += 1
        full_path = backup_path / file_path

        if full_path.exists() and full_path.is_file():
            if dry_run:
                deleted_files += 1
            else:
                try:
                    # Handle read-only files
                    if not os.access(full_path, os.W_OK):
                        os.chmod(full_path, stat.S_IWRITE)
                    full_path.unlink()
                    deleted_files += 1
                except Exception as e:
                    errors.append(f"File: {file_path} - {str(e)}")

        print_progress(current, total_items, deleted_dirs, deleted_files, start_time)

    # Final newline after progress
    print()

    elapsed = time.time() - start_time
    print(f"\nCompleted in {elapsed:.1f}s")

    return {
        'deleted_dirs': deleted_dirs,
        'deleted_files': deleted_files,
        'errors': errors
    }


def main():
    parser = argparse.ArgumentParser(
        description='Delete files/directories from backup based on scan result'
    )
    parser.add_argument('backup_path', help='Path to backup directory')
    parser.add_argument('scan_result', help='Path to scan result JSON file')
    parser.add_argument('--dry-run', action='store_true', help='Show what would be deleted without deleting')

    args = parser.parse_args()

    backup_path = Path(args.backup_path)

    # Validate paths
    if not backup_path.is_dir():
        print(f"Error: Backup path not found: {args.backup_path}", file=sys.stderr)
        sys.exit(1)

    if not os.path.isfile(args.scan_result):
        print(f"Error: Scan result file not found: {args.scan_result}", file=sys.stderr)
        sys.exit(1)

    # Load scan result
    try:
        with open(args.scan_result, 'r', encoding='utf-8') as f:
            scan_data = json.load(f)
    except Exception as e:
        print(f"Error reading scan result: {e}", file=sys.stderr)
        sys.exit(1)

    directories = scan_data.get('directories', [])
    files = scan_data.get('files', [])

    if args.dry_run:
        print("=== DRY RUN MODE - No files will be deleted ===\n")

    # Delete items
    result = delete_items(backup_path, directories, files, dry_run=args.dry_run)

    # Print summary
    print(f"\nSummary:")
    print(f"  Directories deleted: {result['deleted_dirs']}")
    print(f"  Files deleted: {result['deleted_files']}")

    if result['errors']:
        print(f"\nErrors ({len(result['errors'])}):")
        for err in result['errors'][:10]:  # Show first 10 errors
            print(f"  {err}")
        if len(result['errors']) > 10:
            print(f"  ... and {len(result['errors']) - 10} more errors")

    # Output JSON result to stdout for programmatic use
    print(f"\n--- JSON Result ---")
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
