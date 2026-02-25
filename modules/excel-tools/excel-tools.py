"""
Excel Tools — Consolidated Utility

Menu-driven CLI combining:
  1. Unprotect & Unhide sheets
  2. Re-protect & Re-hide sheets
  3. Strip external workbook links
  4. Find & Replace in formulas
  5. Dump all formulas (debug)
  6. Compare workbooks
  7. Generate Lumen invoices (domain-specific)
  8. Clear all tab colors

Uses direct XML manipulation (zipfile) — no openpyxl — so conditional
formatting, external links, and other Excel features are never corrupted
during save.

Usage:
    python excel-tools.py
"""

import calendar  # noqa: F401  (used in generate path, imported for completeness)
import getpass
import html
import json
import os
import re
import shutil
import sys
import tempfile
import zipfile
from datetime import datetime
from xml.etree import ElementTree as ET


# ── Excel XML namespaces ─────────────────────────────────────────────────────
NS = {
    "sp": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
    "r":  "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
}

# ── Regex patterns (shared across options) ───────────────────────────────────
# Matches any <f ...>...</f> formula element
FORMULA_RE = re.compile(r"(<f(?:\s[^>]*)?>)(.*?)(</f>)", re.DOTALL)
# Matches the r= attribute of an enclosing <c> cell element
CELL_REF_RE = re.compile(r'<c\b[^>]*\br="([A-Z]{1,3}\d+)"')
# Matches shared formula references (self-closing, no formula text stored)
SHARED_REF_RE = re.compile(r'<f\s+t="shared"\s+si="\d+"\s*/>')
# Matches <f> elements containing external workbook references ([1], [2], …)
EXTERNAL_FORMULA_RE = re.compile(
    r"<f(?:\s[^>]*)?>(?=[^<]*\[[0-9]+\])[^<]*</f>"
)

# ── Sheet protection options ──────────────────────────────────────────────
# Each entry: (xml_attribute, dialog_label, inverted_semantics)
#
# inverted=True  → selectLockedCells / selectUnlockedCells
#                  XML "0" = user IS allowed  (dialog checkbox ✓, default)
#                  XML "1" = user is NOT allowed
# inverted=False → all other permissions
#                  XML "0" = user is NOT allowed  (default)
#                  XML "1" = user IS allowed  (dialog checkbox ✓)
PROTECTION_OPTIONS: list[tuple[str, str, bool]] = [
    ("selectLockedCells",   "Select locked cells",           True),
    ("selectUnlockedCells", "Select unlocked cells",         True),
    ("formatCells",         "Format cells",                  False),
    ("formatColumns",       "Format columns",                False),
    ("formatRows",          "Format rows",                   False),
    ("insertColumns",       "Insert columns",                False),
    ("insertRows",          "Insert rows",                   False),
    ("insertHyperlinks",    "Insert hyperlinks",             False),
    ("deleteColumns",       "Delete columns",                False),
    ("deleteRows",          "Delete rows",                   False),
    ("sort",                "Sort",                          False),
    ("autoFilter",          "Use AutoFilter",                False),
    ("pivotTables",         "Use PivotTable and PivotChart", False),
    ("objects",             "Edit objects",                  False),
    ("scenarios",           "Edit scenarios",                False),
]

# Matches Excel's default "Protect Sheet" dialog: only the two Select options
# are checked; everything else is unchecked (not allowed).
DEFAULT_ALLOW: dict[str, bool] = {
    attr: inverted  # inverted=True → allowed by default; False → not allowed
    for attr, _, inverted in PROTECTION_OPTIONS
}


# ── Terminal UI ───────────────────────────────────────────────────────────────
# Enable VT/ANSI escape processing on Windows 10+ consoles.
if sys.platform == "win32":
    try:
        import ctypes as _ctypes
        _ctypes.windll.kernel32.SetConsoleMode(
            _ctypes.windll.kernel32.GetStdHandle(-11), 7
        )
    except Exception:
        pass

# ANSI colour codes — match PowerShell console ForegroundColor names.
CYAN   = "\033[96m"
YELLOW = "\033[93m"
GREEN  = "\033[92m"
WHITE  = "\033[97m"
GRAY   = "\033[90m"
RED    = "\033[91m"
BOLD   = "\033[1m"
RESET  = "\033[0m"

# Unbuffered single-keypress input — msvcrt on Windows, tty/termios on Unix.
try:
    import msvcrt as _msvcrt
    _HAS_CBREAK = True
except ImportError:
    _HAS_CBREAK = False


def _getch() -> tuple[bool, str]:
    """
    Read one keypress without echoing.
    Returns (is_special, char); is_special=True for arrow / function keys.
    Windows special-key second bytes: H=up, P=down, M=right, K=left.
    """
    if _HAS_CBREAK:
        ch = _msvcrt.getwch()
        if ch in ("\x00", "\xe0"):      # extended key prefix
            return True, _msvcrt.getwch()
        return False, ch
    # Unix fallback
    try:
        import tty
        import termios
        fd  = sys.stdin.fileno()
        old = termios.tcgetattr(fd)
        try:
            tty.setraw(fd)
            ch = sys.stdin.read(1)
            if ch == "\x1b":
                rest = sys.stdin.read(2)
                if rest == "[A":
                    return True, "H"
                if rest == "[B":
                    return True, "P"
                return False, "\x1b"
            return False, ch
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old)
    except Exception:
        return False, ""


_BOX_WIDTH = 46   # total width: ╔ + 44 inner chars + ╗


def _box_header(title: str) -> None:
    """Print a cyan double-line box header matching the PowerShell console style."""
    inner  = _BOX_WIDTH - 2           # 44
    padded = title[: inner - 2]       # truncate if title exceeds 42 chars
    print(f"\n{CYAN}╔{'═' * inner}╗{RESET}")
    print(f"{CYAN}║{RESET}  {padded:<{inner - 2}}{CYAN}║{RESET}")
    print(f"{CYAN}╚{'═' * inner}╝{RESET}")


def _arrow_menu(items: list[tuple[str, str]], default: int = 0) -> str | None:
    """
    Render an arrow-key navigable menu matching the PowerShell Show-ArrowMenu
    style.

    items:   list of (key, label) pairs; the selected key string is returned.
    default: initial highlighted index (0-based position within items).

    Keys: ↑↓ navigate · Enter select · digit shortcut · Esc → None.

    Redraws item rows in-place via ANSI cursor movement so output above
    (e.g. the box header) remains visible.
    """
    if not _HAS_CBREAK:
        # Plain text fallback
        for key, label in items:
            print(f"  {YELLOW}{key}.{RESET} {label}")
        raw = input(f"\n  {GRAY}Select: {RESET}").strip()
        return raw if raw else None

    sel = max(0, min(default, len(items) - 1))
    H   = len(items) + 2   # item lines + blank line + hint line

    def _draw(first: bool = False) -> None:
        if not first:
            sys.stdout.write(f"\033[{H}A")   # cursor up H lines
        for i, (key, label) in enumerate(items):
            sys.stdout.write("\033[2K\r")
            if i == sel:
                sys.stdout.write(
                    f"  {GREEN}>{RESET} {YELLOW}{key}.{RESET}"
                    f" {GREEN}{label}{RESET}\n"
                )
            else:
                sys.stdout.write(
                    f"    {GRAY}{key}.{RESET} {WHITE}{label}{RESET}\n"
                )
        sys.stdout.write("\033[2K\r\n")
        sys.stdout.write(
            f"\033[2K\r  {GRAY}↑↓ navigate · Enter select"
            f" · or type number{RESET}\n"
        )
        sys.stdout.flush()

    _draw(first=True)

    while True:
        special, ch = _getch()
        if special:
            if ch == "H":           # up arrow
                sel = (sel - 1) % len(items)
                _draw()
            elif ch == "P":         # down arrow
                sel = (sel + 1) % len(items)
                _draw()
        else:
            if ch in ("\r", "\n"):  # Enter — confirm
                return items[sel][0]
            elif ch in ("\x1b", "q", "Q"):  # Escape or Q
                return None
            else:
                # Digit shortcut: jump and select immediately
                for i, (key, _) in enumerate(items):
                    if ch == key:
                        sel = i
                        _draw()
                        return key


