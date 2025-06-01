## 4.0.5-xentraxx

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

## 4.0.4-xentraxx

### Fork/Alternate version

#### Bug fixes

- Changed Github actions from Ubuntu 24.04 to 22.04 for legacy Synology NAS support

## 4.0.3-xentraxx

### Fork/Alternate version

#### Bug fixes

- Relying on the emoji-regex package to find all emojis
- Added tests to find more emojis
- Fixed github build actions
- Fixed emoji logic to handle inivible characters (by @ireun (Thank you!))
- Made output nicer and fixed wrong mimeType lookup where exiftool would fail (by @ireun (Thank you!))
- Using ubuntu-22.04 instead of ubuntu-latest to build for legacy compatibility with old Synology NAS (thanks to @jaimetur)

## 4.0.2-xentraxx

### Fork/Alternate version

#### Bug fixes

- Removed some dysfunctional progress bars
- resolved typo in release notes

## 4.0.1-xentraxx

### Fork/Alternate version 

#### Bug fixes

- Fixed [PhotoMigrator](https://github.com/jaimetur/PhotoMigrator) integration by finding exiftool in more locations.
- Fixed some typos
- Fixed emoji to hex encoding and decoding and added support for BMP emojis in addition to surrowgate.
- Fixed some tests

## 4.0.0-wacheee (by Xentraxx)

### Fork/Alternate version 

### This change is a big overhaul of the project, so only the major improvements or potential breaking changes are mentioned

#### Tl;dr

- Added support for reading EXIF data from JXL (JPEG XL), ARW, RAW, DNG, CRW, CR3, NRW, NEF and RAF files internally.
- Adeded support for reading and writing coordinates and DateTime from and to exif for almost all file formats.
- Added a "--write-exif" flag which will write missing EXIF information (coordinates and DateTime) from json to EXIF for jpg and jpeg files
- Added support to get DateTime from .MOV, .MP4 and probably many other video formats through exiftool. You need to download it yourself (e.g. from here: https://exiftool.org/), rename it to exiftool.exe and make sure the folder you keep it in is in your $PATH variable or in the same folder as gpth.
- Added verbose mode (--verbose or -v)
- File size is not limited anymore by default but can be limited using the --limit-filesize flag for systems with low RAM (like a NAS).

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

##### *Previous fixes and improvement (from 3.4.3-wacheee to 4.0.0-wacheee)*
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
