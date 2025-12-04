#!python3
"""Fast line counter for projects with exclusion visibility.

Shows line counts per project with inline exclusion indicators:
- White/normal text: Files included in count
- Gray text: Files/directories excluded from count
- Excluded column: Shows count of excluded items (e.g., "26(f), 1(d)")

Exclusion rules are configured in config.json under the 'lineCounter' section.

Usage:
    python count-lines.py [PATH]
    python count-lines.py --show-exclusions
    python count-lines.py --manage
    python count-lines.py --add-ext .zip --add-pattern backup

Arguments:
    PATH                  Optional path to analyze (default: devRoot from config.json)
    --show-exclusions     Display current exclusion configuration
    --manage              Launch interactive exclusion manager
    --add-ext EXT         Add global extension exclusion (e.g., .zip)
    --add-pattern PAT     Add global path pattern exclusion (e.g., backup)
    --remove-ext EXT      Remove global extension exclusion
    --remove-pattern PAT  Remove global path pattern exclusion

Examples:
    python count-lines.py
    python count-lines.py C:\\Projects\\myapp
    python count-lines.py --show-exclusions
    python count-lines.py --add-ext .zip
    python count-lines.py --add-ext .zip --add-pattern backup
    python count-lines.py --manage
"""

import os
import sys
import json
import fnmatch
import argparse
import shutil
from pathlib import Path
from collections import defaultdict
from datetime import datetime
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

def backup_config(config_path: Path) -> Path:
    """Create a backup of config.json before modifications."""
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_path = config_path.parent / f"config.json.backup_{timestamp}"
    shutil.copy2(config_path, backup_path)
    return backup_path

def save_config(config_path: Path, config: dict) -> bool:
    """Save configuration to config.json with pretty formatting."""
    try:
        with open(config_path, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=2, ensure_ascii=False)
        return True
    except Exception as e:
        print(f"Error saving config: {e}")
        return False

def validate_extension(ext: str) -> str:
    """Validate and normalize extension format."""
    ext = ext.strip()
    if not ext.startswith('.'):
        ext = '.' + ext
    return ext.lower()

def show_exclusions(config: dict):
    """Display current exclusion configuration."""
    line_counter = config.get('lineCounter', {})
    global_ex = line_counter.get('globalExclusions', {})
    project_ex = line_counter.get('projectExclusions', {})

    print("\n" + "="*80)
    print("COUNT-LINES EXCLUSION CONFIGURATION")
    print("="*80)

    # Global Exclusions
    print("\nGLOBAL EXCLUSIONS (Applied to all projects):")
    print("-" * 80)

    extensions = global_ex.get('extensions', [])
    patterns = global_ex.get('pathPatterns', [])

    if extensions:
        print(f"\n  Extensions ({len(extensions)}):")
        for ext in sorted(extensions):
            print(f"    • {ext}")
    else:
        print("\n  Extensions: None")

    if patterns:
        print(f"\n  Path Patterns ({len(patterns)}):")
        for pattern in sorted(patterns):
            print(f"    • {pattern}")
    else:
        print("\n  Path Patterns: None")

    # Project-Specific Exclusions
    if project_ex:
        print(f"\n\nPROJECT-SPECIFIC EXCLUSIONS ({len(project_ex)} projects):")
        print("-" * 80)

        for project, rules in sorted(project_ex.items()):
            print(f"\n  {project}:")

            if rules.get('excludeAll'):
                print("    [!] ENTIRE PROJECT EXCLUDED")
                continue

            if rules.get('includeOnly'):
                print(f"    Include Only: {', '.join(rules['includeOnly'])}")
                continue

            if rules.get('extensions'):
                print(f"    Extensions: {', '.join(rules['extensions'])}")
            if rules.get('files'):
                print(f"    Files: {', '.join(rules['files'])}")
            if rules.get('filePatterns'):
                print(f"    Patterns: {', '.join(rules['filePatterns'])}")
            if rules.get('pathPatterns'):
                print(f"    Paths: {', '.join(rules['pathPatterns'])}")
    else:
        print("\n\nPROJECT-SPECIFIC EXCLUSIONS: None")

    print("\n" + "="*80)