def _checkbox_list(
    title:          str,
    labels:         list[str],
    checked:        list[bool] | None = None,
    allow_all_none: bool = True,
) -> list[bool] | None:
    """
    Arrow-key navigable checkbox list matching Show-CheckboxSelection style.

    title:          displayed in the cyan box header
    labels:         display text for each item
    checked:        initial checked state (defaults to all False)
    allow_all_none: enable A=all / N=none keyboard shortcuts

    Keys: ↑↓ navigate · Space toggle · Enter confirm · Esc → None.

    Fallback (no msvcrt): numbered comma-separated toggle loop.
    """
    state = list(checked) if checked is not None else [False] * len(labels)
    sel   = 0
    H     = len(labels) + 2   # label lines + blank line + hint line

    hint_parts = ["↑↓ navigate", "Space toggle", "Enter confirm"]
    if allow_all_none:
        hint_parts += ["A all", "N none"]
    hint_parts.append("Esc cancel")
    hint = " · ".join(hint_parts)

    if not _HAS_CBREAK:
        # Numbered fallback
        while True:
            print(f"\n{CYAN}--- {title} ---{RESET}")
            for i, label in enumerate(labels, 1):
                mark = "✓" if state[i - 1] else " "
                print(f"  {YELLOW}{i:2d}.{RESET} [{mark}] {label}")
            an_hint = "A=all · N=none · " if allow_all_none else ""
            raw = input(
                f"\n  {GRAY}Toggle (comma-separated, {an_hint}blank=done):"
                f" {RESET}"
            ).strip().upper()
            if not raw:
                return state
            if allow_all_none and raw == "A":
                state = [True] * len(labels)
            elif allow_all_none and raw == "N":
                state = [False] * len(labels)
            else:
                try:
                    for token in raw.split(","):
                        idx = int(token.strip()) - 1
                        if 0 <= idx < len(labels):
                            state[idx] = not state[idx]
                except ValueError:
                    print(f"  {RED}Invalid input — enter numbers only.{RESET}")
        return state  # unreachable but satisfies linters

    _box_header(title)
    print()   # blank line between box header and first item

    def _draw(first: bool = False) -> None:
        if not first:
            sys.stdout.write(f"\033[{H}A")
        for i, label in enumerate(labels):
            sys.stdout.write("\033[2K\r")
            mark = f"{GREEN}✓{RESET}" if state[i] else " "
            if i == sel:
                sys.stdout.write(
                    f"  {GREEN}>{RESET} [{mark}] {GREEN}{label}{RESET}\n"
                )
            else:
                sys.stdout.write(
                    f"    [{mark}] {WHITE}{label}{RESET}\n"
                )
        sys.stdout.write("\033[2K\r\n")
        sys.stdout.write(f"\033[2K\r  {GRAY}{hint}{RESET}\n")
        sys.stdout.flush()

    _draw(first=True)

    while True:
        special, ch = _getch()
        if special:
            if ch == "H":               # up
                sel = (sel - 1) % len(labels)
                _draw()
            elif ch == "P":             # down
                sel = (sel + 1) % len(labels)
                _draw()
        else:
            if ch == " ":               # Space = toggle
                state[sel] = not state[sel]
                _draw()
            elif ch in ("\r", "\n"):    # Enter = confirm
                return state
            elif ch == "\x1b":          # Esc = cancel
                return None
            elif allow_all_none and ch in ("a", "A"):
                state = [True] * len(labels)
                _draw()
            elif allow_all_none and ch in ("n", "N"):
                state = [False] * len(labels)
                _draw()


# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  SHARED CORE                                                             ║
# ╚══════════════════════════════════════════════════════════════════════════╝

def _hash_password(password: str) -> str:
    """
    Hash a password using Excel's legacy sheet protection algorithm.
    Returns the hash as an uppercase hex string (e.g., "CC45").
    """
    if not password:
        return ""
    pwd_hash = 0
    for i, char in enumerate(password, 1):
        val = ord(char) << i
        pwd_hash ^= (val & 0x7FFF) | (val >> 15)
    pwd_hash ^= len(password)
    pwd_hash ^= 0xCE4B
    return format(pwd_hash, "04X")


def _xml_escape(text: str) -> str:
    """
    Escape text for use inside XML content (formula text).
    Escapes &, <, and > — Excel stores > as &gt; and may mis-parse
    the <> operator if left unescaped.
    """
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def _xml_unescape(text: str) -> str:
    """Unescape XML entities back to plain text for display."""
    return html.unescape(text)


def _get_workbook_info(xlsx_path: str) -> list[dict]:
    """
    Parse workbook.xml to get sheet names, IDs, states, and rIds.
    Returns list of dicts: [{"name", "sheetId", "rId", "state"}, …]
    """
    with zipfile.ZipFile(xlsx_path, "r") as zf:
        wb_xml = zf.read("xl/workbook.xml")
    root = ET.fromstring(wb_xml)
    sheets_elem = root.find("sp:sheets", NS)
    if sheets_elem is None:
        return []
    result = []
    for sheet in sheets_elem.findall("sp:sheet", NS):
        result.append({
            "name":    sheet.get("name", ""),
            "sheetId": sheet.get("sheetId", ""),
            "rId":     sheet.get(f"{{{NS['r']}}}id", ""),
            "state":   sheet.get("state", "visible"),
        })
    return result


def _get_sheet_paths(xlsx_path: str) -> dict[str, str]:
    """
    Parse workbook.xml.rels to map rIds to internal zip paths.
    Returns dict: {"rId1": "xl/worksheets/sheet1.xml", …}
    """
    with zipfile.ZipFile(xlsx_path, "r") as zf:
        rels_xml = zf.read("xl/_rels/workbook.xml.rels")
    root = ET.fromstring(rels_xml)
    mapping = {}
    for rel in root:
        rid    = rel.get("Id", "")
        target = rel.get("Target", "")
        if not target.startswith("/"):
            target = "xl/" + target
        mapping[rid] = target
    return mapping


def _modify_xlsx(xlsx_path: str, modifications: dict,
                 exclude: set[str] | None = None):
    """
    Modify specific XML files inside an xlsx archive in-place.

    modifications: dict mapping internal zip paths to callables.
        Each callable receives raw XML bytes and returns modified XML bytes.
    exclude: optional set of zip path prefixes to omit from the output.
        Example: {"xl/externalLinks/"} removes all files under that path.
    """
    tmp_fd, tmp_path = tempfile.mkstemp(suffix=".xlsx")
    os.close(tmp_fd)
    exclude = exclude or set()

    try:
        with zipfile.ZipFile(xlsx_path, "r") as zf_in:
            with zipfile.ZipFile(tmp_path, "w", zipfile.ZIP_DEFLATED) as zf_out:
                for item in zf_in.infolist():
                    if any(item.filename.startswith(p) for p in exclude):
                        continue
                    data = zf_in.read(item.filename)
                    if item.filename in modifications:
                        data = modifications[item.filename](data)
                    # Preserve original ZipInfo (compression level, timestamps)
                    zf_out.writestr(item, data)
        shutil.move(tmp_path, xlsx_path)
    except Exception:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise


def browse_files(count: int | None = None) -> list[str]:
    """
    Open a file dialog to select Excel files.

    count: if given, the dialog title prompts for exactly that many files.
           No enforcement is done — caller should validate.
    """
    try:
        import tkinter as tk
        from tkinter import filedialog
        title = (
            f"Select {count} Excel File{'s' if count != 1 else ''} to Open"
            if count else "Select Excel Files"
        )
        root = tk.Tk()
        root.withdraw()
        root.attributes("-topmost", True)
        files = filedialog.askopenfilenames(
            title=title,
            filetypes=[
                ("Excel Files", "*.xlsx *.xlsm"),
                ("All Files", "*.*"),
            ],
        )
        root.destroy()
        return list(files)
    except Exception as e:
        print(f"{YELLOW}File dialog unavailable ({e}). Enter paths manually.{RESET}")
        return _manual_file_entry()


def _manual_file_entry() -> list[str]:
    """Fallback: let the user type file paths one per line."""
    print(f"{GRAY}Enter Excel file paths (one per line, blank line to finish):{RESET}")
    files = []
    while True:
        path = input("  > ").strip().strip('"').strip("'")
        if not path:
            break
        if os.path.isfile(path):
            files.append(os.path.abspath(path))
        else:
            print(f"  {RED}File not found:{RESET} {path}")
    return files


def _select_or_reuse_files(current_files: list[str]) -> list[str]:
    """Offer to reuse files from a previous operation or browse for new ones."""
    if current_files:
        print(f"\n{CYAN}Files from last operation ({len(current_files)}):{RESET}")
        for f in current_files:
            print(f"  {WHITE}{f}{RESET}")
        reuse = input(
            f"\n  {YELLOW}Reuse these files?{RESET} {GRAY}(Y/n):{RESET} "
        ).strip().upper()
        if reuse != "N":
            return current_files

    files = browse_files()
    if not files:
        print(f"  {GRAY}No files selected.{RESET}")
        return []
    return [os.path.abspath(f) for f in files]


def _prompt_password() -> str:
    """Prompt for a sheet protection password (hidden input)."""
    return getpass.getpass(
        f"  {YELLOW}Sheet protection password{RESET} {GRAY}(blank if none):{RESET} "
    )


