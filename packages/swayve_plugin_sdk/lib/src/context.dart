import 'host/http.dart';
import 'host/logger.dart';
import 'host/settings.dart';
import 'host/storage.dart';
import 'host/webview.dart';
import 'host_info.dart';
import 'providers.dart';

/// Everything a plugin is allowed to touch, and the only way to reach the
/// host.
///
/// The context is handed to `SwayvePlugin.initialize` and is valid until
/// `dispose` completes. A plugin holds on to it, registers the providers for
/// the capabilities it declared, and uses the facilities its permissions
/// allow.
///
/// **Permission-guarded facilities** — [storage], [http], [credentials] and
/// [webView] — throw `SwayvePermissionDeniedException` **synchronously** when
/// the plugin did not declare the matching permission. Reading the getter is
/// what throws, not the first call on it, so the failure names the line that
/// over-reached. [host], [log] and [settings] are always available.
///
/// **Registration** is only valid during `initialize`. A host may reject a
/// provider registered later, and it always rejects a provider whose
/// capability the manifest did not declare — a plugin cannot acquire
/// behaviour it did not ask for at install time.
abstract interface class SwayvePluginContext {
  /// Facts about the Swayve instance the plugin is running in.
  SwayveHostInfo get host;

  /// The plugin's channel into host diagnostics. Never logs secrets.
  SwayvePluginLogger get log;

  /// The plugin's isolated key-value store.
  ///
  /// Requires the `local_plugin_storage` permission.
  SwayvePluginStorage get storage;

  /// The host-mediated HTTP client, restricted to the manifest's declared
  /// hosts.
  ///
  /// Requires the `network` permission.
  SwayveHttpClient get http;

  /// The plugin's own credential slot in the platform secret store.
  ///
  /// Requires the `external_auth` permission.
  SwayveCredentialStore get credentials;

  /// Read access to the settings the user configured for this plugin.
  SwayveSettingsView get settings;

  /// A host-rendered web view for sign-in or embedded playback.
  ///
  /// Requires the `webview` permission.
  SwayveWebViewController get webView;

  /// Registers the plugin's `search` implementation.
  void registerSearchProvider(SwayveSearchProvider provider);

  /// Registers the plugin's `catalog` implementation.
  void registerCatalogProvider(SwayveCatalogProvider provider);

  /// Registers the plugin's `streaming` implementation.
  void registerStreamProvider(SwayveStreamProvider provider);

  /// Registers the plugin's `metadata` implementation.
  void registerMetadataProvider(SwayveMetadataProvider provider);

  /// Registers the plugin's `lyrics` implementation.
  void registerLyricsProvider(SwayveLyricsProvider provider);

  /// Registers the plugin's `scrobbling` implementation.
  void registerScrobbleProvider(SwayveScrobbleProvider provider);

  /// Registers the plugin's `artwork` implementation.
  void registerArtworkProvider(SwayveArtworkProvider provider);

  /// Registers the plugin's `playlist_read` implementation.
  void registerPlaylistProvider(SwayvePlaylistProvider provider);

  /// Registers the plugin's `authentication` implementation.
  void registerAuthProvider(SwayveAuthProvider provider);
}
