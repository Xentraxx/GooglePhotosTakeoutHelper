/// Constants for identifying and handling "extra" format patterns
///
/// This file contains language-specific suffixes used to identify edited
/// versions of photos and videos that should be filtered out during processing.
library;

/// List of language-specific "edited" format suffixes
///
/// These patterns are used to identify files that are edited versions
/// of original photos/videos and should typically be excluded from processing.
/// All patterns should be lowercase for case-insensitive matching.
const List<String> extraFormats = <String>[
  // Special Suffixes (are always in English)
  '-effects',
  '-motion',
  '-animation',
  '-smile',
  '-collage',
  '-mix',

  // Edited Suffixes (language-specific)
  // EN/US - thanks @DalenW
  '-edited',
  // PL
  '-edytowane',
  // DE - thanks @cintx
  '-bearbeitet',
  // NL - thanks @jaapp
  '-bewerkt',
  // JA - thanks @fossamagna
  '-編集済み',
  // ZH - Chinese
  '-编辑',
  // IT - thanks @rgstori
  '-modificato',
  // FR - for @palijn's problems <3
  '-modifié',
  // ES - @Sappstal report
  '-ha editado',
  // IT
  '-editado',
  // CA - @Sappstal report
  '-editat',
  // Add more "edited" flags in more languages if you want.
  // They need to be lowercase.
];