def _load_config() -> dict:
    """
    Load excel-tools.json from the same directory as this script.
    Returns an empty dict if the file is not found or cannot be parsed.
    """
    config_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "excel-tools.json"
    )
    if not os.path.isfile(config_path):
        return {}
    with open(config_path, "r", encoding="utf-8") as fh:
        return json.load(fh)


# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  OPTIONS 1 & 2 — UNPROTECT / UNHIDE  and  RE-PROTECT / RE-HIDE          ║
# ╚══════════════════════════════════════════════════════════════════════════╝

def _prompt_protection_settings(sheet_name: str) -> dict[str, bool]:
    """
    Interactively configure per-sheet protection options via checkbox list.

    Uses arrow-key navigation when available (msvcrt), falls back to
    numbered comma-separated toggle otherwise.

    Returns a dict mapping XML attribute names to bool (True = user allowed).
    """
    labels  = [label for _, label, _ in PROTECTION_OPTIONS]
    initial = [DEFAULT_ALLOW[attr] for attr, _, _ in PROTECTION_OPTIONS]
    result  = _checkbox_list(
        f'Protection: "{sheet_name}"', labels, initial, allow_all_none=True
    )
    if result is None:      # Esc = keep defaults
        return dict(DEFAULT_ALLOW)
    return {attr: result[i] for i, (attr, _, _) in enumerate(PROTECTION_OPTIONS)}


def add_protection_to_sheet(sheet_xml_bytes: bytes, pwd_hash: str,
                             allow: dict[str, bool] | None = None) -> bytes:
    """
    Add (or replace) a <sheetProtection> element in a sheet XML.

    allow: optional dict mapping XML attribute names to bool (True = user is
           allowed that action). When None, Excel's default dialog state is
           used — only 'Select locked/unlocked cells' are permitted, matching
           the screenshot defaults. When provided, all 15 permission attributes
           are emitted explicitly so the intent is self-documenting in the XML.
    """
    content = sheet_xml_bytes.decode("utf-8")

    # Remove any existing protection so we can replace cleanly
    if "sheetProtection" in content:
        content = re.sub(r"<[^<]*sheetProtection[^>]*/\s*>", "", content)

    parts = ['sheet="1"']
    if pwd_hash:
        parts.append(f'password="{pwd_hash}"')

    if allow is not None:
        # Emit all permission attributes explicitly for transparency.
        # ALL 15 sheetProtection attrs use the same semantics:
        #   "0" = user IS allowed that action
        #   "1" = user is BLOCKED from that action
        # (The 'inverted' flag in PROTECTION_OPTIONS only controls DEFAULT_ALLOW,
        #  not the XML value formula.)
        for attr, _, _inverted in PROTECTION_OPTIONS:
            allowed = allow.get(attr, DEFAULT_ALLOW[attr])
            xml_val = "0" if allowed else "1"
            parts.append(f'{attr}="{xml_val}"')

    protection_elem = f'<sheetProtection {" ".join(parts)}/>'

    # Insert after </sheetData> or <sheetData/>
    if "</sheetData>" in content:
        content = content.replace("</sheetData>",
                                  f"</sheetData>{protection_elem}", 1)
    elif re.search(r"<sheetData\s*/>", content):
        content = re.sub(r"(<sheetData\s*/>)",
                         rf"\1{protection_elem}", content, count=1)

    return content.encode("utf-8")


def remove_protection_from_sheet(sheet_xml_bytes: bytes) -> bytes:
    """Remove all <sheetProtection> elements from a sheet XML."""
    content = sheet_xml_bytes.decode("utf-8")
    # Remove self-closing form: <sheetProtection … />
    content = re.sub(r"<[^<]*sheetProtection[^>]*/\s*>", "", content)
    # Remove paired form: <sheetProtection …>…</sheetProtection>
    content = re.sub(
        r"<[^<]*sheetProtection[^>]*>.*?</[^<]*sheetProtection>",
        "", content, flags=re.DOTALL,
    )
    return content.encode("utf-8")


def unprotect_and_unhide(files: list[str], password: str):
    """Unprotect and unhide ALL sheets in the given workbooks."""
    for filepath in files:
        print(f"\n{CYAN}Processing:{RESET} {filepath}")

        try:
            sheets_info = _get_workbook_info(filepath)
            sheet_paths = _get_sheet_paths(filepath)
        except Exception as e:
            print(f"  {RED}ERROR{RESET} reading workbook: {e}")
            continue

        modifications = {}
        changes_made  = False

        for sheet in sheets_info:
            xml_path      = sheet_paths.get(sheet["rId"], "")
            was_hidden    = sheet["state"] != "visible"
            was_protected = False

            if xml_path:
                try:
                    with zipfile.ZipFile(filepath, "r") as zf:
                        s_xml = zf.read(xml_path).decode("utf-8")
                    was_protected = "sheetProtection" in s_xml
                except Exception:
                    pass

            if was_protected and xml_path:
                modifications[xml_path] = remove_protection_from_sheet
                changes_made = True
                print(f"  {GREEN}Unprotected:{RESET}  {sheet['name']}")

            if was_hidden:
                changes_made = True
                print(f"  {GREEN}Unhid:{RESET}        {sheet['name']}")

            if not was_hidden and not was_protected:
                print(f"  {GRAY}No changes:{RESET}   {sheet['name']}")

        hidden_sheets = [s for s in sheets_info if s["state"] != "visible"]
        if hidden_sheets:
            def _unhide(xml_bytes):
                content = xml_bytes.decode("utf-8")
                content = re.sub(
                    r'(<sheet\b[^>]*?)\s+state="(?:hidden|veryHidden)"',
                    r"\1", content,
                )
                return content.encode("utf-8")
            modifications["xl/workbook.xml"] = _unhide

        if changes_made:
            try:
                _modify_xlsx(filepath, modifications)
                print(f"  {GREEN}Saved:{RESET} {filepath}")
            except Exception as e:
                print(f"  {RED}ERROR saving:{RESET} {e}")
        else:
            print(f"  {GRAY}No changes needed.{RESET}")


