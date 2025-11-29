#!/usr/bin/env python3
"""Fast line counter for projects with exclusion visibility.

Shows line counts per project with inline exclusion indicators:
- White/normal text: Files included in count
- Gray text: Files/directories excluded from count
- Excluded column: Shows count of excluded items (e.g., "26(f), 1(d)")

Exclusion rules are configured in config.json under the 'lineCounter' section.

Usage:
    python count-lines.py [PATH]

Arguments:
    PATH    Optional path to analyze (default: devRoot from config.json)

Examples:
    python count-lines.py
    python count-lines.py C:\\Projects\\myapp
"""

import os
import sys
import json
import fnmatch
from pathlib import Path
from collections import defaultdict
import time

# Global variable to store exclusion config
_exclusion_config = None

def load_exclusion_config(config_path: Path) -> dict:
    """Load line counter exclusion configuration from config.json."""
    global _exclusion_config

    if _exclusion_config is not None:
        return _exclusion_config

    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)
        _exclusion_config = config.get('lineCounter', {})
        return _exclusion_config
    except (FileNotFoundError, KeyError, json.JSONDecodeError) as e:
        print(f"Warning: Could not read lineCounter config from config.json: {e}")
        print(f"Using default exclusions only (.git, node_modules, hidden files)")
        _exclusion_config = {}
        return _exclusion_config

def should_exclude(file_path: Path, base_path: Path, dev_root: Path, config: dict) -> bool:
    """Check if a file should be excluded from counting based on config.json settings."""
    rel_path = file_path.relative_to(base_path)
    parts = rel_path.parts

    # Get global and project-specific exclusions from config
    global_exclusions = config.get('globalExclusions', {})
    project_exclusions = config.get('projectExclusions', {})

    # Apply global exclusions
    # Check global extensions
    for ext in global_exclusions.get('extensions', []):
        if file_path.suffix == ext:
            return True

    # Check global path patterns (case-insensitive)
    file_path_str = str(file_path).lower()
    for pattern in global_exclusions.get('pathPatterns', []):
        if pattern.lower() in file_path_str:
            return True

    # Determine the project name from the dev root perspective
    try:
        rel_to_dev = file_path.relative_to(dev_root)
        project = rel_to_dev.parts[0] if len(rel_to_dev.parts) > 0 else None
    except ValueError:
        # File is outside dev root, use first part of relative path
        project = parts[0] if len(parts) > 0 else None

    # Apply project-specific exclusions
    if project and project in project_exclusions:
        proj_config = project_exclusions[project]

        # Check if entire project is excluded
        if proj_config.get('excludeAll', False):
            return True

        # Check includeOnly whitelist (if present, only these files are included)
        include_only = proj_config.get('includeOnly', [])
        if include_only:
            return file_path.name not in include_only

        # Check exact filename exclusions
        for filename in proj_config.get('files', []):
            if file_path.name == filename:
                return True

        # Check filename patterns (supports wildcards)
        for pattern in proj_config.get('filePatterns', []):
            if fnmatch.fnmatch(file_path.name, pattern):
                return True

        # Check project-specific extensions
        for ext in proj_config.get('extensions', []):
            if file_path.suffix == ext:
                return True

        # Check project-specific path patterns (case-insensitive)
        for pattern in proj_config.get('pathPatterns', []):
            if pattern.lower() in file_path_str:
                return True

    return False

def count_lines_in_file(file_path: Path) -> int:
    """Count lines in a file, handling various encodings."""
    encodings = ['utf-8', 'latin-1', 'cp1252']

    for encoding in encodings:
        try:
            with open(file_path, 'r', encoding=encoding) as f:
                return sum(1 for _ in f)
        except (UnicodeDecodeError, PermissionError):
            continue
        except Exception:
            return 0
    return 0

