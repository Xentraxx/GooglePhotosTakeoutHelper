# Contributing to Google Photos Takeout Helper

Thank you for your interest in contributing to Google Photos Takeout Helper! This guide will help you get started with contributing to the project.

## Code of Conduct

By participating in this project, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md).

## Getting Started

### Prerequisites

- [Dart SDK](https://dart.dev/get-dart) (version 3.0 or later)
- [ExifTool](https://exiftool.org/) installed and accessible in your PATH
- Git for version control

### Setting Up Development Environment

1. Fork the repository on GitHub
2. Clone your fork locally:
   ```bash
   git clone https://github.com/Xentraxx/GooglePhotosTakeoutHelper.git
   cd GooglePhotosTakeoutHelper
   ```
3. Get dependencies:
   ```bash
   dart pub get
   ```
4. Verify your setup by running tests:
   ```bash
   dart test
   ```

## How to Contribute

### Reporting Issues

- Use the GitHub issue tracker to report bugs or request features
- Search existing issues before creating a new one
- Provide detailed information including:
  - Your operating system
  - Dart version (`dart --version`)
  - ExifTool version (`exiftool -ver`)
  - the commit you experienced the issue on (if on development branch)
  - Steps to reproduce the issue
  - Expected vs actual behavior

### Submitting Changes

1. Create a new branch for your feature or bugfix:
   ```bash
   git checkout -b feature/your-feature-name
   ```
2. Make your changes following the coding standards
3. Add or update tests for your changes
4. Ensure all tests pass:
   ```bash
   dart test
   ```
5. fix link warnings
6. run "dart format ."
7. Update documentation if needed
8. Commit your changes with a clear commit message
9. Push to your fork and submit a pull request

### Coding Standards

- Follow [Dart style guide](https://dart.dev/guides/language/effective-dart/style)
- Use `dart format` to format your code
- Use `dart analyze` to check for issues
- Write comprehensive tests for new functionality
- Document public APIs with dartdoc comments
- Keep functions focused and maintainable

### Testing

- Write unit tests for new functions and classes
- Update existing tests when modifying functionality
- Ensure all tests pass before submitting
- Include integration tests for complex features
- Test on multiple platforms when possible

### Documentation

- Update README.md for user-facing changes
- Add dartdoc comments for public APIs
- Update CHANGELOG.md following the existing format
- Include examples in documentation when helpful

## Project Structure

```
lib/
├── media.dart              # Core Media class and file handling
├── grouping.dart          # Duplicate detection and grouping logic
├── interactive.dart       # User interaction and CLI interface
├── folder_classify.dart   # Album and folder type detection
├── moving.dart           # File organization and moving logic
├── extras.dart           # Edited file detection
├── exiftoolInterface.dart # ExifTool integration
├── utils.dart            # Utility functions
└── date_extractors/      # Date extraction from various sources
    ├── date_extractor.dart
    ├── exif_extractor.dart
    ├── guess_extractor.dart
    └── json_extractor.dart
```

## Development Workflow

1. **Planning**: Discuss significant changes in an issue first
2. **Implementation**: Work in small, focused commits
3. **Testing**: Ensure comprehensive test coverage
4. **Documentation**: Update relevant documentation
5. **Review**: Submit pull request for code review
6. **Integration**: Merge after approval and CI passes

## Release Process

Releases are managed by project maintainers and follow semantic versioning:
- **Patch** (x.y.Z): Bug fixes and minor improvements
- **Minor** (x.Y.z): New features that are backwards compatible
- **Major** (X.y.z): Breaking changes

## Getting Help

- Check existing documentation in README.md
- Search through GitHub issues
- Ask questions in new issues with the "question" label
- Review the codebase and tests for examples

## Recognition

Contributors will be recognized in:
- GitHub contributors list
- CHANGELOG.md for significant contributions
- Special mentions for major features or fixes

Thank you for contributing to make Google Photos Takeout Helper better for everyone!