def reprotect_and_rehide(files: list[str], password: str):
    """
    Re-protect ALL sheets and re-hide user-selected sheets.
    Reads sheet names from all files (union) so the user can pick
    which ones to hide; all workbooks assumed to share the same structure.
    """
    if not files:
        return

    try:
        sheets_info = _get_workbook_info(files[0])
    except Exception as e:
        print(f"  {RED}ERROR{RESET} reading workbook: {e}")
        return

    sheet_names    = [s["name"] for s in sheets_info]
    seen_names     = set(sheet_names)
    file_sheet_map = {files[0]: list(sheet_names)}

    if len(files) > 1:
        print(f"\n{CYAN}Scanning sheet structure across all files…{RESET}")
        for filepath in files[1:]:
            try:
                other_info  = _get_workbook_info(filepath)
                other_names = [s["name"] for s in other_info]
                file_sheet_map[filepath] = other_names
                for name in other_names:
                    if name not in seen_names:
                        sheet_names.append(name)
                        seen_names.add(name)
            except Exception as e:
                print(
                    f"  {YELLOW}WARNING:{RESET} Could not read"
                    f" {os.path.basename(filepath)}: {e}"
                )

        if len(seen_names) > len(sheets_info):
            print(f"  {YELLOW}Note:{RESET} Not all files share the same tabs.")
        for name in sheet_names:
            count = sum(1 for names in file_sheet_map.values() if name in names)
            if count < len(files):
                print(
                    f"    {YELLOW}\"{name}\"{RESET}"
                    f" — present in {count}/{len(files)} file(s)"
                )
        print(f"  {GRAY}{len(files)} file(s) scanned.{RESET}")

    # ── Select sheets to re-hide ──────────────────────────────────────────
    hide_checked = _checkbox_list(
        "Select sheets to re-hide",
        sheet_names,
        [False] * len(sheet_names),
    )
    if hide_checked is None:
        sheets_to_hide = []   # Esc = hide none
    else:
        sheets_to_hide = [n for n, c in zip(sheet_names, hide_checked) if c]

    if sheets_to_hide and set(sheets_to_hide) >= set(sheet_names):
        print(
            f"  {YELLOW}WARNING:{RESET} Can't hide all sheets."
            f" Keeping first sheet visible."
        )
        sheets_to_hide = [n for n in sheets_to_hide if n != sheet_names[0]]

    if sheets_to_hide:
        print(
            f"\n  {GRAY}Sheets to re-hide:"
            f" {', '.join(sheets_to_hide)}{RESET}"
        )
    else:
        print(f"\n  {GRAY}No sheets will be hidden.{RESET}")
    print(f"  {GRAY}All sheets will be re-protected.{RESET}")

    # ── Custom protection settings ────────────────────────────────────────
    print(
        f"\n{CYAN}Default protection:{RESET} Select locked cells ✓,"
        f" Select unlocked cells ✓"
    )
    print(
        f"  {GRAY}All other actions (format, insert, delete, sort, etc.)"
        f" are blocked by default.{RESET}"
    )
    print(
        f"  {GRAY}Leave all unchecked to use defaults for every sheet.{RESET}"
    )

    custom_checked = _checkbox_list(
        "Custom protection settings",
        sheet_names,
        [False] * len(sheet_names),
        allow_all_none=True,
    )

    custom_protection: dict[str, dict[str, bool]] = {}
    if custom_checked is not None:
        for name, c in zip(sheet_names, custom_checked):
            if c:
                custom_protection[name] = _prompt_protection_settings(name)

    if custom_protection:
        print(
            f"\n  {CYAN}Custom settings configured for:{RESET}"
            f" {', '.join(custom_protection.keys())}"
        )
    # ─────────────────────────────────────────────────────────────────────

    pwd_hash = _hash_password(password) if password else ""

    for filepath in files:
        print(f"\n{CYAN}Restoring:{RESET} {filepath}")
        if not os.path.isfile(filepath):
            print(f"  {RED}ERROR:{RESET} File not found, skipping.")
            continue

        try:
            file_sheets     = _get_workbook_info(filepath)
            sheet_paths_map = _get_sheet_paths(filepath)
        except Exception as e:
            print(f"  {RED}ERROR{RESET} reading workbook: {e}")
            continue

        modifications = {}

        for sheet in file_sheets:
            xml_path = sheet_paths_map.get(sheet["rId"], "")
            if not xml_path:
                continue

            sheet_allow = custom_protection.get(sheet["name"])  # None = defaults
            def _make_protect(ph=pwd_hash, allow=sheet_allow):
                def _protect(xml_bytes):
                    return add_protection_to_sheet(xml_bytes, ph, allow)
                return _protect
            modifications[xml_path] = _make_protect()
            custom_tag = f" {CYAN}(custom){RESET}" if sheet_allow is not None else ""
            print(f"  {GREEN}Re-protected:{RESET}  {sheet['name']}{custom_tag}")

        if sheets_to_hide:
            file_sheet_names = {s["name"] for s in file_sheets}
            applicable = [n for n in sheets_to_hide if n in file_sheet_names]
            skipped    = [n for n in sheets_to_hide if n not in file_sheet_names]

            if applicable:
                def _make_hide(names=applicable):
                    def _hide(xml_bytes):
                        content = xml_bytes.decode("utf-8")
                        for name in names:
                            escaped = re.escape(name)
                            # Insert state="hidden" immediately before r:id= to
                            # match Excel's expected attribute order: name, sheetId,
                            # state, r:id
                            content = re.sub(
                                rf'(<sheet\b[^>]*name="{escaped}"[^>]*?)'
                                rf'(r:id="[^"]*")',
                                rf'\1state="hidden" \2',
                                content,
                            )
                        return content.encode("utf-8")
                    return _hide
                modifications["xl/workbook.xml"] = _make_hide()
                for name in applicable:
                    print(f"  {GREEN}Re-hid:{RESET}        {name}")

            for name in skipped:
                print(
                    f"  {GRAY}Skipped hide:{RESET}  {name}"
                    f" {GRAY}(not in this file){RESET}"
                )

        if modifications:
            try:
                _modify_xlsx(filepath, modifications)
                print(f"  {GREEN}Saved:{RESET} {filepath}")
            except Exception as e:
                print(f"  {RED}ERROR saving:{RESET} {e}")


# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  OPTION 3 — STRIP EXTERNAL WORKBOOK LINKS                                ║
# ╚══════════════════════════════════════════════════════════════════════════╝

def strip_external_formulas(sheet_xml_bytes: bytes) -> bytes:
    """Remove <f> elements that reference external workbooks ([1], [2], …)."""
    content = sheet_xml_bytes.decode("utf-8")
    content = EXTERNAL_FORMULA_RE.sub("", content)
    return content.encode("utf-8")


def clean_workbook_external_refs(wb_xml_bytes: bytes) -> bytes:
    """Remove <externalReferences> block and external <definedName> entries."""
    content = wb_xml_bytes.decode("utf-8")
    content = re.sub(
        r"<externalReferences[^>]*>.*?</externalReferences>",
        "", content, flags=re.DOTALL,
    )
    content = re.sub(r"<externalReferences[^>]*/\s*>", "", content)
    content = re.sub(
        r"<definedName\b[^>]*>(?=[^<]*\[[0-9]+\])[^<]*</definedName>",
        "", content,
    )
    return content.encode("utf-8")


def clean_workbook_rels(rels_xml_bytes: bytes) -> bytes:
    """Remove externalLink relationships from workbook.xml.rels."""
    content = rels_xml_bytes.decode("utf-8")
    content = re.sub(
        r'<Relationship\b[^>]*Target="externalLinks/[^"]*"[^>]*/?>',
        "", content,
    )
    return content.encode("utf-8")


def clean_content_types(ct_xml_bytes: bytes) -> bytes:
    """Remove externalLink entries from [Content_Types].xml."""
    content = ct_xml_bytes.decode("utf-8")
    content = re.sub(
        r'<Override\b[^>]*PartName="/xl/externalLinks/[^"]*"[^>]*/?>',
        "", content,
    )
    return content.encode("utf-8")


def strip_external_links(files: list[str]):
    """
    Remove all external workbook links from the given Excel files.

    For each file:
      1. Sheet XMLs: remove external <f> formulas, keeping cached <v> values.
      2. workbook.xml: remove <externalReferences> and external <definedName>s.
      3. workbook.xml.rels: remove externalLink relationships.
      4. [Content_Types].xml: remove externalLink content type entries.
      5. xl/externalLinks/: removed from the archive entirely.
    """
    for filepath in files:
        print(f"\n{CYAN}Processing:{RESET} {filepath}")
        if not os.path.isfile(filepath):
            print(f"  {RED}ERROR:{RESET} File not found, skipping.")
            continue

        has_external_links = False
        with zipfile.ZipFile(filepath, "r") as zf:
            for name in zf.namelist():
                if name.startswith("xl/externalLinks/"):
                    has_external_links = True
                    break

        if not has_external_links:
            print(f"  {GRAY}No external links found.{RESET}")
            continue

        try:
            sheets_info = _get_workbook_info(filepath)
            sheet_paths = _get_sheet_paths(filepath)
        except Exception as e:
            print(f"  {RED}ERROR{RESET} reading workbook: {e}")
            continue

        modifications = {}
        total_removed = 0

        for sheet in sheets_info:
            xml_path = sheet_paths.get(sheet["rId"], "")
            if not xml_path:
                continue
            try:
                with zipfile.ZipFile(filepath, "r") as zf:
                    s_xml = zf.read(xml_path).decode("utf-8")
            except Exception:
                continue

            matches = EXTERNAL_FORMULA_RE.findall(s_xml)
            if not matches:
                continue

            modifications[xml_path] = strip_external_formulas
            total_removed += len(matches)
            print(
                f"  {GREEN}{sheet['name']}:{RESET}"
                f" stripped {len(matches)} external formula(s)"
            )

        modifications["xl/workbook.xml"]           = clean_workbook_external_refs
        modifications["xl/_rels/workbook.xml.rels"] = clean_workbook_rels
        modifications["[Content_Types].xml"]        = clean_content_types

        exclude = {"xl/externalLinks/", "xl/calcChain.xml"}

        try:
            _modify_xlsx(filepath, modifications, exclude=exclude)
            if total_removed:
                print(
                    f"  {GREEN}Converted{RESET}"
                    f" {total_removed} formula(s) to static values."
                )
            print(f"  {GREEN}Removed{RESET} external link files from archive.")
            print(f"  {GREEN}Saved:{RESET} {filepath}")
        except Exception as e:
            print(f"  {RED}ERROR saving:{RESET} {e}")


# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  OPTION 4 — FIND & REPLACE IN FORMULAS                                   ║
# ╚══════════════════════════════════════════════════════════════════════════╝

