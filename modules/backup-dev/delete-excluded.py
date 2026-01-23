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


def count_directory_contents(dir_path: Path) -> tuple:
    """
    Count files and subdirectories in a directory.
    Returns (file_count, dir_count).
    """
    if not dir_path.exists() or not dir_path.is_dir():
        return (0, 0)

    file_count = 0
    dir_count = 0

    try:
        for item in dir_path.rglob('*'):
            if item.is_file():
                file_count += 1
            elif item.is_dir():
                dir_count += 1
    except Exception:
        # If we can't count, return 0 (better than crashing)
        return (0, 0)

    return (file_count, dir_count)


def delete_items(backup_path: Path, directories: list, files: list, dry_run: bool = False, debug: bool = False) -> dict:
    """
    Delete directories and files with progress indication.

    Returns dict with deletion counts and errors.
    """
    deleted_dirs = 0
    deleted_files = 0
    errors = []
    skipped_items = []

    # Count total items including files within directories
    print("Analyzing items to delete...")
    total_files_in_dirs = 0
    total_subdirs_in_dirs = 0

    for dir_path_str in directories:
        full_path = backup_path / dir_path_str
        if full_path.exists() and full_path.is_dir():
            file_count, dir_count = count_directory_contents(full_path)
            total_files_in_dirs += file_count
            total_subdirs_in_dirs += dir_count

    total_items = len(directories) + total_subdirs_in_dirs + len(files) + total_files_in_dirs
    current = 0
    start_time = time.time()

    if total_items == 0:
        print("Nothing to delete.")
        return {'deleted_dirs': 0, 'deleted_files': 0, 'errors': [], 'skipped': []}

    print(f"Deleting {len(directories)} directories ({total_subdirs_in_dirs} subdirs, {total_files_in_dirs} files) + {len(files)} standalone files...")
    print(f"Total items: {total_items:,}")
    if debug:
        print("DEBUG MODE: Detailed output enabled")
    print()

    # Delete directories first
    for dir_path in directories:
        full_path = backup_path / dir_path

        if debug:
            print(f"\n[DIR] {dir_path}")
            print(f"  Full path: {full_path}")
            print(f"  Exists: {full_path.exists()}")
            if full_path.exists():
                print(f"  Is dir: {full_path.is_dir()}")
                try:
                    # Check file attributes (Windows-specific)
                    import subprocess
                    attrib_result = subprocess.run(['attrib', str(full_path)],
                                                 capture_output=True, text=True, timeout=2)
                    print(f"  Attributes: {attrib_result.stdout.strip()}")
                except Exception as e:
                    print(f"  Attributes: Unable to check ({e})")

        if full_path.exists() and full_path.is_dir():
            # Count items in this directory for progress
            file_count, dir_count = count_directory_contents(full_path)
            items_in_dir = 1 + dir_count + file_count  # +1 for the directory itself

            if dry_run:
                deleted_dirs += 1
                current += items_in_dir
                if debug:
                    print(f"  [DRY-RUN] Would delete ({file_count} files, {dir_count} subdirs)")
            else:
                try:
                    if debug:
                        print(f"  Attempting deletion ({file_count} files, {dir_count} subdirs)...")
                    shutil.rmtree(full_path, onerror=remove_readonly)
                    deleted_dirs += 1
                    current += items_in_dir
                    if debug:
                        print(f"  ✓ Deleted successfully")
                        # Verify deletion
                        if full_path.exists():
                            print(f"  ⚠ WARNING: Path still exists after deletion!")
                except Exception as e:
                    error_msg = f"Dir: {dir_path} - {str(e)}"
                    errors.append(error_msg)
                    current += items_in_dir  # Still count as processed even if failed
                    if debug:
                        print(f"  ✗ ERROR: {str(e)}")
        else:
            current += 1  # Still increment for non-existent dirs
            if debug:
                print(f"  [SKIP] Does not exist or not a directory")
            skipped_items.append(f"Dir: {dir_path} - Does not exist")

        if not debug:
            print_progress(current, total_items, deleted_dirs, deleted_files, start_time)

    # Delete files
    for file_path in files:
        current += 1
        full_path = backup_path / file_path

        if debug:
            print(f"\n[FILE] {file_path}")
            print(f"  Full path: {full_path}")
            print(f"  Exists: {full_path.exists()}")
            if full_path.exists():
                print(f"  Is file: {full_path.is_file()}")
                try:
                    import subprocess
                    attrib_result = subprocess.run(['attrib', str(full_path)],
                                                 capture_output=True, text=True, timeout=2)
                    print(f"  Attributes: {attrib_result.stdout.strip()}")
                except Exception as e:
                    print(f"  Attributes: Unable to check ({e})")

        if full_path.exists() and full_path.is_file():
            if dry_run:
                deleted_files += 1
                if debug:
                    print(f"  [DRY-RUN] Would delete")
            else:
                try:
                    if debug:
                        print(f"  Attempting deletion...")
                    # Handle read-only files
                    if not os.access(full_path, os.W_OK):
                        os.chmod(full_path, stat.S_IWRITE)
                        if debug:
                            print(f"  Removed read-only attribute")
                    full_path.unlink()
                    deleted_files += 1
                    if debug:
                        print(f"  ✓ Deleted successfully")
                        # Verify deletion
                        if full_path.exists():
                            print(f"  ⚠ WARNING: File still exists after deletion!")
                except Exception as e:
                    error_msg = f"File: {file_path} - {str(e)}"
                    errors.append(error_msg)
                    if debug:
                        print(f"  ✗ ERROR: {str(e)}")
        else:
            if debug:
                print(f"  [SKIP] Does not exist or not a file")
            skipped_items.append(f"File: {file_path} - Does not exist")

        if not debug:
            print_progress(current, total_items, deleted_dirs, deleted_files, start_time)

    # Final newline after progress
    if not debug:
        print()

    elapsed = time.time() - start_time
    print(f"\nCompleted in {elapsed:.1f}s")

    if debug and skipped_items:
        print(f"\nSkipped items: {len(skipped_items)}")

    return {
        'deleted_dirs': deleted_dirs,
        'deleted_files': deleted_files,
        'errors': errors,
        'skipped': skipped_items
    }


def main():
    parser = argparse.ArgumentParser(
        description='Delete files/directories from backup based on scan result'
    )
    parser.add_argument('backup_path', help='Path to backup directory')
    parser.add_argument('scan_result', help='Path to scan result JSON file')
    parser.add_argument('--dry-run', action='store_true', help='Show what would be deleted without deleting')
    parser.add_argument('--debug', action='store_true', help='Enable detailed debug output for troubleshooting')
    parser.add_argument('--output', '-o', help='Save result JSON to file (for PowerShell integration)')

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

    if args.debug:
        print(f"=== DEBUG MODE ENABLED ===")
        print(f"Backup path: {backup_path}")
        print(f"Scan result: {args.scan_result}")
        print(f"Items to process: {len(directories)} dirs, {len(files)} files")
        print()

    # Delete items
    result = delete_items(backup_path, directories, files, dry_run=args.dry_run, debug=args.debug)

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

    # Save result to file if requested (for PowerShell integration)
    if args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            json.dump(result, f, indent=2)
        print(f"\nResult saved to: {args.output}")


if __name__ == '__main__':
    main()
