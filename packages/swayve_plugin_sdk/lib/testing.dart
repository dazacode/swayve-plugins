/// Test doubles for everything a Swayve host provides.
///
/// Import this alongside `package:swayve_plugin_sdk/swayve_plugin_sdk.dart`
/// in your `test/` directory to exercise a plugin end to end — initialize,
/// register, resolve, dispose — with no host, no Flutter and no network:
///
/// ```dart
/// final context = FakeSwayvePluginContext(
///   permissions: {SwayvePermission.network},
/// );
/// context.fakeHttp.enqueueJson({'items': []});
/// await plugin.initialize(context);
/// ```
///
/// The fakes are not lenient stand-ins. [FakeSwayvePluginContext] enforces
/// the permission set you declare, so a plugin that reaches for a facility
/// its manifest never asked for fails in your test suite instead of on a
/// user's phone — which is the point of shipping them at all.
///
/// This library is deliberately not exported from the main library: nothing
/// in a shipping plugin should ever import a fake.
library;

export 'src/testing/cancellation_token_source.dart';
export 'src/testing/fake_context.dart';
export 'src/testing/fake_http_client.dart';
export 'src/testing/fake_settings.dart';
export 'src/testing/fake_webview.dart';
export 'src/testing/in_memory_stores.dart';
export 'src/testing/recording_logger.dart';