def find_replace_formulas(files: list[str]):
    """
    Find and replace text within formulas across all sheets.
    Only modifies content inside <f> elements — values, formatting, and
    everything else are untouched.

    Handles XML entity encoding; shows a preview before applying changes.
    """
    print(f"\n  {GRAY}NOTE: Enter formulas as they appear in Excel (without leading '=').{RESET}")
    print(f"  {GRAY}Example: to change =SUM(A1:A10) to =SUM(B1:B10),{RESET}")
    print(f"  {GRAY}search for 'SUM(A1:A10)' and replace with 'SUM(B1:B10)'.{RESET}")
    print(f"  {GRAY}Operators like <> are handled automatically.{RESET}")
    print(f"  {GRAY}The @ implicit intersection operator (Excel 365) is stripped{RESET}")
    print(f"  {GRAY}automatically since it is not stored in the XML.{RESET}\n")

    search_str = input(f"  {YELLOW}Search for:{RESET}     ").strip()
    if not search_str:
        print(f"  {GRAY}No search string entered. Aborting.{RESET}")
        return

    replace_str = input(f"  {YELLOW}Replace with:{RESET}   ").strip()

    if "@" in search_str or "@" in replace_str:
        search_str  = search_str.replace("@", "")
        replace_str = replace_str.replace("@", "")
        print(f"  {GRAY}(Stripped '@' implicit intersection operators from input){RESET}")

    print(f"\n  {CYAN}Find:{RESET}    '{search_str}'")
    print(f"  {CYAN}Replace:{RESET} '{replace_str}'")

    search_lower   = search_str.lower()
    search_pattern = re.compile(re.escape(search_str), re.IGNORECASE)

    # First pass: preview matches
    all_matches = []
    for filepath in files:
        try:
            sheets_info = _get_workbook_info(filepath)
            sheet_paths = _get_sheet_paths(filepath)
        except Exception as e:
            print(f"  {RED}ERROR{RESET} reading {os.path.basename(filepath)}: {e}")
            continue

        for sheet in sheets_info:
            xml_path = sheet_paths.get(sheet["rId"], "")
            if not xml_path:
                continue
            try:
                with zipfile.ZipFile(filepath, "r") as zf:
                    sheet_xml = zf.read(xml_path).decode("utf-8")
            except Exception:
                continue

            for f_match in FORMULA_RE.finditer(sheet_xml):
                formula_text = _xml_unescape(f_match.group(2))
                if search_lower not in formula_text.lower():
                    continue
                preceding = sheet_xml[: f_match.start()]
                cell_ref  = "?"
                c_matches = list(CELL_REF_RE.finditer(preceding))
                if c_matches:
                    cell_ref = c_matches[-1].group(1)
                all_matches.append((filepath, sheet["name"], cell_ref, formula_text))

    if not all_matches:
        print(f"\n  {YELLOW}No formulas containing '{search_str}' found.{RESET}")
        return

    print(
        f"\n  {CYAN}Found {len(all_matches)} formula(s)"
        f" containing '{search_str}':{RESET}\n"
    )
    current_file = None
    max_preview  = 50
    for i, (filepath, sheet_name, cell_ref, formula_text) in enumerate(all_matches):
        if filepath != current_file:
            current_file = filepath
            print(f"  {WHITE}{os.path.basename(filepath)}:{RESET}")
        if i < max_preview:
            new_display = search_pattern.sub(lambda _: replace_str, formula_text)
            print(f"    {sheet_name}!{cell_ref}: ={formula_text}")
            print(f"      {GREEN}->{RESET} ={new_display}")
    if len(all_matches) > max_preview:
        print(f"    {GRAY}… and {len(all_matches) - max_preview} more{RESET}")

    print(f"\n  {GRAY}Mark replaced formulas as array formulas (Ctrl+Shift+Enter)?{RESET}")
    print(f"  {GRAY}Required for formulas using array math like (range=val)*(range=val).{RESET}")
    force_array = (
        input(f"  {YELLOW}Force array formula?{RESET} {GRAY}(y/N):{RESET} ")
        .strip().upper() == "Y"
    )

    confirm = input(
        f"\n  {YELLOW}Apply {len(all_matches)} replacement(s)?{RESET}"
        f" {GRAY}(y/N):{RESET} "
    ).strip().upper()
    if confirm != "Y":
        print(f"  {GRAY}Cancelled.{RESET}")
        return

    # Second pass: apply replacements
    for filepath in files:
        try:
            sheets_info = _get_workbook_info(filepath)
            sheet_paths = _get_sheet_paths(filepath)
        except Exception:
            continue

        modifications = {}
        file_count    = 0

        for sheet in sheets_info:
            xml_path = sheet_paths.get(sheet["rId"], "")
            if not xml_path:
                continue
            try:
                with zipfile.ZipFile(filepath, "r") as zf:
                    sheet_xml = zf.read(xml_path).decode("utf-8")
            except Exception:
                continue

            sheet_matches = sum(
                1 for f_match in FORMULA_RE.finditer(sheet_xml)
                if search_lower in _xml_unescape(f_match.group(2)).lower()
            )
            if sheet_matches == 0:
                continue

            def _make_replace(pat=search_pattern, repl=replace_str,
                              arr=force_array, sxml=sheet_xml):
                def _do_replace(xml_bytes):
                    content = xml_bytes.decode("utf-8")

                    def _replace_in_formula(m):
                        open_tag     = m.group(1)
                        formula_xml  = m.group(2)
                        close_tag    = m.group(3)
                        formula_text = _xml_unescape(formula_xml)
                        if search_lower not in formula_text.lower():
                            return m.group(0)
                        new_text = pat.sub(lambda _: repl, formula_text)
                        new_xml  = _xml_escape(new_text)
                        if arr and 't="array"' not in open_tag:
                            pos = content.find(m.group(0))
                            preceding = content[:pos] if pos >= 0 else ""
                            c_m = list(CELL_REF_RE.finditer(preceding))
                            if c_m:
                                cell_ref = c_m[-1].group(1)
                                open_tag = f'<f t="array" ref="{cell_ref}">'
                        return open_tag + new_xml + close_tag

                    content = FORMULA_RE.sub(_replace_in_formula, content)
                    return content.encode("utf-8")
                return _do_replace

            modifications[xml_path] = _make_replace()
            file_count += sheet_matches

        if modifications:
            try:
                _modify_xlsx(filepath, modifications, exclude={"xl/calcChain.xml"})
                print(
                    f"  {GREEN}{os.path.basename(filepath)}:{RESET}"
                    f" replaced {file_count} formula(s)"
                )
            except Exception as e:
                print(
                    f"  {RED}ERROR saving{RESET}"
                    f" {os.path.basename(filepath)}: {e}"
                )


# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  OPTION 5 — DUMP ALL FORMULAS (DEBUG)                                    ║
# ╚══════════════════════════════════════════════════════════════════════════╝

def dump_formulas(files: list[str]):
    """
    Dump raw formula XML from the first selected file, showing decoded text
    and Python repr to expose hidden/invisible characters.
    """
    for filepath in files[:1]:
        print(f"\n  {CYAN}File:{RESET} {os.path.basename(filepath)}")
        try:
            sheets_info = _get_workbook_info(filepath)
            sheet_paths = _get_sheet_paths(filepath)
        except Exception as e:
            print(f"  {RED}ERROR:{RESET} {e}")
            return

        for sheet in sheets_info:
            xml_path = sheet_paths.get(sheet["rId"], "")
            if not xml_path:
                continue
            try:
                with zipfile.ZipFile(filepath, "r") as zf:
                    sheet_xml = zf.read(xml_path).decode("utf-8")
            except Exception:
                continue

            formulas = list(FORMULA_RE.finditer(sheet_xml))
            if not formulas:
                continue

            print(
                f"\n  {CYAN}--- {sheet['name']}"
                f" ({len(formulas)} formulas) ---{RESET}"
            )
            for f_match in formulas:
                open_tag    = f_match.group(1)
                formula_xml = f_match.group(2)

                preceding = sheet_xml[: f_match.start()]
                cell_ref  = "?"
                c_matches = list(CELL_REF_RE.finditer(preceding))
                if c_matches:
                    cell_ref = c_matches[-1].group(1)

                display  = _xml_unescape(formula_xml)
                tag_info = f" {open_tag}" if open_tag != "<f>" else ""
                print(f"    {YELLOW}{cell_ref}{tag_info}:{RESET}")
                print(f"      {GRAY}raw:{RESET}  {formula_xml}")
                if display != formula_xml:
                    print(f"      {GRAY}text:{RESET} {display}")
                print(f"      {GRAY}repr:{RESET} {repr(formula_xml)}")


# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  OPTION 6 — COMPARE WORKBOOKS                                            ║
# ╚══════════════════════════════════════════════════════════════════════════╝

def _extract_formulas(xlsx_path: str, sheet_xml_path: str) -> dict[str, str]:
    """
    Extract all formulas from a single sheet XML.

    Returns dict mapping cell reference → formula text (decoded/unescaped).
    Shared formulas are resolved: cells referencing a shared formula master
    get the master formula stored (Excel recalculates them from the master
    so the individual cells don't store their own formula text).
    """
    with zipfile.ZipFile(xlsx_path, "r") as zf:
        sheet_xml = zf.read(sheet_xml_path).decode("utf-8")

    formulas = {}

    # First pass: collect explicit formulas (non-empty <f>…</f>)
    for fm in FORMULA_RE.finditer(sheet_xml):
        open_tag     = fm.group(1)
        formula_xml  = fm.group(2)
        formula_text = _xml_unescape(formula_xml)

        preceding = sheet_xml[: fm.start()]
        cell_ref  = "?"
        c_matches = list(CELL_REF_RE.finditer(preceding))
        if c_matches:
            cell_ref = c_matches[-1].group(1)

        if 't="shared"' in open_tag and 'ref="' in open_tag:
            si_match = re.search(r'si="(\d+)"', open_tag)
            if si_match:
                formulas[cell_ref] = f"[shared:si={si_match.group(1)}] {formula_text}"
        elif 't="array"' in open_tag:
            formulas[cell_ref] = f"[array] {formula_text}"
        else:
            formulas[cell_ref] = formula_text

    # Second pass: shared formula references (self-closing, no formula text)
    for sm in SHARED_REF_RE.finditer(sheet_xml):
        preceding = sheet_xml[: sm.start()]
        cell_ref  = "?"
        c_matches = list(CELL_REF_RE.finditer(preceding))
        if c_matches:
            cell_ref = c_matches[-1].group(1)
        si_match = re.search(r'si="(\d+)"', sm.group(0))
        si = si_match.group(1) if si_match else "?"
        formulas[cell_ref] = f"[shared-ref:si={si}]"

    return formulas


