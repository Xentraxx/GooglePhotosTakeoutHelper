## 4.2.0 (Unreleased) – Incremental Enhancements & New Date Strategy

### ✨ New / Improved Features
- Parent folder date extraction strategy (feature #28) – derives capture date from enclosing folder names when metadata is missing
- Display ExifTool version in startup diagnostics for clearer environment visibility
- Automatic use of `exiftool -fast` flag (issue #64) for quicker metadata reads on large libraries
- Streamlined ZIP handling: simplified, fully streaming unzip implementation (lower memory footprint)

### ⚡ Performance
- Optimized file reading path for MIME / EXIF detection (reduced I/O + memory)
- Further logging efficiency and progress bar refinements (Step 8 progress bar, suppressed false timestamp warnings)

### 🛠 Fixes
- Date division now applied only to `ALL_PHOTOS`, not album folders (issue #55)
- Fixed issues #61 and #62 (album / path related edge cases)
- Additional cleanup of deprecated copy mode remnants
- More resilient handling when symlinks / test fixtures are present

### 🧹 Maintenance / Refactor
- Removed unused `fuzzysearch` dependency
- LoggerMixin integration into ExifTool service
- Continued internal simplifications & dead code removal

### ✅ Stability & Tests
- Extended test coverage for new parent-folder date strategy & edge cases
- Adjusted tests for symlink detection and timestamp handling

---

## 4.1.0 – Performance, EXIF Enhancements & Logging Unification

### ✨ Features
- Panasonic RAW support added
- EXIF validation layer introduced (early detection of malformed or missing metadata)
- Unified logging service + extended structured logging across steps
- Enhanced final output summary & statistics (hash caching, clearer step logs)

### ⚡ Performance Improvements
- Step 5 optimization (~30% faster – issue #44)
- Hash calculation caching (speeds up duplicate detection & integrity checks)
- General performance improvements across duplicate detection, moving logic & EXIF operations

### 🛠 Bug Fixes
- Resolved race conditions & file synchronization issues (Windows + cross-platform)
- Fixed issues #39, #44, #45, #46, #47, #50 (duplicate detection, logging, performance & EXIF edge cases)
- Corrected coordinates EXIF writing edge cases
- Fixed crash on unsupported AVI variants & refined AVI EXIF write skips
- Stabilized album creation logic & moving modes (all strategies fully implemented)
- Fixed “nothing” album mode to prevent silent loss of album-only photos
- Improved free space detection on Unix with fallbacks

### 🔧 Refactoring & Cleanup
- Large scale removal of legacy, deprecated & wrapper layers (post-architecture hardening)
- Removed obsolete utilities and abstraction layers; simplified structure
- Centralized and clarified interactive mode logic & prompts
- Extensive test reorganization (more e2e + issue-focused tests)

### ✅ Quality & Tooling
- Expanded e2e and unit test coverage (new tests for moving modes, logging, album handling)
- Improved logging granularity for Steps 1–8 (duplicate detection, date extraction, finalization)
- Enhanced issue templates & project metadata

---

## 4.0.9-Xentraxx - Major Architecture Refactor

### 🛡️ **BREAKING CHANGE: Copy Mode Completely Removed**

This release removes the `--copy` flag and all copy mode functionality to ensure **complete input directory safety** and eliminate data integrity issues.

#### **Why This Change Was Made**
- **Input Directory Protection**: Copy mode was modifying files in the input directory during extension fixing and filename sanitization, violating the principle of data safety
- **Simplified Architecture**: Removes complex conditional logic that led to inconsistent behavior
- **Clearer User Intent**: All operations now clearly move files from input to output, with no ambiguity
- **Enhanced Reliability**: Eliminates edge cases where input files could be modified unexpectedly

#### **Breaking Changes**
- **❌ Removed**: `--copy` command line flag
- **❌ Removed**: `copyMode` from all configuration APIs
- **❌ Removed**: Copy-related conditional logic throughout codebase
- **✅ New Behavior**: All files are **always moved** from input to output directory

#### **Migration Guide**
- **Before**: `gpth --input source --output dest --copy`
- **After**: `gpth --input source --output dest` (copy flag no longer needed or supported)
- **Result**: Files will be moved (not copied) from source to destination
- **Behavior**: Files are relocated from input to output directory with metadata processing applied

#### **Technical Implementation**
- **FileOperationService**: Simplified to move-only operations with cross-device copy+delete fallback
- **Moving Strategies**: All strategies now use consistent move semantics
- **Album Strategies**: Duplicate copy strategy still creates copies in album folders when needed
- **Configuration System**: Streamlined without copy mode complexity

#### **Benefits**
- **⚡ Better Performance**: Simplified logic reduces overhead
- **🧹 Cleaner Codebase**: Removed 400+ lines of conditional copy logic
- **🎯 Clearer Semantics**: Move operations are explicit and predictable

### 🛡️ **BREAKING CHANGE: fix extension flag renamed**

- **Consolidated extension fixing flags** into unified `--fix-extensions=<mode>` option
  - **Before**: `--fix-extensions`, `--fix-extensions-non-jpeg`, `--fix-extensions-solo-mode`
  - **After**: `--fix-extensions=<mode>` with `none`, `standard`, `conservative`, `solo` modes

### 🏗️ **Complete Architecture Overhaul**

This release represents a fundamental restructuring of the codebase following **Clean Architecture** principles, providing better maintainability, testability, and performance.

#### **Tl;dr**

- fix extenstion flag changed to `--fix-extensions=<mode>`
- Improved performance.
- **CRITICAL FIX**: Nothing mode now processes ALL files, preventing data loss in move mode

#### **Critical Bug Fixes**
- **🚨 FIXED: Data loss in Nothing mode** - Album-only files are now properly moved in Nothing mode instead of being silently skipped, preventing potential data loss when using move mode with `--album-behavior=nothing`

#### **Domain-Driven Design Implementation**
- **Reorganized codebase into distinct layers**: Domain, Infrastructure, and Presentation
- **Introduced service-oriented architecture** with dependency injection container
- **Implemented immutable domain entities** for better data integrity and performance
- **Added comprehensive test coverage** with over 200+ unit and integration tests

#### **Service Consolidation & Modernization**
- **Unified service interfaces** through consolidated service pattern
- **Implemented ServiceContainer** for centralized dependency management
- **Refactored moving logic** into strategy pattern with pluggable implementations
- **Enhanced error handling** with proper exception hierarchies and logging

### 🚀 **Performance & Reliability Improvements**

#### **Async Processing Architecture**
- **Stream-based file I/O operations** replacing synchronous access
- **Persistent ExifTool process** management (10-50x faster EXIF operations)
- **Concurrent media processing** with race condition protection
- **Memory optimization** - up to 99.4% reduction for large file operations

#### **Advanced File Operations**
- **Streaming hash calculations** (20% faster with reduced memory usage)
- **Optimized directory scanning** (50% fewer I/O operations)
- **Parallel file moving operations** (40-50% performance improvement)
- **Smart duplicate detection** with memory-efficient algorithms
- **Native Win32 creation time updates** - Replaced PowerShell with direct Win32 FFI calls (10-100x faster)

#### **Intelligent Extension Correction**
- **MIME type validation** with file header detection
- **RAW format protection** - prevents corruption of TIFF-based files
- **Comprehensive safety modes** for different use cases
- **JSON metadata synchronization** after extension fixes

### 📁 **Modern File Management**

#### **Strategy Pattern Implementation**
- **Pluggable moving strategies**: Nothing, Copy, Shortcut, Reverse Shortcut
- **Context-aware path generation** with date-based organization
- **Atomic file operations** with rollback capabilities
- **Smart collision handling** with unique filename generation

#### **Cross-Platform Improvements**
- **Platform-specific optimizations** for Windows, macOS, and Linux
- **Enhanced shortcut creation** bypassing PowerShell on Windows
- **Unified disk space management** across all platforms
- **Improved encoding handling** for international filenames

### 🧪 **Testing & Quality Assurance**

#### **Comprehensive Test Suite**
- **200+ automated tests** covering unit, integration, and end-to-end scenarios
- **Mock service infrastructure** for reliable testing
- **Performance regression testing** with benchmarks
- **Cross-platform validation** across all supported systems

#### **Code Quality Improvements**
- **Comprehensive documentation** with detailed function descriptions
- **Lint rule enforcement** following Dart best practices
- **Type safety enhancements** with null safety
- **Error logging standardization** with structured log levels

### 🔄 **Processing Pipeline Modernization**

#### **Eight-Step Pipeline Architecture**
1. **Extension Fixing** - Intelligent MIME type correction
2. **Media Discovery** - Optimized file system scanning
3. **Duplicate Removal** - Content-based deduplication
4. **Date Extraction** - Multi-source timestamp resolution
5. **EXIF Writing** - Metadata synchronization
6. **Album Detection** - Smart folder classification
7. **File Moving** - Strategy-based organization
8. **Creation Time Updates** - Final timestamp alignment

#### **Enhanced Data Processing**
- **MediaEntity immutable models** for thread-safe operations
- **Coordinate processing** with validation and conversion
- **JSON metadata matching** with truncated filename support
- **Album relationship management** with shortcut strategies

### 🛠️ **Infrastructure Enhancements**

#### **External Tool Integration**
- **Persistent ExifTool management** with automatic discovery
- **Platform service abstraction** for system-specific operations
- **Disk space monitoring** with real-time calculations
- **Process lifecycle management** with proper cleanup

#### **Interactive User Experience**
- **Consolidated interactive services** with improved prompts
- **Real-time progress reporting** for long-running operations
- **Enhanced error messages** with actionable guidance
- **ZIP extraction restoration** with security improvements

### 📋 **Configuration & Usability**

#### **Streamlined Configuration**
- **Unified command-line interface** with consistent flag patterns
- **Interactive configuration validation** with user guidance
- **Global configuration service** with centralized settings
- **Backward compatibility** for existing workflows

#### **Bug Fixes & Stability**
- **Race condition elimination** in concurrent operations
- **JSON file matching improvements** for truncated names
- **Memory leak prevention** in long-running processes
- **Cross-platform filename handling** improvements

## 4.0.8-Xentraxx

### Interactive ZIP File Extraction Restored

#### Major Feature Restoration
- **Restored interactive ZIP file extraction functionality** that was previously deprecated due to photo loss issues
- Added comprehensive security measures to prevent data loss and security vulnerabilities
- Implemented user-friendly choice between automatic ZIP extraction or using pre-extracted directories

#### New Interactive ZIP Features
- **`askIfUnzip()` function**: Provides users with clear options for handling Google Takeout data:
  - Option 1: Select ZIP files for automatic extraction (Recommended)
  - Option 2: Use already extracted directory
- **Enhanced `getZips()` function**: Improved file picker with better validation and user feedback
- **Secure `unzip()` function**: Comprehensive ZIP extraction with multiple safety layers

#### Security and Safety Improvements
- **ZIP Slip Protection**: Prevents malicious ZIP files from extracting outside the target directory
- **Cross-platform filename sanitization**: Handles encoding issues and invalid characters safely
- **Comprehensive error handling**: User-friendly error messages with actionable guidance
- **File integrity validation**: Verifies ZIP files before extraction
- **Progress reporting**: Real-time feedback during extraction process

#### Technical Enhancements
- **`_extractZipSafely()` helper**: Internal function with security checks and encoding handling
- **`_sanitizeFileName()` helper**: Cross-platform filename normalization and safety checks
- **`_handleExtractionError()` helper**: Context-specific error handling with detailed guidance
- **`SecurityException` class**: Custom exception for handling security-related extraction issues

#### Workflow Integration
- Seamlessly integrated into interactive mode with clear user prompts

### Extension Fixing Feature

- Added comprehensive file extension correction functionality to handle mismatched MIME types and extensions
- Added three CLI flags for different extension fixing behaviors:
  - `--fix-extensions`: Fixes incorrect extensions except for TIFF-based files (e.g., RAW formats)
  - `--fix-extensions-non-jpeg`: More conservative mode that also skips actual JPEG files  
  - `--fix-extensions-solo-mode`: Standalone mode that fixes extensions and exits without further processing
- Added interactive prompts for extension fixing configuration with three options for user convenience
- Enhanced EXIF writing error messages to suggest using `--fix-extensions` when extension/MIME type mismatches are detected
- Added comprehensive test coverage for extension fixing functionality including edge cases

### JSON File Matching Improvements

- Added support for removing partial extra format suffixes from truncated filenames (issue #29)
- Enhanced JSON file matching for media files with filename truncation due to filesystem limits
- Added `removePartialExtraFormats` function to handle cases where suffixes like "-ed" need to be removed to match corresponding JSON files
- Improved date extraction reliability for files with truncated names ending in partial extra format patterns

#### Technical Details

When filenames are truncated due to filesystem character limits, partial suffixes (e.g., "-ed" from "-edited") can prevent proper JSON file matching for date extraction. The new functionality identifies and removes these partial patterns, allowing the JSON extractor to find corresponding metadata files and extract accurate photo dates.

### Bug Fixes and Improvements

- Fixed EXIF writing to properly handle files with incorrect extensions by detecting MIME type mismatches
- Improved error logging with more informative messages about extension/MIME type conflicts
- Updated statistics reporting to include count of fixed file extensions
- Enhanced interactive mode with better user guidance for extension fixing options

### Technical Details

The extension fixing feature addresses a common issue where Google Photos' "data saving" option compresses images to JPEG format but retains original file extensions, or where web-downloaded images have incorrect extensions. The tool now:

1. Reads file headers to detect actual MIME type
2. Compares with extension-based MIME type detection
3. Skips TIFF-based files (like RAW formats) as they're often misidentified
4. Renames files with correct extensions and updates associated JSON metadata files
5. Provides detailed logging of the fixing process

The feature integrates seamlessly with the existing EXIF writing workflow, ensuring metadata can be properly written to files after extension correction.

## 4.0.7-Xentraxx

### Fork/Alternate version

#### Bug fixes

- Simplified year folder detection logic to strictly match "Photos from YYYY" format
- Updated folder classification tests to align with more restrictive year folder recognition
- Fixed test failures related to year folder pattern matching

#### General improvements

- Enhanced test coverage for folder classification functionality
- Improved test documentation and organization
- Strengthened year folder validation to prevent false positives
- Removed --modify-json flag from wachees fork due to issues.

## 4.0.5-wacheee-xentraxx-beta

### Fork/Alternate version

#### Bug fixes

- Fixed multiple serious race conditions
- Fixed serious problem where (1) was appended more than once
- Fixed serious bug where reverse-shortcut album mode was not creating albums
- Fixed serious bug where on windows .lnk was appended to a shortcut more than once
- Fixed bug where mimeType needs to be identified by file header for various RAW formats which are based on TIFF (Thank you @IreunN)

#### General improvements

- Added more than 200 unit and functional tests with documentation
- Documented every function comprehensively
- Improved general documentation in code
- Improved README to be more comprehensive
- Added CONTRIBUTING.md

## 4.0.4-wacheee-xentraxx-beta

### Fork/Alternate version

#### Bug fixes

- Changed Github actions from Ubuntu 24.04 to 22.04 for legacy Synology NAS support

## 4.0.3-wacheee-xentraxx-beta

### Fork/Alternate version

#### Bug fixes

- Relying on the emoji-regex package to find all emojis
- Added tests to find more emojis
- Fixed github build actions
- Fixed emoji logic to handle inivible characters (by @ireun (Thank you!))
- Made output nicer and fixed wrong mimeType lookup where exiftool would fail (by @ireun (Thank you!))
- Using ubuntu-22.04 instead of ubuntu-latest to build for legacy compatibility with old Synology NAS (thanks to @jaimetur)

## 4.0.2-wacheee-xentraxx-beta

### Fork/Alternate version

#### Bug fixes

- Removed some dysfunctional progress bars
- resolved typo in release notes

## 4.0.1-wacheee-xentraxx-beta

### Fork/Alternate version 
### This change is a big overhaul of the project, so only the major improvements or potential breaking changes are mentioned
### This version was developed mainly by @Xentraxx (https://github.com/Xentraxx/)

#### Tl;dr

- Added support for reading EXIF data from JXL (JPEG XL), ARW, RAW, DNG, CRW, CR3, NRW, NEF and RAF files internally.
- Adeded support for reading and writing coordinates and DateTime from and to exif for almost all file formats.
- Added a "--write-exif" flag which will write missing EXIF information (coordinates and DateTime) from json to EXIF for jpg and jpeg files
- Added support to get DateTime from .MOV, .MP4 and probably many other video formats through exiftool. You need to download it yourself (e.g. from here: https://exiftool.org/), rename it to exiftool.exe and make sure the folder you keep it in is in your $PATH variable or in the same folder as gpth.
- Added verbose mode (--verbose or -v)
- File size is not limited anymore by default but can be limited using the --limit-filesize flag for systems with low RAM (like a NAS).
- Fixed [PhotoMigrator](https://github.com/jaimetur/PhotoMigrator) integration by finding exiftool in more locations.
- Fixed some typos
- Fixed emoji to hex encoding and decoding and added support for BMP emojis in addition to surrowgate.
- Fixed some tests 


#### General improvements

- upgraded dependencies and fixed breaking changes
- updated dart to a minimum version of 3.8.0 of the dart SDK
- included image, intl and coordinate_converter packages
- applied a list of coding best practices through lint rules to code
- added/edited a bunch of comments and changed unnecessary print() to log() for debugging and a better user experience
- Divided code in steps through comments and included steps in output for readability, debuggability and to make it easier to follow the code
- checked TODOs in README.md
- Added TODOs to look into in code through //TODO comments
- moved json_extractor file into date_extractor folder
- added unit tests for new write-exif functionality
- made CLI --help output more readable through line breaks
- renamed some variables/functions to better reflect their purpose
- moved step 8 (update creation time) before final output
- added output how often DateTime and Coordinates have been written in EXIF at the final output
- changed that test data will be created in test subfolder instead of project root directory
- Added consistent log levels to log output to quickly differenciate between informational and error logs
- Added logging of elapsed time for each step.
- Exposed the maxFileSize flag as an argument (--limit-filesize) to set if necessary, It's now deactivated by default to support larger files like videos.
- Added DateTime extraction method statistics to the final output - shows how many files had their dates extracted through which method
- Added elapsed time logging for each processing step
- Improved Github actions

#### Bug fixes

- fixed existing unit tests which would fail on windows
- Fixed Github Actions

#### Added functionality

- Support for writing coordinates and DateTime to EXIF
  - Added new CLI option "--write-exif".
  - When enabled, the script will check if the associated json of any given file contains coordinates and if the file does not yet have them in its EXIF data, the script will add them.
  - When enabled, the script will check if a DateTime has been extracted from any of the given extraction methods and if the file has no EXIF DateTime set, it will add the DateTime to the EXIF data 'DateTime', 'DateTimeOriginal'and 'DateTimeDigitized'.
  - Added verbose mode (--verbose or -v) with log levels info, warning and error.

- Moved from the stale "exif" package to "exif_reader" for dart local exif reading, the image library for local jpeg exif writing and the external exiftool for all other EXIF reading and writing (images and videos)
  - The move to exif_reader adds support for extracting DateTime from JXL (JPEG XL), ARW, RAW, DNG, CRW, CR3, NRW, NEF and RAF files, and video formats like MOV, MP4, etc.
  - Exiftool needs to be in $PATH variable or in the same folder as the running binary. If not, that's okay. Then we fall back to exif_reader. But if you have ExifTool locally, Google Photos Takeout Helper now supports reading CreatedDateTime EXIF data for almost all media formats.

- Added new interactive prompts:
  - Option to write EXIF data to files (--write-exif)
  - Option to limit file size for systems with low RAM (--limit-filesize)

#### Limitations
- As mentioned on the PR https://github.com/Wacheee/GooglePhotosTakeoutHelper/pull/13#issuecomment-2910289503 this version can be slower than 3.6.x-wacheee in Windows because is using PowerShell to create shortcuts (FFI is causing heap exception)

##
<details>
<summary>Previous fixes and improvements</summary>
  
#####  *Previous fixes and improvement (from 3.4.3-wacheee to 4.0.0-wacheee)*
- *added macOS executables supporting both ARM64 and Intel architectures https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/issues/310 https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/issues/396#issuecomment-2787459117*
- *fixed an exception when using GPTH with command-line arguments https://github.com/Wacheee/GooglePhotosTakeoutHelper/issues/5 https://github.com/Wacheee/GooglePhotosTakeoutHelper/issues/8*
- *the "fix JSON metadata files" option can now be configured using command-line arguments https://github.com/Wacheee/GooglePhotosTakeoutHelper/issues/7 https://github.com/Wacheee/GooglePhotosTakeoutHelper/issues/9*
- *if `shortcut` option is selected, shortcut creation will be 10 times faster on Windows platforms (new creation method that avoids using PowerShell). For more details: [TheLastGimbus#390](https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/pull/390)*
- *fixed issues with folder names containing emojis  💖🤖🚀on Windows #389*
- *added an interactive option to update the creation times of files in the output folder to match their last modified times at the end of the program (only on Windows) #371*
- *if a media is not in a year folder it establishes one from an album to move it to ALL_PHOTOS correctly. This will move the original media file directly from the album (or one of those albums) to ALL_PHOTOS and create a shortcut in the output album folder (if shortcut option is selected) #261*
- *added support for moving or copying files with the following extensions to the output folder: .MP, .MV, .DNG, and .CR2 #381 #324 #180 #271*
- *added an interactive option to convert Pixel Motion Photo files (.MP or .MV) to .mp4*
- *added an option to remove the "supplemental-metadata" suffix from JSON to prevent issues with metadata #353 #355*
- *fixed shortcut issue on Windows platforms #248*
- *added more options for date-based folders [year, month, day] #238 (based in this commit [`More granular date folders #299`](https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/pull/299/commits/d06fe73101845acd650bc025d2977b96bbd1bf1d))*
- *added reverse-shortcut option, now you can mantain original photo in album folders and create a shortcut in year albums*
  
##### *Limitations:*
- *if album mode is set to duplicate-copy, it will move the album photos to the album folder (as usual), but ALL_PHOTOS will not contain them if the media is not in a year album.*
- *it does not fix issues related to reading JSON files (if necessary) for Motion Photo files; however, if the dates are included in the file name (as with Pixel Motion Photos), the correct dates will be established.*
- *No interactive unzipping*

## 3.6.2-wacheee

### Fork/Alternate version 
#### macOS executables

- added macOS executables supporting both ARM64 and Intel architectures https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/issues/310 https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/issues/396#issuecomment-2787459117
  
##### *Previous fixes and improvement (from 3.4.3-wacheee to 3.6.1-wacheee)*
- *fixed an exception when using GPTH with command-line arguments https://github.com/Wacheee/GooglePhotosTakeoutHelper/issues/5 https://github.com/Wacheee/GooglePhotosTakeoutHelper/issues/8*
- *the "fix JSON metadata files" option can now be configured using command-line arguments https://github.com/Wacheee/GooglePhotosTakeoutHelper/issues/7 https://github.com/Wacheee/GooglePhotosTakeoutHelper/issues/9*
- *if `shortcut` option is selected, shortcut creation will be 10 times faster on Windows platforms (new creation method that avoids using PowerShell). For more details: [TheLastGimbus#390](https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/pull/390)*
- *fixed issues with folder names containing emojis  💖🤖🚀on Windows #389*
- *added an interactive option to update the creation times of files in the output folder to match their last modified times at the end of the program (only on Windows) #371*
- *if a media is not in a year folder it establishes one from an album to move it to ALL_PHOTOS correctly. This will move the original media file directly from the album (or one of those albums) to ALL_PHOTOS and create a shortcut in the output album folder (if shortcut option is selected) #261*
- *added support for moving or copying files with the following extensions to the output folder: .MP, .MV, .DNG, and .CR2 #381 #324 #180 #271*
- *added an interactive option to convert Pixel Motion Photo files (.MP or .MV) to .mp4*
- *added an option to remove the "supplemental-metadata" suffix from JSON to prevent issues with metadata #353 #355*
- *fixed shortcut issue on Windows platforms #248*
- *added more options for date-based folders [year, month, day] #238 (based in this commit [`More granular date folders #299`](https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/pull/299/commits/d06fe73101845acd650bc025d2977b96bbd1bf1d))*
- *added reverse-shortcut option, now you can mantain original photo in album folders and create a shortcut in year albums*
  
##### *Limitations (previous fixes):*
- *if album mode is set to duplicate-copy, it will move the album photos to the album folder (as usual), but ALL_PHOTOS will not contain them if the media is not in a year album.*
- *it does not fix issues related to reading JSON files (if necessary) for Motion Photo files; however, if the dates are included in the file name (as with Pixel Motion Photos), the correct dates will be established.*

## 3.6.1-wacheee

### Fork/Alternate version 
#### Fixes for Command-Line Arguments

- fixed an exception when using GPTH with command-line arguments https://github.com/Wacheee/GooglePhotosTakeoutHelper/issues/5 https://github.com/Wacheee/GooglePhotosTakeoutHelper/issues/8
- the "fix JSON metadata files" option can now be configured using command-line arguments https://github.com/Wacheee/GooglePhotosTakeoutHelper/issues/7 https://github.com/Wacheee/GooglePhotosTakeoutHelper/issues/9
  
##### *Previous fixes and improvement (from 3.4.3-wacheee to 3.6.0-wacheee)*
- *if `shortcut` option is selected, shortcut creation will be 10 times faster on Windows platforms (new creation method that avoids using PowerShell). For more details: [TheLastGimbus#390](https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/pull/390)*
- *fixed issues with folder names containing emojis  💖🤖🚀on Windows #389*
- *added an interactive option to update the creation times of files in the output folder to match their last modified times at the end of the program (only on Windows) #371*
- *if a media is not in a year folder it establishes one from an album to move it to ALL_PHOTOS correctly. This will move the original media file directly from the album (or one of those albums) to ALL_PHOTOS and create a shortcut in the output album folder (if shortcut option is selected) #261*
- *added support for moving or copying files with the following extensions to the output folder: .MP, .MV, .DNG, and .CR2 #381 #324 #180 #271*
- *added an interactive option to convert Pixel Motion Photo files (.MP or .MV) to .mp4*
- *added an option to remove the "supplemental-metadata" suffix from JSON to prevent issues with metadata #353 #355*
- *fixed shortcut issue on Windows platforms #248*
- *added more options for date-based folders [year, month, day] #238 (based in this commit [`More granular date folders #299`](https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/pull/299/commits/d06fe73101845acd650bc025d2977b96bbd1bf1d))*
- *added reverse-shortcut option, now you can mantain original photo in album folders and create a shortcut in year albums*
  
##### *Limitations (previous fixes):*
- *if album mode is set to duplicate-copy, it will move the album photos to the album folder (as usual), but ALL_PHOTOS will not contain them if the media is not in a year album.*
- *it does not fix issues related to reading JSON files (if necessary) for Motion Photo files; however, if the dates are included in the file name (as with Pixel Motion Photos), the correct dates will be established.*

### Fork/Alternate version 
#### Windows: 10x faster shortcut creation and other fixes

- if `shortcut` option is selected, shortcut creation will be 10 times faster on Windows platforms (new creation method that avoids using PowerShell). For more details: [TheLastGimbus#390](https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/pull/390)
- fixed issues with folder names containing emojis  💖🤖🚀on Windows #389
  
##### *Previous fixes and improvement (from 3.4.3-wacheee to 3.5.2-wacheee)*
- *added an interactive option to update the creation times of files in the output folder to match their last modified times at the end of the program (only on Windows) #371*
- *if a media is not in a year folder it establishes one from an album to move it to ALL_PHOTOS correctly. This will move the original media file directly from the album (or one of those albums) to ALL_PHOTOS and create a shortcut in the output album folder (if shortcut option is selected) #261*
- *added support for moving or copying files with the following extensions to the output folder: .MP, .MV, .DNG, and .CR2 #381 #324 #180 #271*
- *added an interactive option to convert Pixel Motion Photo files (.MP or .MV) to .mp4*
- *added an option to remove the "supplemental-metadata" suffix from JSON to prevent issues with metadata #353 #355*
- *fixed shortcut issue on Windows platforms #248*
- *added more options for date-based folders [year, month, day] #238 (based in this commit [`More granular date folders #299`](https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/pull/299/commits/d06fe73101845acd650bc025d2977b96bbd1bf1d))*
- *added reverse-shortcut option, now you can mantain original photo in album folders and create a shortcut in year albums*
  
##### *Limitations (previous fixes):*
- *if album mode is set to duplicate-copy, it will move the album photos to the album folder (as usual), but ALL_PHOTOS will not contain them if the media is not in a year album.*
- *it does not fix issues related to reading JSON files (if necessary) for Motion Photo files; however, if the dates are included in the file name (as with Pixel Motion Photos), the correct dates will be established.*

## 3.5.2-wacheee

### Fork/Alternate version 
#### New option to update creation time at the end of program - Windows only

- added an interactive option to update the creation times of files in the output folder to match their last modified times at the end of the program #371

Limitations:
- only works for Windows right now
  
##### *Previous fixes and improvement (from 3.4.3-wacheee to 3.5.1-wacheee)*
- *if a media is not in a year folder it establishes one from an album to move it to ALL_PHOTOS correctly. This will move the original media file directly from the album (or one of those albums) to ALL_PHOTOS and create a shortcut in the output album folder (if shortcut option is selected) #261*
- *added support for moving or copying files with the following extensions to the output folder: .MP, .MV, .DNG, and .CR2 #381 #324 #180 #271*
- *added an interactive option to convert Pixel Motion Photo files (.MP or .MV) to .mp4*
- *added an option to remove the "supplemental-metadata" suffix from JSON to prevent issues with metadata #353 #355*
- *fixed shortcut issue on Windows platforms #248*
- *added more options for date-based folders [year, month, day] #238 (based in this commit [`More granular date folders #299`](https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/pull/299/commits/d06fe73101845acd650bc025d2977b96bbd1bf1d))*
- *added reverse-shortcut option, now you can mantain original photo in album folders and create a shortcut in year albums*
  
##### *Limitations (previous fixes):*
- *if album mode is set to duplicate-copy, it will move the album photos to the album folder (as usual), but ALL_PHOTOS will not contain them if the media is not in a year album.*
- *it does not fix issues related to reading JSON files (if necessary) for Motion Photo files; however, if the dates are included in the file name (as with Pixel Motion Photos), the correct dates will be established.*

## 3.5.1-wacheee

### Fork/Alternate version 
#### Always move to ALL_PHOTOS even if it is not present in year album

- if a media is not in a year folder it establishes one from an album to move it to ALL_PHOTOS correctly. This will move the original media file directly from the album (or one of those albums) to ALL_PHOTOS and create a shortcut in the output album folder (if shortcut option is selected) #261

Limitations:
- if album mode is set to duplicate-copy, it will move the album photos to the album folder (as usual), but ALL_PHOTOS will not contain them if the media is not in a year album.
  
##### *Previous fixes (3.4.3-wacheee - 3.5.0-wacheee)*
- *added support for moving or copying files with the following extensions to the output folder: .MP, .MV, .DNG, and .CR2 #381 #324 #180 #271*
- *added an interactive option to convert Pixel Motion Photo files (.MP or .MV) to .mp4*
- *added an option to remove the "supplemental-metadata" suffix from JSON to prevent issues with metadata #353 #355*
- *fixed shortcut issue on Windows platforms #248*
- *added more options for date-based folders [year, month, day] #238 (based in this commit [`More granular date folders #299`](https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/pull/299/commits/d06fe73101845acd650bc025d2977b96bbd1bf1d))*
- *added reverse-shortcut option, now you can mantain original photo in album folders and create a shortcut in year albums*
  
##### *Limitations (previous fixes):*
- *it does not fix issues related to reading JSON files (if necessary) for Motion Photo files; however, if the dates are included in the file name (as with Pixel Motion Photos), the correct dates will be established.*

## 3.5.0-wacheee

### Fork/Alternate version 
#### Convert Pixel Motion Photo files Option - More extensions supported 

- added support for moving or copying files with the following extensions to the output folder: .MP, .MV, .DNG, and .CR2 #381 #324 #180 #271
- added an interactive option to convert Pixel Motion Photo files (.MP or .MV) to .mp4

Limitations:
- it does not fix issues related to reading JSON files (if necessary) for Motion Photo files; however, if the dates are included in the file name (as with Pixel Motion Photos), the correct dates will be established.

## 3.4.3-wacheee

### Fork/Alternate version from original 
#### Bug fixes

- added an option to remove the "supplemental-metadata" suffix from JSON to prevent issues with metadata #353 #355
- fixed shortcut issue on Windows platforms #248
- added more options for date-based folders [year, month, day] #238 (based in this commit [`More granular date folders #299`](https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/pull/299/commits/d06fe73101845acd650bc025d2977b96bbd1bf1d))
- added reverse-shortcut option, now you can mantain original photo in album folders and create a shortcut in year albums

## 3.4.3

### Just a few patches ❤️‍🩹

- put stuff in `date-unknown` also when not div-to-dates - #245
- fix extras detection on mac - #243
- add note to not worry about album finding ;)
- nice message when trying to run interactive on headless

## 3.4.2

### Bug fixes again 🐛

- (maybe?) fix weird windoza trailing spaces in folder names (literally wtf??) - #212
  
  Not sure about this one so hope there will be no day-1 patch 😇🙏

- update to Dart 3 🔥
- recognize `.mts` files as videos, unlike Apache 😒 - #223
- change shortcuts/symlinks to relative so it doesn't break on folder move 🤦 - #232
- don't fail on set-file-modification errors - turns out there are lot of these - #229

### Happy takeouts 👽

## 3.4.1

- Lot of serious bug fixes
  - Interactive unzipping was disabled because it sometimes lost *a lot of* photos ;_;
    
    Sorry if anyone lost anything - now I made some visual instruction on how to unzip
  - Gracefully handle powershell fail - it fails with non-ascii names :(
- Great improvement on json matching - now, my 5k Takeout has 100% matches!

## 3.4.0

### Albums 🎉

It finally happened everyone! It wasn't easy, but I think I nailed it and everything should perfectly 👌

You get **_🔥FOUR🔥_** different options on how you want your albums 😱 - detailed descriptions about them is at: https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/discussions/187#discussion-4980576

(This also automatically nicely covers Trash/Archive, so previous solution that originally closed the https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/issues/138 was replaced)

### Happy Take-outing 🥳 

## 3.3.5

- Address #178 issues in logs - instructions on what to do

  Sorry but this is all i can do for now :( we may get actual fix if https://github.com/brendan-duncan/archive/pull/244 ever moves further

## 3.3.4

- New name-guess patterns from @matt-boris <3
- Support 19**-s and 18**-s while name guessing
  > First camera was invented in 1839. I don't underestimate you guys anymore :eyes:
- Fix path errors on windoza while unzipping #172
- Fix #175 bad guessing json files with `...(1)` stuff

## 3.3.3

- Fix memory crashes :D
- nicer names for split-to-dates thanks to @denouche #168 <3

## 3.3.2

- Bump SDK and dependencies

## 3.3.1

### Fix bugs introduced in `v3.3.0` 🤓

- #147 Support `.tgz` files too
- #145 **DON'T** use ram memory equal to zip file thanks to `asyncWrite: true` flag 🙃
- #143 don't crash when encoding is other than `utf8` 🍰
- #136 #144 - On windzoa, set time to 1970 if it's before that - would love to *actually* fix this, but Dart doesn't let me :/

## 3.3.0

- Fix #143 - issues when encoding is not utf8 - sadly, others are still not supported, just skipped
- Ask for divide-to-folders in interactive
- Close #138 - support Archive/Trash folders!

  Implementation of this is a bit complicated, so may break, but should work 99% times
- Fix #134 - nicely tell user what to do when no "year folders" instead of exceptions
- Fix #92 - Much better json finding!
  
  It now should find all of those `...-edited(1).jpg.json` - this also makes it faster because it rarely falls back to reading exif, which is slower
- More small fixes and refactors

### Enjoy even faster and more stable `gpth` everyone 🥳🥳🥳

## 3.2.0

- Brand new ✨interactive mode✨ - just double click 🤘
  - `gpth` now uses 💅discontinued💅 [`file_picker_desktop`](https://pub.dev/packages/file_picker_desktop) to launch pickers for user to select output folder and input...
  - ...zips 🤐! because it also decompresses the takeouts for you! (People had ton of trouble of how to join them etc - no worries anymore!)
- Donation link

## 3.1.1

- Code sign windoza exe with self-made cert

## 3.1.0

- Added `--divide-to-dates` 🎉

## 3.0.0

- Dart!
- Speed
- Consistency - it is well known what script does, what does it copy and what not
- Stable album detection (tho still don't know what to do with it)
- [Testing!](https://youtu.be/UGSgpvjHp9o?t=292)
- Better json matching
- `--guess-from-name` is now a default
- `--skip-extras-harder` is missing for now
- `--divide-to-dates` is missing for now
- End-to-end tests are gone, but they're not as required since we have a lod of Units instead 👍
