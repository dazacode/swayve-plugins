import '../context.dart';
import '../enums.dart';
import '../host/http.dart';
import '../host/logger.dart';
import '../host/settings.dart';
import '../host/storage.dart';
import '../host/webview.dart';
import '../host_info.dart';
import '../permission_enforcement.dart';
import '../providers.dart';
import '../version.dart';
import 'fake_http_client.dart';
import 'fake_settings.dart';
import 'fake_webview.dart';
import 'in_memory_stores.dart';
import 'recording_logger.dart';

/// A [SwayvePluginContext] a plugin can be initialized against in a plain
/// `dart test`.
///
/// It exists to catch two classes of bug before a user ever sees them:
///
/// * **over-reach.** The context enforces [permissions] through the same
///   `SwayvePermissionEnforcement` mixin the host uses, so touching an
///   undeclared facility throws `SwayvePermissionDeniedException` here
///   exactly as it would on a device. Construct it with the permissions your
///   `plugin.json` actually declares — not with all of them — and the test
///   suite becomes a permission audit.
/// * **unregistered capabilities.** Every `register*` call is recorded, so a
///   test can assert that a plugin registered a provider for each capability
///   it declared and none that it did not.
///
/// Every facility has a working in-memory implementation, and each can be
/// replaced through the constructor when a test needs to script behaviour.
final class FakeSwayvePluginContext
    with SwayvePermissionEnforcement
    implements SwayvePluginContext {
  /// Creates a context granting exactly [permissions].
  ///
  /// The default grants nothing, which is the right default: a test must opt
  /// in to each permission its manifest declares.
  FakeSwayvePluginContext({
    Set<SwayvePermission> permissions = const {},
    SwayveHostInfo? host,
    RecordingSwayvePluginLogger? logger,
    InMemorySwayvePluginStorage? storage,
    FakeSwayveHttpClient? http,
    InMemorySwayveCredentialStore? credentials,
    FakeSwayveSettingsView? settings,
    FakeSwayveWebViewController? webView,
  })  : grantedPermissions = Set<SwayvePermission>.unmodifiable(permissions),
        _host = host ?? defaultHostInfo,
        fakeLogger = logger ?? RecordingSwayvePluginLogger(),
        fakeStorage = storage ?? InMemorySwayvePluginStorage(),
        fakeHttp = http ?? FakeSwayveHttpClient(),
        fakeCredentials = credentials ?? InMemorySwayveCredentialStore(),
        fakeSettings = settings ?? FakeSwayveSettingsView(),
        fakeWebView = webView ?? FakeSwayveWebViewController();

  /// The host a fake context describes unless a test says otherwise:
  /// Swayve 1.1.0 on Android, API level 1, able to render an in-app web view.
  static const SwayveHostInfo defaultHostInfo = SwayveHostInfo(
    swayveVersion: Version(1, 1, 0),
    swayvePluginApi: 1,
    platform: SwayvePlatform.android,
    supportedEmbeds: {SwayveWebEmbedKind.inAppWebView},
    locale: 'en-GB',
    region: 'GB',
  );

  @override
  final Set<SwayvePermission> grantedPermissions;

  final SwayveHostInfo _host;

  /// The recording logger behind [log], for assertions.
  final RecordingSwayvePluginLogger fakeLogger;

  /// The in-memory store behind [storage], for assertions.
  ///
  /// Reachable without the `local_plugin_storage` permission on purpose: a
  /// test inspects it, a plugin must go through [storage].
  final InMemorySwayvePluginStorage fakeStorage;

  /// The scripted client behind [http], for queueing responses and asserting
  /// on requests.
  final FakeSwayveHttpClient fakeHttp;

  /// The in-memory secret store behind [credentials], for assertions.
  final InMemorySwayveCredentialStore fakeCredentials;

  /// The settings view behind [settings]. Use its `set` to simulate the user
  /// changing a setting.
  final FakeSwayveSettingsView fakeSettings;

  /// The scripted web view behind [webView].
  final FakeSwayveWebViewController fakeWebView;

  final List<SwayveSearchProvider> _searchProviders = <SwayveSearchProvider>[];
  final List<SwayveCatalogProvider> _catalogProviders =
      <SwayveCatalogProvider>[];
  final List<SwayveStreamProvider> _streamProviders = <SwayveStreamProvider>[];
  final List<SwayveMetadataProvider> _metadataProviders =
      <SwayveMetadataProvider>[];
  final List<SwayveLyricsProvider> _lyricsProviders = <SwayveLyricsProvider>[];
  final List<SwayveScrobbleProvider> _scrobbleProviders =
      <SwayveScrobbleProvider>[];
  final List<SwayveArtworkProvider> _artworkProviders =
      <SwayveArtworkProvider>[];
  final List<SwayvePlaylistProvider> _playlistProviders =
      <SwayvePlaylistProvider>[];
  final List<SwayveAuthProvider> _authProviders = <SwayveAuthProvider>[];

  /// The search providers registered so far.
  List<SwayveSearchProvider> get searchProviders =>
      List.unmodifiable(_searchProviders);

  /// The catalog providers registered so far.
  List<SwayveCatalogProvider> get catalogProviders =>
      List.unmodifiable(_catalogProviders);

  /// The stream providers registered so far.
  List<SwayveStreamProvider> get streamProviders =>
      List.unmodifiable(_streamProviders);

  /// The metadata providers registered so far.
  List<SwayveMetadataProvider> get metadataProviders =>
      List.unmodifiable(_metadataProviders);

  /// The lyrics providers registered so far.
  List<SwayveLyricsProvider> get lyricsProviders =>
      List.unmodifiable(_lyricsProviders);

  /// The scrobble providers registered so far.
  List<SwayveScrobbleProvider> get scrobbleProviders =>
      List.unmodifiable(_scrobbleProviders);

  /// The artwork providers registered so far.
  List<SwayveArtworkProvider> get artworkProviders =>
      List.unmodifiable(_artworkProviders);

  /// The playlist providers registered so far.
  List<SwayvePlaylistProvider> get playlistProviders =>
      List.unmodifiable(_playlistProviders);

  /// The auth providers registered so far.
  List<SwayveAuthProvider> get authProviders =>
      List.unmodifiable(_authProviders);

  /// The capabilities implied by everything registered so far.
  ///
  /// Compare it with the plugin's declared capabilities to prove the two
  /// agree in both directions.
  Set<SwayveCapability> get registeredCapabilities => {
        if (_searchProviders.isNotEmpty) SwayveCapability.search,
        if (_catalogProviders.isNotEmpty) SwayveCapability.catalog,
        if (_streamProviders.isNotEmpty) SwayveCapability.streaming,
        if (_metadataProviders.isNotEmpty) SwayveCapability.metadata,
        if (_lyricsProviders.isNotEmpty) SwayveCapability.lyrics,
        if (_scrobbleProviders.isNotEmpty) SwayveCapability.scrobbling,
        if (_artworkProviders.isNotEmpty) SwayveCapability.artwork,
        if (_playlistProviders.isNotEmpty) SwayveCapability.playlistRead,
        if (_authProviders.isNotEmpty) SwayveCapability.authentication,
      };

  /// Releases the resources the fakes hold. Call it in a test's teardown.
  Future<void> close() async {
    fakeHttp.cancelHangs();
    await fakeSettings.close();
  }

  @override
  SwayveHostInfo get host => _host;

  @override
  SwayvePluginLogger get log => fakeLogger;

  @override
  SwayvePluginStorage get storage =>
      guard(SwayvePermission.localPluginStorage, () => fakeStorage);

  @override
  SwayveHttpClient get http => guard(SwayvePermission.network, () => fakeHttp);

  @override
  SwayveCredentialStore get credentials =>
      guard(SwayvePermission.externalAuth, () => fakeCredentials);

  @override
  SwayveSettingsView get settings => fakeSettings;

  @override
  SwayveWebViewController get webView =>
      guard(SwayvePermission.webview, () => fakeWebView);

  @override
  void registerSearchProvider(SwayveSearchProvider provider) =>
      _searchProviders.add(provider);

  @override
  void registerCatalogProvider(SwayveCatalogProvider provider) =>
      _catalogProviders.add(provider);

  @override
  void registerStreamProvider(SwayveStreamProvider provider) =>
      _streamProviders.add(provider);

  @override
  void registerMetadataProvider(SwayveMetadataProvider provider) =>
      _metadataProviders.add(provider);

  @override
  void registerLyricsProvider(SwayveLyricsProvider provider) =>
      _lyricsProviders.add(provider);

  @override
  void registerScrobbleProvider(SwayveScrobbleProvider provider) =>
      _scrobbleProviders.add(provider);

  @override
  void registerArtworkProvider(SwayveArtworkProvider provider) =>
      _artworkProviders.add(provider);

  @override
  void registerPlaylistProvider(SwayvePlaylistProvider provider) =>
      _playlistProviders.add(provider);

  @override
  void registerAuthProvider(SwayveAuthProvider provider) =>
      _authProviders.add(provider);
}