def _normalize_formula(formula: str, sheet_name_map: dict[str, str]) -> str:
    """
    Normalize a formula so sheet-name references become canonical positional
    names (Sheet1, Sheet2, …).

    This makes '='January 2026'!K2' and '='Month YYYY'!K2' compare equal.
    Also strips shared/array metadata prefixes for comparison purposes.
    """
    normalized = re.sub(r"^\[(?:shared:si=\d+|array)\]\s*", "", formula)

    for original, canonical in sheet_name_map.items():
        escaped = re.escape(original)
        # Quoted form: ='Sheet Name'!
        normalized = re.sub(rf"'{escaped}'!", f"'{canonical}'!", normalized)
        # Unquoted form (single-word names): =SheetName!
        normalized = re.sub(rf"(?<![']){escaped}!", f"{canonical}!", normalized)

    return normalized


def compare_workbooks(file_a: str, file_b: str) -> list[str]:
    """
    Compare two Excel workbooks and return a list of report lines.

    Sheets are matched by position. Formulas are normalized to remove
    sheet-name differences. Only structural formula logic differences
    are reported.
    """
    report = []
    name_a = os.path.basename(file_a)
    name_b = os.path.basename(file_b)

    sheets_a = _get_workbook_info(file_a)
    sheets_b = _get_workbook_info(file_b)
    paths_a  = _get_sheet_paths(file_a)
    paths_b  = _get_sheet_paths(file_b)

    div  = "=" * 80
    div2 = "-" * 80
    report.append(div)
    report.append("EXCEL WORKBOOK FORMULA COMPARISON")
    report.append(div)
    report.append(f"  File A: {name_a}")
    report.append(f"  File B: {name_b}")
    report.append(f"  Sheets A: {[s['name'] for s in sheets_a]}")
    report.append(f"  Sheets B: {[s['name'] for s in sheets_b]}")

    if len(sheets_a) != len(sheets_b):
        report.append(
            f"\n  WARNING: Sheet count differs "
            f"({len(sheets_a)} vs {len(sheets_b)}). "
            "Comparing up to the minimum."
        )

    # Build canonical positional names for sheet-name normalization
    sheet_name_map_a: dict[str, str] = {}
    sheet_name_map_b: dict[str, str] = {}
    for i, (sa, sb) in enumerate(zip(sheets_a, sheets_b)):
        canonical = f"_Sheet{i+1}_"
        sheet_name_map_a[sa["name"]] = canonical
        sheet_name_map_b[sb["name"]] = canonical

    pairs = min(len(sheets_a), len(sheets_b))
    for i in range(pairs):
        sa = sheets_a[i]
        sb = sheets_b[i]
        xml_path_a = paths_a.get(sa["rId"], "")
        xml_path_b = paths_b.get(sb["rId"], "")

        report.append(f"\n{div2}")
        report.append(f"SHEET {i+1}: \"{sa['name']}\" (A) vs \"{sb['name']}\" (B)")
        report.append(div2)

        if not xml_path_a or not xml_path_b:
            report.append("  ERROR: Could not locate sheet XML path.")
            continue

        formulas_a = _extract_formulas(file_a, xml_path_a)
        formulas_b = _extract_formulas(file_b, xml_path_b)

        report.append(f"  Formula count:  A={len(formulas_a)},  B={len(formulas_b)}")

        all_cells = sorted(
            set(formulas_a.keys()) | set(formulas_b.keys()),
            key=lambda c: (int(re.search(r"\d+", c).group()), c),
        )

        diffs    = []
        only_a   = []
        only_b   = []
        matching = 0

        for cell in all_cells:
            fa = formulas_a.get(cell)
            fb = formulas_b.get(cell)

            if fa is not None and fb is not None:
                norm_a = _normalize_formula(fa, sheet_name_map_a)
                norm_b = _normalize_formula(fb, sheet_name_map_b)
                if norm_a == norm_b:
                    matching += 1
                else:
                    diffs.append((cell, fa, fb))
            elif fa is not None:
                only_a.append((cell, fa))
            else:
                only_b.append((cell, fb))

        report.append(f"  Matching formulas: {matching}")

        if diffs:
            report.append(f"\n  FORMULA DIFFERENCES ({len(diffs)}):")
            for cell, fa, fb in diffs:
                report.append(f"    {cell}:")
                report.append(f"      A: ={fa}")
                report.append(f"      B: ={fb}")

        if only_a:
            report.append(f"\n  FORMULAS ONLY IN A ({len(only_a)}):")
            for cell, fa in only_a:
                report.append(f"    {cell}: ={fa}")

        if only_b:
            report.append(f"\n  FORMULAS ONLY IN B ({len(only_b)}):")
            for cell, fb in only_b:
                report.append(f"    {cell}: ={fb}")

        if not diffs and not only_a and not only_b:
            report.append("  All formulas match (after normalization).")

    if len(sheets_a) > pairs:
        report.append(f"\n  EXTRA SHEETS IN A (not compared):")
        for s in sheets_a[pairs:]:
            report.append(f"    - {s['name']}")
    if len(sheets_b) > pairs:
        report.append(f"\n  EXTRA SHEETS IN B (not compared):")
        for s in sheets_b[pairs:]:
            report.append(f"    - {s['name']}")

    report.append(f"\n{div}")
    report.append("COMPARISON COMPLETE")
    report.append(div)

    return report


# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  OPTION 7 — GENERATE LUMEN INVOICES (domain-specific)                   ║
# ╚══════════════════════════════════════════════════════════════════════════╝

def _read_site_codes(po_ref_path: str) -> list[str]:
    """
    Read unique site codes from column A of the first sheet in the
    PO reference workbook (configured via excel-tools.json). Skips the header row.
    """
    ns = NS["sp"]

    with zipfile.ZipFile(po_ref_path, "r") as zf:
        ss_xml  = zf.read("xl/sharedStrings.xml").decode("utf-8")
        ss_root = ET.fromstring(ss_xml)
        strings = []
        for si in ss_root.findall(f"./{{{ns}}}si"):
            texts = si.findall(f".//{{{ns}}}t")
            strings.append("".join(t.text or "" for t in texts))

        sheet_xml = zf.read("xl/worksheets/sheet1.xml").decode("utf-8")
        s_root    = ET.fromstring(sheet_xml)

    rows  = s_root.findall(f".//{{{ns}}}row")
    codes = []
    for row in rows[1:]:  # skip header
        for cell in row.findall(f"{{{ns}}}c"):
            ref = cell.get("r", "")
            if ref.startswith("A") and ref[1:].isdigit():
                t      = cell.get("t", "")
                v_elem = cell.find(f"{{{ns}}}v")
                v      = v_elem.text if v_elem is not None else None
                if t == "s" and v is not None:
                    codes.append(strings[int(v)])
                elif v:
                    codes.append(v)

    seen, unique = set(), []
    for code in codes:
        if code not in seen:
            seen.add(code)
            unique.append(code)
    return unique


def _set_c17_value(sheet_xml_bytes: bytes, site_code: str) -> bytes:
    """
    Replace the value of cell C17 in the sheet XML with the given site code.
    Rewrites as an inline string (t="inlineStr") to avoid touching shared strings.
    """
    content = sheet_xml_bytes.decode("utf-8")

    c17_pattern = re.compile(r'(<c\s+r="C17")([^>]*)(>)(.*?)(</c>)', re.DOTALL)
    match = c17_pattern.search(content)

    if not match:
        c17_self   = re.compile(r'<c\s+r="C17"[^/]*/>')
        match_self = c17_self.search(content)
        if match_self:
            replacement = (
                f'<c r="C17" t="inlineStr">'
                f'<is><t>{site_code}</t></is></c>'
            )
            content = (
                content[: match_self.start()]
                + replacement
                + content[match_self.end():]
            )
        else:
            print(f"    {YELLOW}WARNING:{RESET} C17 cell not found in sheet XML.")
        return content.encode("utf-8")

    attrs       = match.group(2)
    attrs       = re.sub(r'\s*t="[^"]*"', "", attrs)
    style_match = re.search(r's="(\d+)"', attrs)
    style_attr  = f' s="{style_match.group(1)}"' if style_match else ""

    replacement = (
        f'<c r="C17"{style_attr} t="inlineStr">'
        f'<is><t>{site_code}</t></is></c>'
    )
    content = content[: match.start()] + replacement + content[match.end():]
    return content.encode("utf-8")


