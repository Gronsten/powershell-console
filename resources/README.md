# Resources Directory

This directory contains data files used by the PowerShell AWS Console.

## npm-packages.json

**Purpose:** Complete list of all npm package names for global package search functionality.

**Source:** https://raw.githubusercontent.com/nice-registry/all-the-package-names/master/names.json

**Metadata lookup:** Global npm search uses this file for name matching only. Version and
description come from `npm view` against your configured registry (`npm config get registry`,
e.g. corporate JFrog), not from `registry.npmjs.org`.

**Size:** ~90MB (3.6M+ package names)

**Update Frequency:** Automatically checked every 24 hours during npm package searches with optional user-prompted update

### Automatic Updates

The package search feature automatically checks the file age when performing npm searches. If the file is older than 24 hours, you'll see:

```
Package list is X day(s) old.
Update now? (y/N):
```

Simply press `y` to download the latest version, or `N` to continue with the existing list.

### Manual Update

You can also manually update the package list at any time. Run this command from the project root:

```powershell
curl -s "https://raw.githubusercontent.com/nice-registry/all-the-package-names/master/names.json" -o resources/npm-packages.json
```

Or on Windows without curl:

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/nice-registry/all-the-package-names/master/names.json" -OutFile "resources/npm-packages.json"
```

### Initial Setup / Auto-Download

**Automatic (Recommended):**
The package search feature will automatically prompt you to download the package list the first time you search for an npm package:

```
Package list not found. Download now? (90MB) (Y/n)
```

Simply press Enter (or `y`) to download automatically. The script will:
- Create the `resources/` directory if needed
- Download the 90MB package list
- Continue with your search

**Manual Setup:**
If you prefer to download manually before first use:

```powershell
# Create resources directory if it doesn't exist
New-Item -ItemType Directory -Path "resources" -Force

# Download package list
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/nice-registry/all-the-package-names/master/names.json" -OutFile "resources/npm-packages.json"
```

**Note:** This file is excluded from git (.gitignore) due to its size.
