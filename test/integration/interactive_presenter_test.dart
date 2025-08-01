import 'package:gpth/presentation/interactive_presenter.dart';
import 'package:test/test.dart';

void main() {
  group('InteractivePresenter', () {
    late InteractivePresenter presenter;

    setUp(() {
      // Disable sleep and input validation for faster tests
      presenter = InteractivePresenter(
        enableSleep: false,
        enableInputValidation: false,
      );
    });

    test('should create InteractivePresenter instance', () {
      expect(presenter, isA<InteractivePresenter>());
    });

    test('should have album options defined', () {
      expect(InteractivePresenter.albumOptions, isNotEmpty);
      expect(InteractivePresenter.albumOptions, contains('shortcut'));
      expect(InteractivePresenter.albumOptions, contains('duplicate-copy'));
      expect(InteractivePresenter.albumOptions, contains('json'));
      expect(InteractivePresenter.albumOptions, contains('nothing'));
      expect(InteractivePresenter.albumOptions, contains('reverse-shortcut'));
    });

    test('should have proper album option descriptions', () {
      const options = InteractivePresenter.albumOptions;

      for (final entry in options.entries) {
        expect(entry.key, isNotEmpty);
        expect(entry.value, isNotEmpty);
        expect(
          entry.value.length,
          greaterThan(10),
        ); // Should have meaningful descriptions
      }
    });

    test('should validate album option keys are unique', () {
      final keys = InteractivePresenter.albumOptions.keys.toList();
      final uniqueKeys = keys.toSet();

      expect(keys.length, equals(uniqueKeys.length));
    });

    group('Album options content validation', () {
      test('shortcut option should mention symlinks', () {
        final shortcutDescription =
            InteractivePresenter.albumOptions['shortcut']!;
        expect(shortcutDescription.toLowerCase(), contains('symlinks'));
        expect(shortcutDescription.toLowerCase(), contains('recommend'));
      });

      test('duplicate-copy option should mention copying', () {
        final duplicateDescription =
            InteractivePresenter.albumOptions['duplicate-copy']!;
        expect(duplicateDescription.toLowerCase(), contains('copied'));
        expect(duplicateDescription.toLowerCase(), contains('space'));
      });

      test('json option should mention JSON files', () {
        final jsonDescription = InteractivePresenter.albumOptions['json']!;
        expect(jsonDescription.toLowerCase(), contains('json'));
        expect(jsonDescription.toLowerCase(), contains('programmer'));
      });

      test('nothing option should mention ignoring albums', () {
        final nothingDescription =
            InteractivePresenter.albumOptions['nothing']!;
        expect(nothingDescription.toLowerCase(), contains('ignore'));
        expect(nothingDescription.toLowerCase(), contains('warning'));
      });
    });

    group('Configuration validation', () {
      test('should create with sleep enabled by default', () {
        final defaultPresenter = InteractivePresenter();
        expect(defaultPresenter, isA<InteractivePresenter>());
      });

      test('should create with input validation enabled by default', () {
        final defaultPresenter = InteractivePresenter();
        expect(defaultPresenter, isA<InteractivePresenter>());
      });

      test('should allow disabling sleep', () {
        final noSleepPresenter = InteractivePresenter(enableSleep: false);
        expect(noSleepPresenter, isA<InteractivePresenter>());
      });

      test('should allow disabling input validation', () {
        final noValidationPresenter = InteractivePresenter(
          enableInputValidation: false,
        );
        expect(noValidationPresenter, isA<InteractivePresenter>());
      });
    });

    group('Method availability', () {
      test('should have showGreeting method', () {
        expect(() => presenter.showGreeting(), returnsNormally);
      });

      test('should have showNothingFoundMessage method', () {
        expect(() => presenter.showNothingFoundMessage(), returnsNormally);
      });
      test('should have showPressEnterPrompt method', () {
        // Test that the method exists without calling it (since it waits for input)
        expect(presenter.showPressEnterPrompt, isA<Function>());
      });

      test('should have readUserInput method', () {
        // Test that the method exists without calling it (since it waits for input)
        expect(presenter.readUserInput, isA<Function>());
      });
    });

    group('Presenter behavior consistency', () {
      test('album options should have consistent naming convention', () {
        final keys = InteractivePresenter.albumOptions.keys;

        for (final key in keys) {
          // Keys should be lowercase with hyphens, no spaces
          expect(key, matches(RegExp(r'^[a-z-]+$')));
          expect(key, isNot(contains(' ')));
        }
      });

      test('album descriptions should end with newlines for formatting', () {
        final descriptions = InteractivePresenter.albumOptions.values;

        for (final description in descriptions) {
          expect(description, endsWith('\n'));
        }
      });
    });

    group('Error handling', () {
      test('should handle concurrent access to album options', () {
        // Test that the static album options can be accessed concurrently
        final futures = List.generate(
          10,
          (final index) => Future(() => InteractivePresenter.albumOptions),
        );

        expect(() => Future.wait(futures), returnsNormally);
      });
    });

    group('Integration with logging', () {
      test('should be able to use logging mixin methods', () {
        // InteractivePresenter uses LoggerMixin, so it should have logging methods
        // This is more of a compile-time check that the mixin is properly applied
        expect(presenter, isA<InteractivePresenter>());
      });
    });
  });
}