def _resolve_l9_formula(sheet_xml_bytes: bytes, po_number: str) -> bytes:
    """
    Convert cell L9 from a formula to a static inline string value.

    L9 normally contains =INDEX(Reference!…,MATCH($C$17,…)) which resolves
    to the PO number. Replacing it with a static value removes the dependency
    on the Reference sheet at open time.
    """
    content = sheet_xml_bytes.decode("utf-8")

    l9_pattern = re.compile(r'(<c\s+r="L9")([^>]*)(>)(.*?)(</c>)', re.DOTALL)
    match = l9_pattern.search(content)
    if not match:
        return content.encode("utf-8")

    attrs       = match.group(2)
    style_match = re.search(r's="(\d+)"', attrs)
    style_attr  = f' s="{style_match.group(1)}"' if style_match else ""

    replacement = (
        f'<c r="L9"{style_attr} t="inlineStr">'
        f'<is><t>{po_number}</t></is></c>'
    )
    content = content[: match.start()] + replacement + content[match.end():]
    return content.encode("utf-8")


def _read_reference_data(xlsx_path: str, sheet_xml_path: str) -> dict:
    """Read the Reference sheet and return a dict of (col, row) → value."""
    with zipfile.ZipFile(xlsx_path, "r") as zf:
        data = zf.read(sheet_xml_path).decode("utf-8")

    cell_pattern = re.compile(
        r'<c r="([A-Z]+)(\d+)"([^>]*)>(.*?)</c>', re.DOTALL
    )
    ref_data = {}
    for m in cell_pattern.finditer(data):
        col, row_s = m.group(1), m.group(2)
        inner      = m.group(4)
        v_match    = re.search(r"<v>(.*?)</v>", inner)
        if v_match and v_match.group(1):
            ref_data[(col, int(row_s))] = v_match.group(1)
    return ref_data


def _build_po_lookup(ref_data: dict) -> dict[str, str]:
    """Build a site code → PO number mapping from Reference sheet data."""
    code_to_po: dict[str, str] = {}
    for row in range(2, 101):
        code = ref_data.get(("A", row))
        po   = ref_data.get(("D", row))
        if code and code not in code_to_po:
            code_to_po[code] = po or ""
    return code_to_po


def _prepare_invoice_workbook(wb_xml_bytes: bytes) -> bytes:
    """
    Invoice-specific workbook.xml transformation:
      - Strip external references and defined names
      - Hide the Reference (third) sheet
      - Reset activeTab to 0 (Summary)
      - Add fullCalcOnLoad="1" so Excel recalculates C17-dependent formulas
    """
    content = clean_workbook_external_refs(wb_xml_bytes).decode("utf-8")

    # Hide the Reference sheet
    content = re.sub(
        r'(<sheet\b[^>]*name="Reference"[^>]*?)(r:id="[^"]*")',
        r'\1state="hidden" \2',
        content,
    )
    # Reset activeTab so Excel doesn't open on the hidden Reference sheet
    content = re.sub(r' activeTab="\d+"', "", content)
    # Force full recalculation on open
    content = re.sub(r'(<calcPr\b)', r'\1 fullCalcOnLoad="1"', content)

    return content.encode("utf-8")


def generate_invoices(
    template_path:     str,
    po_ref_path:       str,
    output_dir:        str,
    year_month:        str,
    password:          str,
    filename_template: str = "{code}-Invoice {year_month}.xlsx",
):
    """
    Generate one invoice xlsx per site code.

    Steps per invoice:
      1. Copy the MASTER template.
      2. Set C17 to the site code; resolve L9 to the PO number.
      3. Strip external link formulas from all sheets.
      4. Protect all sheets with the given password.
      5. Hide the Reference sheet; reset activeTab; add fullCalcOnLoad.
      6. Remove external link relationship/content-type entries and files.
    """
    site_codes = _read_site_codes(po_ref_path)
    print(
        f"\n  {CYAN}Found {len(site_codes)} site codes:{RESET}"
        f" {', '.join(site_codes)}"
    )

    sheets_info = _get_workbook_info(template_path)
    sheet_paths = _get_sheet_paths(template_path)

    if len(sheets_info) < 3:
        print(f"  {RED}ERROR:{RESET} Template must have at least 3 sheets.")
        return

    sheet2_rId      = sheets_info[1]["rId"]
    sheet2_xml_path = sheet_paths.get(sheet2_rId, "")
    if not sheet2_xml_path:
        print(f"  {RED}ERROR:{RESET} Could not find second sheet XML path.")
        return

    all_sheet_paths = [
        sheet_paths[si["rId"]]
        for si in sheets_info
        if sheet_paths.get(si["rId"])
    ]

    sheet3_rId      = sheets_info[2]["rId"]
    sheet3_xml_path = sheet_paths.get(sheet3_rId, "")
    ref_data  = _read_reference_data(template_path, sheet3_xml_path)
    po_lookup = _build_po_lookup(ref_data)

    pwd_hash = _hash_password(password) if password else ""

    print(f"  {GRAY}Output directory: {output_dir}{RESET}")
    print(f"  {GRAY}Password hash: {pwd_hash if pwd_hash else '(none)'}{RESET}")
    print(f"  {GRAY}PO lookup: {len(po_lookup)} codes mapped{RESET}\n")

    created = 0
    for code in site_codes:
        filename    = filename_template.format(code=code, year_month=year_month)
        output_path = os.path.join(output_dir, filename)
        shutil.copy2(template_path, output_path)

        po_number = po_lookup.get(code, "")
        if not po_number:
            print(f"    {YELLOW}WARNING:{RESET} No PO number found for {code}")

        modifications: dict = {}

        def _make_sheet2_mod(site_code=code, po=po_number, ph=pwd_hash):
            def _mod(xml_bytes):
                xml_bytes = _set_c17_value(xml_bytes, site_code)
                xml_bytes = _resolve_l9_formula(xml_bytes, po)
                xml_bytes = strip_external_formulas(xml_bytes)
                xml_bytes = add_protection_to_sheet(xml_bytes, ph)
                return xml_bytes
            return _mod
        modifications[sheet2_xml_path] = _make_sheet2_mod()

        for sp in all_sheet_paths:
            if sp == sheet2_xml_path:
                continue

            def _make_other_mod(ph=pwd_hash):
                def _mod(xml_bytes):
                    xml_bytes = strip_external_formulas(xml_bytes)
                    xml_bytes = add_protection_to_sheet(xml_bytes, ph)
                    return xml_bytes
                return _mod
            modifications[sp] = _make_other_mod()

        modifications["xl/workbook.xml"]            = _prepare_invoice_workbook
        modifications["xl/_rels/workbook.xml.rels"] = clean_workbook_rels
        modifications["[Content_Types].xml"]        = clean_content_types

        exclude = {"xl/calcChain.xml", "xl/externalLinks/"}

        try:
            _modify_xlsx(output_path, modifications, exclude=exclude)
            print(f"  {GREEN}Created:{RESET} {filename}")
            created += 1
        except Exception as e:
            print(f"  {RED}ERROR creating{RESET} {filename}: {e}")
            if os.path.exists(output_path):
                os.unlink(output_path)

    print(
        f"\n  {CYAN}Done.{RESET} Created {created} of {len(site_codes)} invoices."
    )


# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  OPTION 8 — CLEAR ALL TAB COLORS                                         ║
# ╚══════════════════════════════════════════════════════════════════════════╝

def remove_tab_color_from_sheet(sheet_xml_bytes: bytes) -> bytes:
    """Remove <tabColor> element from a sheet XML, resetting tab to 'no color'."""
    content = sheet_xml_bytes.decode("utf-8")
    # Remove self-closing form: <tabColor … />
    content = re.sub(r"<tabColor\b[^>]*/\s*>", "", content)
    # Remove paired form: <tabColor …>…</tabColor> (defensive; rare in practice)
    content = re.sub(
        r"<tabColor\b[^>]*>.*?</tabColor>", "", content, flags=re.DOTALL
    )
    return content.encode("utf-8")