def add_global_extension(config_path: Path, extension: str) -> bool:
    """Add a global extension exclusion."""
    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)

        ext = validate_extension(extension)

        # Ensure lineCounter structure exists
        if 'lineCounter' not in config:
            config['lineCounter'] = {}
        if 'globalExclusions' not in config['lineCounter']:
            config['lineCounter']['globalExclusions'] = {}
        if 'extensions' not in config['lineCounter']['globalExclusions']:
            config['lineCounter']['globalExclusions']['extensions'] = []

        extensions = config['lineCounter']['globalExclusions']['extensions']

        if ext in extensions:
            print(f"Extension '{ext}' already excluded")
            return False

        # Backup before modification
        backup_path = backup_config(config_path)
        print(f"Config backed up to: {backup_path.name}")

        extensions.append(ext)
        extensions.sort()

        if save_config(config_path, config):
            print(f"[+] Added extension: {ext}")
            return True
        else:
            return False

    except Exception as e:
        print(f"Error adding extension: {e}")
        return False

def add_global_pattern(config_path: Path, pattern: str) -> bool:
    """Add a global path pattern exclusion."""
    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)

        pattern = pattern.strip().lower()

        # Ensure lineCounter structure exists
        if 'lineCounter' not in config:
            config['lineCounter'] = {}
        if 'globalExclusions' not in config['lineCounter']:
            config['lineCounter']['globalExclusions'] = {}
        if 'pathPatterns' not in config['lineCounter']['globalExclusions']:
            config['lineCounter']['globalExclusions']['pathPatterns'] = []

        patterns = config['lineCounter']['globalExclusions']['pathPatterns']

        if pattern in patterns:
            print(f"Pattern '{pattern}' already excluded")
            return False

        # Backup before modification
        backup_path = backup_config(config_path)
        print(f"Config backed up to: {backup_path.name}")

        patterns.append(pattern)
        patterns.sort()

        if save_config(config_path, config):
            print(f"[+] Added pattern: {pattern}")
            return True
        else:
            return False

    except Exception as e:
        print(f"Error adding pattern: {e}")
        return False

def remove_global_extension(config_path: Path, extension: str) -> bool:
    """Remove a global extension exclusion."""
    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)

        ext = validate_extension(extension)

        extensions = config.get('lineCounter', {}).get('globalExclusions', {}).get('extensions', [])

        if ext not in extensions:
            print(f"Extension '{ext}' not found in exclusions")
            return False

        # Backup before modification
        backup_path = backup_config(config_path)
        print(f"Config backed up to: {backup_path.name}")

        extensions.remove(ext)

        if save_config(config_path, config):
            print(f"[-] Removed extension: {ext}")
            return True
        else:
            return False

    except Exception as e:
        print(f"Error removing extension: {e}")
        return False

def remove_global_pattern(config_path: Path, pattern: str) -> bool:
    """Remove a global path pattern exclusion."""
    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)

        pattern = pattern.strip().lower()

        patterns = config.get('lineCounter', {}).get('globalExclusions', {}).get('pathPatterns', [])

        if pattern not in patterns:
            print(f"Pattern '{pattern}' not found in exclusions")
            return False

        # Backup before modification
        backup_path = backup_config(config_path)
        print(f"Config backed up to: {backup_path.name}")

        patterns.remove(pattern)

        if save_config(config_path, config):
            print(f"[-] Removed pattern: {pattern}")
            return True
        else:
            return False

    except Exception as e:
        print(f"Error removing pattern: {e}")
        return False

