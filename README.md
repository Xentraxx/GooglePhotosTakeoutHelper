# Google Photos Takeout Helper 📸

[![AUR](https://img.shields.io/aur/version/gpth-bin?logo=arch-linux)](https://aur.archlinux.org/packages/gpth-bin)
[![Downloads](https://img.shields.io/github/downloads/TheLastGimbus/GooglePhotosTakeoutHelper/total?label=downloads)](https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/releases/)
[![Issues](https://img.shields.io/github/issues-closed/TheLastGimbus/GooglePhotosTakeoutHelper?label=resolved%20issues)](https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/issues)

Transform your chaotic Google Photos Takeout into organized photo libraries with proper dates, albums, and metadata.

## Important Note
This is a work in progress.
If you have issues with the current version, I recommend trying https://github.com/Xentraxx/GooglePhotosTakeoutHelper/actions/runs/15668191903
It is experimental, but WAYYYYY faster and better than the current version. I just didn't have the chance to try every possible case. Test coverage is there though!

**Acknowledgment**: This project is based on the original work by [TheLastGimbus](https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper). We are grateful for their foundational contributions to the Google Photos Takeout ecosystem.

## What This Tool Does

When you export photos from Google Photos using [Google Takeout](https://takeout.google.com/), you get a mess of folders with weird `.json` files and broken timestamps. This tool:

- ✅ **Organizes photos chronologically** with correct dates
- ✅ **Restores album structure** with multiple handling options
- ✅ **Fixes timestamps** from JSON metadata and EXIF data
- ✅ **Writes GPS coordinates and timestamps** back to media files
- ✅ **Removes duplicates** automatically
- ✅ **Handles special formats** (HEIC, Motion Photos, etc.)

## Quick Start

### 1. Get Your Photos from Google Takeout

1. Go to [Google Takeout](https://takeout.google.com/)
2. Deselect all, then select only **Google Photos**
3. Download all ZIP files

<img width="75%" alt="gpth usage image tutorial" src="https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/assets/40139196/8e85f58c-9958-466a-a176-51af85bb73dd">

### 2. Extract and Merge

Unzip all files and merge them so you have one unified "Takeout" folder.

<img width="75%" alt="Unzip image tutorial" src="https://user-images.githubusercontent.com/40139196/229361367-b9803ab9-2724-4ddf-9af5-4df507e02dfe.png">

**⚠️ Keep the original ZIPs as backup!**

### 3. Install Prerequisites

**ExifTool** (required for metadata handling):

- **Windows**: Download from [exiftool.org](https://exiftool.org/) and rename `exiftool(-k).exe` to `exiftool.exe`
  - Place `exiftool.exe` in your system PATH, or
  - Place `exiftool.exe` in the same folder as `gpth.exe`
  ```bash
  # Or with Chocolatey (automatically adds to PATH):
  choco install exiftool
  ```
- **Mac**: 
  ```bash
  brew install exiftool
  ```
  - Or download from [exiftool.org](https://exiftool.org/) and place `exiftool` in PATH or same folder as `gpth`
- **Linux**: 
  ```bash
  sudo apt install libimage-exiftool-perl
  ```
  - Or download from [exiftool.org](https://exiftool.org/) and place `exiftool` in PATH or same folder as `gpth`

**Note**: If ExifTool is not found in PATH or the same directory as GPTH, the tool will fall back to basic EXIF reading with limited format support.

### 4. Download and Run GPTH

1. Download the latest executable from [releases](https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/releases)
2. **Interactive Mode** (recommended for beginners):
   - Windows: Double-click `gpth.exe`
   - Mac/Linux: Run `./gpth-macos` or `./gpth-linux` in terminal
3. Follow the prompts to select input/output folders and options

## Album Handling Options

GPTH offers several ways to handle your Google Photos albums:

### 🔗 Shortcut (Recommended)
**What it does:** Creates shortcuts/symlinks from album folders to files in `ALL_PHOTOS`. The original files are moved to `ALL_PHOTOS`, and shortcuts are created in album folders.

**Advantages:**
- Saves maximum disk space (no duplicate files)
- Maintains album organization
- Fast processing

**Disadvantages:**
- Shortcuts may break when moving folders between systems
- Not all applications support shortcuts/symlinks
- Windows shortcuts (.lnk files) don't work on Mac/Linux

**Best for:** Most users who want space efficiency and plan to keep photos on the same system.

### 📁 Duplicate Copy
**What it does:** Creates actual file copies in both `ALL_PHOTOS` and album folders. Each photo appears as a separate physical file in every location.

**Advantages:**
- Works across all systems and applications
- Complete independence between folders
- Safe for moving/copying folders between devices
- Album photos remain accessible even if `ALL_PHOTOS` is deleted

**Disadvantages:**
- Uses significantly more disk space (multiplied by number of albums)
- Slower processing due to file copying
- Changes to one copy don't affect others

**Best for:** Users who need maximum compatibility, plan to share folders across different systems, or have plenty of disk space.

### 🔄 Reverse Shortcut
**What it does:** The opposite of shortcut mode. Files remain in their original album folders, and shortcuts are created in `ALL_PHOTOS` pointing to the album locations.

**Advantages:**
- Preserves album-centric organization
- Original files stay in their natural album context
- Good for users who primarily browse by albums

**Disadvantages:**
- `ALL_PHOTOS` becomes dependent on album folders
- If a photo is in multiple albums, only one copy exists (in first album found)
- Shortcuts in `ALL_PHOTOS` may break if album folders are moved

**Best for:** Users who primarily organize and browse photos by albums rather than chronologically.

### 📄 JSON
**What it does:** Creates a single `ALL_PHOTOS` folder with all files, plus an `albums-info.json` file containing metadata about which albums each file belonged to.

**Advantages:**
- Most space-efficient option
- Programmatically accessible album information
- Simple folder structure
- Perfect for developers or automated processing

**Disadvantages:**
- No visual album folders
- Requires custom software to utilize album information
- Not user-friendly for manual browsing

**Best for:** Developers, users migrating to photo management software that can read JSON metadata, or those who don't care about visual album organization.

### ❌ Nothing
**What it does:** Ignores albums entirely and creates only `ALL_PHOTOS` with files from year folders. Album-only files are included if they can be linked to year folders.

**Advantages:**
- Simplest processing
- Fastest execution
- Clean, single-folder result
- No complex album logic

**Disadvantages:**
- Completely loses album organization
- Some album-only photos might be skipped
- No way to recover album information later

**Best for:** Users who don't care about album organization and just want all photos in chronological order.

## Important Notes

- **File Movement:** By default, GPTH moves (not copies) files to save space. Use `--copy` flag if you want to preserve the original takeout structure.
- **Album-Only Photos:** Some photos exist only in albums (not in year folders). GPTH handles these differently depending on the mode chosen.
- **Duplicate Handling:** If a photo appears in multiple albums, the behavior varies by mode (shortcuts link to same file, duplicate-copy creates multiple copies, etc.).

## Command Line Usage

For automation, headless systems, or advanced users:

```bash
gpth --input "/path/to/takeout" --output "/path/to/organized" --albums "shortcut"
```

### Core Arguments

| Argument | Description |
|----------|-------------|
| `--input`, `-i` | Input folder containing extracted Takeout |
| `--output`, `-o` | Output folder for organized photos |
| `--albums` | Album handling: `shortcut`, `duplicate-copy`, `reverse-shortcut`, `json`, `nothing` |
| `--help`, `-h` | Show help and exit |

### Organization Options

| Argument | Description |
|----------|-------------|
| `--divide-to-dates` | Folder structure: `0`=one folder, `1`=by year, `2`=year/month, `3`=year/month/day |
| `--copy` | Copy files instead of moving (safer but uses more space) |
| `--skip-extras` | Skip extra images like "-edited" versions |

### Metadata & Processing

| Argument | Description |
|----------|-------------|
| `--write-exif` | Write GPS coordinates and dates to EXIF metadata (enabled by default) |
| `--transform-pixel-mp` | Convert Pixel Motion Photos (.MP/.MV) to .mp4 |
| `--guess-from-name` | Extract dates from filenames (enabled by default) |
| `--update-creation-time` | Sync creation time with modified time (Windows only) |
| `--limit-filesize` | Skip files larger than 64MB (for low-RAM systems) |

### Other Options

| Argument | Description |
|----------|-------------|
| `--interactive` | Force interactive mode |
| `--verbose`, `-v` | Show detailed logging output |
| `--fix` | Special mode: fix dates in any folder (not just Takeout) |

### Example Commands

**Basic usage:**
```bash
gpth --input "~/Takeout" --output "~/Photos" --albums "shortcut"
```

**Copy files with year folders:**
```bash
gpth --input "~/Takeout" --output "~/Photos" --copy --divide-to-dates 1
```

**Full metadata processing:**
```bash
gpth --input "~/Takeout" --output "~/Photos" --transform-pixel-mp --albums "duplicate-copy"
```

**Fix dates in existing folder:**
```bash
gpth --fix "~/existing-photos"
```

## Features & Capabilities

### 📅 Date Extraction
GPTH uses multiple methods to determine correct photo dates:
1. **JSON metadata** (most accurate)
2. **EXIF data** from photo files
3. **Filename patterns** (Screenshot_20190919-053857.jpg, etc.)
4. **Aggressive matching** for difficult cases

### 🔍 Duplicate Detection
Removes identical files using content hashing, keeping the best copy (shortest filename, most metadata).

### 🌍 GPS Coordinates & Timestamps
Extracts location data and timestamps from JSON files and writes them to media file EXIF data for compatibility with photo viewers and other applications.

### 🎯 Smart File Handling
- **Motion Photos**: Pixel .MP/.MV files can be converted to .mp4
- **HEIC/RAW support**: Handles modern camera formats
- **Unicode filenames**: Properly handles international characters
- **Large files**: Optional size limits for resource-constrained systems

### 📁 Flexible Organization
- Multiple date-based folder structures
- Preserve or reorganize album structure
- Copy or move files (safety vs. efficiency)

## Installation

### Pre-built Binaries
Download from [releases page](https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/releases)

### Package Managers
- **Arch Linux**: `yay -S gpth-bin`

### Building from Source
```bash
git clone https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper.git
cd GooglePhotosTakeoutHelper
dart pub get
dart compile exe bin/gpth.dart -o gpth
```

## Troubleshooting

### Common Issues

**"No photos found"**: Make sure you have a unified Takeout folder structure with "Photos from YYYY" folders.

**Permission errors**: Run with administrator/sudo privileges if moving files across drives.

**Memory issues**: Use `--limit-filesize` for systems with limited RAM.

**Encoding errors**: Some JSON files may have encoding issues; the tool handles most cases automatically.

### Platform-Specific Notes

**Windows**: Creation time updates require administrator privileges.

**macOS**: You may need to allow the executable in Security & Privacy settings.

**Linux**: Ensure ExifTool is installed for full functionality.

## After Migration

### Recommended Apps
- **[Immich](https://immich.app/)**: Self-hosted Google Photos alternative
- **[PhotoPrism](https://photoprism.org/)**: AI-powered photo management
- **[Syncthing](https://syncthing.net/)**: Sync photos across devices while preserving dates

### Android Users
Standard file managers reset photo dates when moving files. Use **Simple Gallery** to preserve timestamps.

## Support This Project

If GPTH saved you time and frustration, consider supporting development:

[![PayPal](https://img.shields.io/badge/Donate-PayPal-blue.svg?logo=paypal&style=for-the-badge)](https://www.paypal.me/TheLastGimbus)
[![Ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/A0A6HO71P)
[![Liberapay](https://liberapay.com/assets/widgets/donate.svg)](https://liberapay.com/TheLastGimbus/donate)

## Related Projects

- **[Google Keep Exporter](https://github.com/vHanda/google-keep-exporter)**: Export Google Keep notes to Markdown
- **[PhotoMigrator](https://github.com/jaimetur/PhotoMigrator)**: Uses GPTH 4.x.x and has been designed to Interact and Manage different Photos Cloud services, and allow users to do an Automatic Migration from one Photo Cloud service to other or from one account to a new account of the same Photo Cloud service.

---

**Note**: This tool moves files by default to avoid using extra disk space. Always keep backups of your original Takeout files!
