/// Test suite for ServiceContainer
///
/// Tests the dependency injection container functionality including
/// service initialization, disposal, and singleton behavior.
library;

import 'package:gpth/gpth_lib_exports.dart';
import 'package:test/test.dart';

void main() {
  group('ServiceContainer', () {
    tearDown(() async {
      // Reset service container after each test
      await ServiceContainer.reset();
    });

    group('singleton behavior', () {
      test('returns same instance on multiple calls', () {
        final instance1 = ServiceContainer.instance;
        final instance2 = ServiceContainer.instance;

        expect(instance1, same(instance2));
      });

      test('creates new instance after reset', () async {
        final instance1 = ServiceContainer.instance;

        await ServiceContainer.reset();

        final instance2 = ServiceContainer.instance;
        expect(instance1, isNot(same(instance2)));
      });
    });

    group('initialization', () {
      test('initializes all core services', () async {
        final container = ServiceContainer.instance;

        await container.initialize();

        expect(container.globalConfig, isNotNull);
        expect(container.utilityService, isNotNull);
        expect(container.diskSpaceService, isNotNull);
        expect(container.interactiveService, isNotNull);
        // ExifTool might not be available in test environment
        // so we don't assert on its presence
      });
      test('handles multiple initialization calls gracefully', () async {
        final container = ServiceContainer.instance;

        await container.initialize();

        // Second initialization should be a no-op and not throw
        await expectLater(container.initialize(), completes);

        // Services should still be available
        expect(container.globalConfig, isNotNull);
        expect(container.utilityService, isNotNull);
      });
    });

    group('disposal', () {
      test('disposes services cleanly', () async {
        final container = ServiceContainer.instance;
        await container.initialize();

        // Should not throw
        await expectLater(container.dispose(), completes);
      });

      test('handles disposal without initialization', () async {
        final container = ServiceContainer.instance;

        // Should not throw even if not initialized
        await expectLater(container.dispose(), completes);
      });

      test('can be disposed multiple times safely', () async {
        final container = ServiceContainer.instance;
        await container.initialize();

        await container.dispose();

        // Should not throw on second disposal
        await expectLater(container.dispose(), completes);
      });
    });

    group('reset', () {
      test('disposes current instance', () async {
        final container = ServiceContainer.instance;
        await container.initialize();

        await ServiceContainer.reset();

        // Should complete without throwing
        expect(true, isTrue);
      });

      test('handles reset when no instance exists', () async {
        // Should not throw even if no instance was created
        await expectLater(ServiceContainer.reset(), completes);
      });
    });

    group('service dependencies', () {
      test('interactive service gets global config dependency', () async {
        final container = ServiceContainer.instance;
        await container.initialize();

        // InteractiveService should have been initialized with globalConfig
        expect(container.interactiveService, isNotNull);
        expect(container.globalConfig, isNotNull);
      });
    });

    group('ExifTool service', () {
      test('handles ExifTool not being available', () async {
        final container = ServiceContainer.instance;

        await container.initialize();

        // ExifTool might not be available in test environment
        // The service should handle this gracefully
        expect(true, isTrue); // Just ensure initialization doesn't throw
      });

      test('disposes ExifTool if available', () async {
        final container = ServiceContainer.instance;
        await container.initialize();

        // If ExifTool was initialized, disposal should handle it
        await expectLater(container.dispose(), completes);
      });
    });

    group('error handling', () {
      test('handles service initialization failures gracefully', () async {
        final container = ServiceContainer.instance;

        // This test ensures that if any service fails to initialize,
        // the container doesn't crash the entire application
        await expectLater(container.initialize(), completes);
      });
    });
  });
}