def count_project_lines(base_path: Path, dev_root: Path = None, exclusion_config: dict = None):
    """Count lines across all projects with exclusions."""
    start_time = time.time()

    # If dev_root not specified, assume base_path is the dev root
    if dev_root is None:
        dev_root = base_path

    # If exclusion_config not provided, use empty dict (no exclusions except defaults)
    if exclusion_config is None:
        exclusion_config = {}

    # Track both included and excluded items per project
    project_stats = defaultdict(lambda: {
        'files': 0, 'lines': 0,
        'excluded_files': 0, 'excluded_dirs': 0
    })

    total_files = 0
    total_lines = 0
    total_excluded_files = 0
    total_excluded_dirs = 0

    for root, dirs, files in os.walk(base_path):
        # Track excluded directories (.git, .hidden, node_modules)
        original_dirs = dirs.copy()
        dirs[:] = [d for d in dirs if not d.startswith('.') and d != 'node_modules']

        # Count excluded directories by project
        for d in original_dirs:
            if d not in dirs:
                try:
                    dir_path = Path(root) / d
                    rel_path = dir_path.relative_to(base_path)
                    project = rel_path.parts[0] if len(rel_path.parts) > 0 else 'root'
                    project_stats[project]['excluded_dirs'] += 1
                    total_excluded_dirs += 1
                except:
                    continue

        for file in files:
            file_path = Path(root) / file

            try:
                rel_path = file_path.relative_to(base_path)
                project = rel_path.parts[0] if len(rel_path.parts) > 0 else 'root'

                if should_exclude(file_path, base_path, dev_root, exclusion_config):
                    project_stats[project]['excluded_files'] += 1
                    total_excluded_files += 1
                    continue

                lines = count_lines_in_file(file_path)

                project_stats[project]['files'] += 1
                project_stats[project]['lines'] += lines
                total_files += 1
                total_lines += lines

            except Exception as e:
                continue

    # Display results
    print("\n" + "="*80)
    print(f"ANALYZING: {base_path}")
    print("="*80)
    print(f"{'Project':<30} {'Files':>10} {'Lines':>13} {'Excluded':>15} {'Status':<10}")
    print("-"*80)

    # Color codes for terminal output
    GRAY = '\033[90m'    # Excluded items
    WHITE = '\033[97m'   # Included items
    YELLOW = '\033[93m'  # Highlighting
    RESET = '\033[0m'

    # Sort by lines descending (included items only)
    sorted_projects = sorted(project_stats.items(),
                            key=lambda x: x[1]['lines'],
                            reverse=True)

    for project, stats in sorted_projects:
        # Determine if this project has any included files
        has_included = stats['files'] > 0
        has_excluded = stats['excluded_files'] > 0 or stats['excluded_dirs'] > 0

        if has_included:
            # Show included files (normal white text)
            excluded_parts = []
            if stats['excluded_files'] > 0:
                excluded_parts.append(f"{stats['excluded_files']}(f)")
            if stats['excluded_dirs'] > 0:
                excluded_parts.append(f"{stats['excluded_dirs']}(d)")
            excluded_count = ", ".join(excluded_parts) if excluded_parts else "0"

            color = WHITE if has_excluded else RESET
            print(f"{color}{project:<30} {stats['files']:>10,} {stats['lines']:>13,} {excluded_count:>15} {'included':<10}{RESET}")

        if has_excluded and not has_included:
            # Show projects that are entirely excluded (gray text)
            excluded_parts = []
            if stats['excluded_files'] > 0:
                excluded_parts.append(f"{stats['excluded_files']}(f)")
            if stats['excluded_dirs'] > 0:
                excluded_parts.append(f"{stats['excluded_dirs']}(d)")
            excluded_desc = ", ".join(excluded_parts)

            print(f"{GRAY}{project:<30} {'---':>10} {'---':>13} {excluded_desc:>15} {'excluded':<10}{RESET}")

    elapsed = time.time() - start_time

    print("="*80)
    print(f"{'TOTAL INCLUDED':<30} {total_files:>10,} {total_lines:>13,} {'':<15} {'':<10}")

    # Format total excluded
    excluded_parts = []
    if total_excluded_files > 0:
        excluded_parts.append(f"{total_excluded_files}(f)")
    if total_excluded_dirs > 0:
        excluded_parts.append(f"{total_excluded_dirs}(d)")
    total_excluded_desc = ", ".join(excluded_parts) if excluded_parts else "0"

    print(f"{GRAY}{'TOTAL EXCLUDED':<30} {'---':>10} {'---':>13} {total_excluded_desc:>15} {'':<10}{RESET}")
    print("="*80)
    print(f"\nProcessing time: {elapsed:.2f} seconds")
    print(f"Legend: {WHITE}Normal text{RESET} = included, {GRAY}Gray{RESET} = excluded | Format: X(f)=files, X(d)=dirs")
    print("="*80)

if __name__ == '__main__':
    # Load config from config.json
    script_dir = Path(__file__).resolve().parent
    config_path = script_dir.parent / 'config.json'

    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)
        dev_root = Path(config['paths']['devRoot'])
    except (FileNotFoundError, KeyError, json.JSONDecodeError) as e:
        print(f"Error: Could not read devRoot from config.json: {e}")
        print(f"Expected config at: {config_path}")
        sys.exit(1)

    # Load exclusion configuration
    exclusion_config = load_exclusion_config(config_path)

    # Parse command line arguments
    if len(sys.argv) > 1:
        # User specified a path
        target = sys.argv[1]

        # Convert to absolute path
        if os.path.isabs(target):
            base_path = Path(target)
        else:
            # Relative path - resolve from current directory
            base_path = Path(os.getcwd()) / target

        # Validate path exists
        if not base_path.exists():
            print(f"Error: Path does not exist: {base_path}")
            sys.exit(1)

        # If it's a file, count just that file
        if base_path.is_file():
            lines = count_lines_in_file(base_path)
            filename = base_path.name

            # Display in standard table format
            print("\n" + "="*80)
            print(f"ANALYZING: {base_path}")
            print("="*80)
            print(f"{'File':<30} {'Files':>10} {'Lines':>13} {'Excluded':>15} {'Status':<10}")
            print("-"*80)
            print(f"{filename:<30} {1:>10,} {lines:>13,} {'0':>15} {'included':<10}")
            print("="*80)
            print(f"{'TOTAL':<30} {1:>10,} {lines:>13,}")
            print("="*80)
            sys.exit(0)
    else:
        # Default to devRoot from config.json
        base_path = dev_root

    count_project_lines(base_path, dev_root, exclusion_config)