def interactive_manage(config_path: Path):
    """Launch interactive exclusion manager."""
    while True:
        try:
            with open(config_path, 'r', encoding='utf-8') as f:
                config = json.load(f)
        except Exception as e:
            print(f"Error loading config: {e}")
            return

        print("\n" + "="*80)
        print("COUNT-LINES EXCLUSION MANAGER")
        print("="*80)
        print("\n1. View current exclusions")
        print("2. Add global extension exclusion")
        print("3. Add global path pattern exclusion")
        print("4. Remove global extension exclusion")
        print("5. Remove global path pattern exclusion")
        print("0. Exit")
        print("\n" + "-"*80)

        choice = input("Your choice: ").strip()

        if choice == '0':
            print("\nExiting exclusion manager.")
            break
        elif choice == '1':
            show_exclusions(config)
        elif choice == '2':
            ext = input("Enter extension to exclude (e.g., .zip or zip): ").strip()
            if ext:
                add_global_extension(config_path, ext)
        elif choice == '3':
            pattern = input("Enter path pattern to exclude (e.g., backup, logs): ").strip()
            if pattern:
                add_global_pattern(config_path, pattern)
        elif choice == '4':
            ext = input("Enter extension to remove (e.g., .zip or zip): ").strip()
            if ext:
                remove_global_extension(config_path, ext)
        elif choice == '5':
            pattern = input("Enter path pattern to remove (e.g., backup, logs): ").strip()
            if pattern:
                remove_global_pattern(config_path, pattern)
        else:
            print("Invalid choice. Please try again.")

if __name__ == '__main__':
    # Load config from config.json
    script_dir = Path(__file__).resolve().parent
    config_path = script_dir.parent / 'config.json'

    # Setup argument parser
    parser = argparse.ArgumentParser(
        description='Count lines in projects with configurable exclusions',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Examples:
  count-lines.py                              # Count lines in devRoot
  count-lines.py C:\\Projects\\myapp           # Count lines in specific path
  count-lines.py --show-exclusions            # View current exclusions
  count-lines.py --add-ext .zip               # Add .zip to exclusions
  count-lines.py --add-pattern backup         # Add backup paths to exclusions
  count-lines.py --manage                     # Interactive management
        '''
    )

    parser.add_argument('path', nargs='?', help='Path to analyze (default: devRoot from config.json)')
    parser.add_argument('--show-exclusions', action='store_true', help='Display current exclusion configuration')
    parser.add_argument('--manage', action='store_true', help='Launch interactive exclusion manager')
    parser.add_argument('--add-ext', metavar='EXT', action='append', help='Add global extension exclusion (e.g., .zip)')
    parser.add_argument('--add-pattern', metavar='PAT', action='append', help='Add global path pattern exclusion (e.g., backup)')
    parser.add_argument('--remove-ext', metavar='EXT', action='append', help='Remove global extension exclusion')
    parser.add_argument('--remove-pattern', metavar='PAT', action='append', help='Remove global path pattern exclusion')

    args = parser.parse_args()

    # Load config
    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)
        dev_root = Path(config['paths']['devRoot'])
    except (FileNotFoundError, KeyError, json.JSONDecodeError) as e:
        print(f"Error: Could not read config.json: {e}")
        print(f"Expected config at: {config_path}")
        sys.exit(1)

    # Handle management commands
    if args.show_exclusions:
        show_exclusions(config)
        sys.exit(0)

    if args.manage:
        interactive_manage(config_path)
        sys.exit(0)

    # Handle add/remove operations
    modified = False

    if args.add_ext:
        for ext in args.add_ext:
            if add_global_extension(config_path, ext):
                modified = True

    if args.add_pattern:
        for pattern in args.add_pattern:
            if add_global_pattern(config_path, pattern):
                modified = True

    if args.remove_ext:
        for ext in args.remove_ext:
            if remove_global_extension(config_path, ext):
                modified = True

    if args.remove_pattern:
        for pattern in args.remove_pattern:
            if remove_global_pattern(config_path, pattern):
                modified = True

    # If any modifications were made, reload config and exit
    if modified:
        print("\nExclusions updated successfully!")
        sys.exit(0)

    # Load exclusion configuration for counting
    exclusion_config = load_exclusion_config(config_path)

    # Determine path to analyze
    if args.path:
        # User specified a path
        target = args.path

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

    # Run line counting
    count_project_lines(base_path, dev_root, exclusion_config)
