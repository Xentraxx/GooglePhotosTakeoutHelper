/// Simple test to verify the MediaEntity moving strategies are working
library;

import 'package:gpth/gpth_lib_exports.dart';
import 'package:test/test.dart';

void main() {
  group('MediaEntity Moving Strategy Factory Basic Tests', () {
    test('factory creates all strategy types without errors', () {
      final fileService = FileOperationService();
      final pathService = PathGeneratorService();
      final symlinkService = SymlinkService();

      final factory = MoveMediaEntityStrategyFactory(
        fileService,
        pathService,
        symlinkService,
      );

      // Test all album behaviors can be created
      for (final behavior in AlbumBehavior.values) {
        expect(
          () => factory.createStrategy(behavior),
          returnsNormally,
          reason: 'Should create strategy for ${behavior.value}',
        );

        final strategy = factory.createStrategy(behavior);
        expect(strategy.name, isNotEmpty);
      }
    });

    test('strategy properties are correct', () {
      final fileService = FileOperationService();
      final pathService = PathGeneratorService();
      final symlinkService = SymlinkService();

      final factory = MoveMediaEntityStrategyFactory(
        fileService,
        pathService,
        symlinkService,
      );

      // Shortcut strategy
      final shortcut = factory.createStrategy(AlbumBehavior.shortcut);
      expect(shortcut.name, equals('Shortcut'));
      expect(shortcut.createsShortcuts, isTrue);
      expect(shortcut.createsDuplicates, isFalse);

      // Duplicate-copy strategy
      final duplicateCopy = factory.createStrategy(AlbumBehavior.duplicateCopy);
      expect(duplicateCopy.name, equals('Duplicate Copy'));
      expect(duplicateCopy.createsShortcuts, isFalse);
      expect(duplicateCopy.createsDuplicates, isTrue);

      // JSON strategy
      final json = factory.createStrategy(AlbumBehavior.json);
      expect(json.name, equals('JSON'));
      expect(json.createsShortcuts, isFalse);
      expect(json.createsDuplicates, isFalse);

      // Nothing strategy
      final nothing = factory.createStrategy(AlbumBehavior.nothing);
      expect(nothing.name, equals('Nothing'));
      expect(nothing.createsShortcuts, isFalse);
      expect(nothing.createsDuplicates, isFalse);

      // Reverse shortcut strategy
      final reverseShortcut = factory.createStrategy(
        AlbumBehavior.reverseShortcut,
      );
      expect(reverseShortcut.name, equals('Reverse Shortcut'));
      expect(reverseShortcut.createsShortcuts, isTrue);
      expect(reverseShortcut.createsDuplicates, isFalse);
    });
  });
}