def clear_tab_colors(files: list[str]):
    """
    Remove all tab colors from every sheet in the given workbooks.

    Tab colors are stored as <tabColor> inside each sheet's <sheetPr> element.
    Removing that element makes Excel display the sheet tab in the default
    (no color) style. The <sheetPr> parent is left intact so other sheet
    properties (e.g. codeName, page setup) are preserved.
    """
    for filepath in files:
        print(f"\n{CYAN}Processing:{RESET} {filepath}")
        if not os.path.isfile(filepath):
            print(f"  {RED}ERROR:{RESET} File not found, skipping.")
            continue

        try:
            sheets_info = _get_workbook_info(filepath)
            sheet_paths = _get_sheet_paths(filepath)
        except Exception as e:
            print(f"  {RED}ERROR{RESET} reading workbook: {e}")
            continue

        modifications = {}
        changes_made  = False

        for sheet in sheets_info:
            xml_path = sheet_paths.get(sheet["rId"], "")
            if not xml_path:
                continue
            try:
                with zipfile.ZipFile(filepath, "r") as zf:
                    s_xml = zf.read(xml_path).decode("utf-8")
            except Exception:
                continue

            if "<tabColor" in s_xml:
                modifications[xml_path] = remove_tab_color_from_sheet
                changes_made = True
                print(f"  {GREEN}Cleared color:{RESET}  {sheet['name']}")
            else:
                print(f"  {GRAY}No color:{RESET}       {sheet['name']}")

        if changes_made:
            try:
                _modify_xlsx(filepath, modifications)
                print(f"  {GREEN}Saved:{RESET} {filepath}")
            except Exception as e:
                print(f"  {RED}ERROR saving:{RESET} {e}")
        else:
            print(f"  {GRAY}No changes needed.{RESET}")


# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  MAIN / MENU                                                             ║
# ╚══════════════════════════════════════════════════════════════════════════╝

_MAIN_MENU = [
    ("1", "Unprotect & Unhide sheets"),
    ("2", "Re-protect & Re-hide sheets"),
    ("3", "Strip external workbook links"),
    ("4", "Find & Replace in formulas"),
    ("5", "Dump all formulas  (debug)"),
    ("6", "Compare workbooks"),
    ("7", "Generate Lumen invoices"),
    ("8", "Clear all tab colors"),
    ("0", "Exit"),
]


def main():
    _box_header("Excel Tools")

    current_files: list[str] = []

    while True:
        print(f"\n{GRAY}{'─' * 44}{RESET}")
        choice = _arrow_menu(_MAIN_MENU)

        if choice is None:      # Esc or Q — exit
            print(f"\n{CYAN}Goodbye.{RESET}\n")
            break

        if choice == "1":
            files = browse_files()
            if not files:
                print(f"  {GRAY}No files selected.{RESET}")
                continue
            current_files = [os.path.abspath(f) for f in files]
            print(f"\n{CYAN}Selected {len(current_files)} file(s):{RESET}")
            for f in current_files:
                print(f"  {WHITE}{f}{RESET}")
            password = _prompt_password()
            unprotect_and_unhide(current_files, password)
            print(
                f"\n{GRAY}Done. Use option 2 to re-protect and re-hide"
                f" when ready.{RESET}"
            )

        elif choice == "2":
            current_files = _select_or_reuse_files(current_files)
            if not current_files:
                continue
            password = _prompt_password()
            reprotect_and_rehide(current_files, password)
            print(f"\n{GRAY}Done.{RESET}")

        elif choice == "3":
            current_files = _select_or_reuse_files(current_files)
            if not current_files:
                continue
            print(f"\n  {YELLOW}WARNING:{RESET} This converts external link formulas to static")
            print(f"  values and removes all external workbook references.")
            print(f"  {RED}This cannot be undone (keep backups!).{RESET}")
            if input(
                f"\n  {YELLOW}Proceed?{RESET} {GRAY}(y/N):{RESET} "
            ).strip().upper() != "Y":
                print(f"  {GRAY}Cancelled.{RESET}")
                continue
            strip_external_links(current_files)
            print(f"\n{GRAY}Done.{RESET}")

        elif choice == "4":
            current_files = _select_or_reuse_files(current_files)
            if not current_files:
                continue
            find_replace_formulas(current_files)
            print(f"\n{GRAY}Done.{RESET}")

        elif choice == "5":
            current_files = _select_or_reuse_files(current_files)
            if not current_files:
                continue
            dump_formulas(current_files)
            print(f"\n{GRAY}Done.{RESET}")

        elif choice == "6":
            # Compare always selects exactly 2 files
            files = browse_files(count=2)
            if not files:
                print(f"  {GRAY}No files selected.{RESET}")
                continue
            if len(files) != 2:
                print(f"  {RED}ERROR:{RESET} Expected 2 files, got {len(files)}.")
                continue
            file_a, file_b = files
            report = compare_workbooks(
                os.path.abspath(file_a), os.path.abspath(file_b)
            )
            # Print report with colour highlights
            for line in report:
                if line.startswith("="):
                    print(f"{CYAN}{line}{RESET}")
                elif line.startswith("-"):
                    print(f"{GRAY}{line}{RESET}")
                elif "DIFFERENCE" in line or "ONLY IN" in line:
                    print(f"{YELLOW}{line}{RESET}")
                elif line.startswith("  A:") or line.startswith("  B:"):
                    print(f"{WHITE}{line}{RESET}")
                elif "All formulas match" in line:
                    print(f"{GREEN}{line}{RESET}")
                elif "ERROR" in line:
                    print(f"{RED}{line}{RESET}")
                elif "WARNING" in line:
                    print(f"{YELLOW}{line}{RESET}")
                else:
                    print(line)

        elif choice == "7":
            cfg = _load_config().get("lumen_invoices", {})
            if not cfg:
                print(
                    f"  {RED}ERROR:{RESET} 'lumen_invoices' section not found"
                    f" in excel-tools.json."
                )
                print(
                    f"  Create excel-tools.json next to this script"
                    f" with the required paths."
                )
                print(f"\n{GRAY}Done.{RESET}")
                continue

            base          = cfg["base_path"]
            tmpl_fld      = cfg["templates_folder"]
            template_path = os.path.join(base, tmpl_fld, cfg["master_template"])
            po_ref_path   = os.path.join(base, tmpl_fld, cfg["po_ref_file"])
            output_dir    = os.path.join(base, cfg["output_folder"])
            fn_tmpl       = cfg["output_filename_template"]

            for label, path in [("Template", template_path),
                                  ("PO Reference", po_ref_path)]:
                if not os.path.isfile(path):
                    print(f"  {RED}ERROR:{RESET} {label} not found: {path}")
                    break
            else:
                if not os.path.isdir(output_dir):
                    print(
                        f"  {RED}ERROR:{RESET} Output directory not found:"
                        f" {output_dir}"
                    )
                else:
                    print(f"\n  {CYAN}Template:{RESET}  {os.path.basename(template_path)}")
                    print(f"  {CYAN}PO Ref:{RESET}    {os.path.basename(po_ref_path)}")
                    print(f"  {CYAN}Output to:{RESET} {output_dir}")

                    now = datetime.now()
                    ym_input = input(
                        f"\n  {YELLOW}Invoice period (YYYY-MM){RESET}"
                        f" {GRAY}[{now.strftime('%Y-%m')}]:{RESET} "
                    ).strip()
                    year_month = ym_input if ym_input else now.strftime("%Y-%m")

                    if not re.match(r"^\d{4}-\d{2}$", year_month):
                        print(f"  {RED}ERROR:{RESET} Invalid format. Use YYYY-MM.")
                        continue

                    site_codes = _read_site_codes(po_ref_path)
                    existing = [
                        fn_tmpl.format(code=c, year_month=year_month)
                        for c in site_codes
                        if os.path.isfile(
                            os.path.join(
                                output_dir,
                                fn_tmpl.format(code=c, year_month=year_month),
                            )
                        )
                    ]
                    if existing:
                        print(
                            f"\n  {YELLOW}WARNING:{RESET}"
                            f" {len(existing)} file(s) will be overwritten:"
                        )
                        for fn in existing:
                            print(f"    {fn}")
                        if input(
                            f"\n  {YELLOW}Continue?{RESET} {GRAY}(y/N):{RESET} "
                        ).strip().upper() != "Y":
                            print(f"  {GRAY}Cancelled.{RESET}")
                            continue

                    password = getpass.getpass(
                        f"\n  {YELLOW}Sheet protection password:{RESET} "
                    )
                    if not password:
                        print(
                            f"  {YELLOW}WARNING:{RESET}"
                            f" No password — sheets will be unprotected."
                        )

                    generate_invoices(
                        template_path, po_ref_path, output_dir,
                        year_month, password, fn_tmpl,
                    )
            print(f"\n{GRAY}Done.{RESET}")

        elif choice == "8":
            current_files = _select_or_reuse_files(current_files)
            if not current_files:
                continue
            clear_tab_colors(current_files)
            print(f"\n{GRAY}Done.{RESET}")

        elif choice == "0":
            print(f"\n{CYAN}Goodbye.{RESET}\n")
            break


if __name__ == "__main__":
    main()
