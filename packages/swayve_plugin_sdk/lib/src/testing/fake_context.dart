import '../context.dart';
import '../enums.dart';
import '../host/http.dart';
import '../host/logger.dart';
import '../host/session_capture.dart';
import '../host/settings.dart';
import '../host/storage.dart';
import '../host/webview.dart';
import '../host_info.dart';
import '../permission_enforcement.dart';
import '../providers.dart';
import '../version.dart';
import 'fake_http_client.dart';
import 'fake_session_capture.dart';
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
  ///
  /// [sessionCapture], when omitted, is backed by the same [credentials]
  /// store (also defaulted here when omitted) as [fakeCredentials] — a
  /// successful scripted capture and a plugin's later `readSecret` agree.
  factory FakeSwayvePluginContext({
    Set<SwayvePermission> permissions = const {},
    SwayveHostInfo? host,
    RecordingSwayvePluginLogger? logger,
    InMemorySwayvePluginStorage? storage,
    FakeSwayveHttpClient? http,
    InMemorySwayveCredentialStore? credentials,
    FakeSwayveSettingsView? settings,
    FakeSwayveWebViewController? webView,
    FakeSwayveSessionCaptureController? sessionCapture,
  }) {
    final resolvedCredentials = credentials ?? InMemorySwayveCredentialStore();
    return FakeSwayvePluginContext._(
      permissions: permissions,
      host: host,
      logger: logger,
      storage: storage,
      http: http,
      credentials: resolvedCredentials,
      settings: settings,
      webView: webView,
      sessionCapture: sessionCapture ??
          FakeSwayveSessionCaptureController(resolvedCredentials),
    );
  }

  FakeSwayvePluginContext._({
    Set<SwayvePermission> permissions = const {},
    SwayveHostInfo? host,
    RecordingSwayvePluginLogger? logger,
    InMemorySwayvePluginStorage? storage,
    FakeSwayveHttpClient? http,
    required InMemorySwayveCredentialStore credentials,
    FakeSwayveSettingsView? settings,
    FakeSwayveWebViewController? webView,
    required FakeSwayveSessionCaptureController sessionCapture,
  })  : grantedPermissions = Set<SwayvePermission>.unmodifiable(permissions),
        _host = host ?? defaultHostInfo,
        fakeLogger = logger ?? RecordingSwayvePluginLogger(),
        fakeStorage = storage ?? InMemorySwayvePluginStorage(),
        fakeHttp = http ?? FakeSwayveHttpClient(),
        fakeCredentials = credentials,
        fakeSettings = settings ?? FakeSwayveSettingsView(),
        fakeWebView = webView ?? FakeSwayveWebViewController(),
        fakeSessionCapture = sessionCapture;

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

  /// The scripted session-capture controller behind [sessionCapture].
  ///
  /// Writes a successful capture's secrets into [fakeCredentials].
  final FakeSwayveSessionCaptureController fakeSessionCapture;

  final List<SwayveSearchProvider> _searchProviders = <SwayveSearchProvider>[];
  final List<SwayveCatalogProvider> _catalogProviders =
      <SwayveCatalogProvider>[];
  final List<SwayveStreamProvider> _streamProviders = <SwayveStreamProvider>[];
  final List<SwayveMetadataProvider> _metadataProviders =
      <SwayveMetadataProvider>[];
  final List<SwayveMetadataSearchProvider> _metadataSearchProviders =
      <SwayveMetadataSearchProvider>[];
  final List<SwayveLyricsProvider> _lyricsProviders = <SwayveLyricsProvider>[];
  final List<SwayveScrobbleProvider> _scrobbleProviders =
      <SwayveScrobbleProvider>[];
  final List<SwayveArtworkProvider> _artworkProviders =
      <SwayveArtworkProvider>[];
  final List<SwayvePlaylistProvider> _playlistProviders =
      <SwayvePlaylistProvider>[];
  final List<SwayveArtistActivityProvider> _artistActivityProviders =
      <SwayveArtistActivityProvider>[];
  final List<SwayveAuthProvider> _authProviders = <SwayveAuthProvider>[];
  final List<SwayveLibraryProvider> _libraryProviders =
      <SwayveLibraryProvider>[];
  final List<SwayveLibraryPushProvider> _libraryPushProviders =
      <SwayveLibraryPushProvider>[];

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

  /// The metadata-search providers registered so far.
  List<SwayveMetadataSearchProvider> get metadataSearchProviders =>
      List.unmodifiable(_metadataSearchProviders);

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

  /// The artist-activity providers registered so far.
  List<SwayveArtistActivityProvider> get artistActivityProviders =>
      List.unmodifiable(_artistActivityProviders);

  /// The auth providers registered so far.
  List<SwayveAuthProvider> get authProviders =>
      List.unmodifiable(_authProviders);

  /// The library providers registered so far.
  List<SwayveLibraryProvider> get libraryProviders =>
      List.unmodifiable(_libraryProviders);

  /// The library-push providers registered so far.
  List<SwayveLibraryPushProvider> get libraryPushProviders =>
      List.unmodifiable(_libraryPushProviders);

  /// The capabilities implied by everything registered so far.
  ///
  /// Compare it with the plugin's declared capabilities to prove the two
  /// agree in both directions.
  Set<SwayveCapability> get registeredCapabilities => {
        if (_searchProviders.isNotEmpty) SwayveCapability.search,
        if (_catalogProviders.isNotEmpty) SwayveCapability.catalog,
        if (_streamProviders.isNotEmpty) SwayveCapability.streaming,
        if (_metadataProviders.isNotEmpty) SwayveCapability.metadata,
        if (_metadataSearchProviders.isNotEmpty)
          SwayveCapability.metadataSearch,
        if (_lyricsProviders.isNotEmpty) SwayveCapability.lyrics,
        if (_scrobbleProviders.isNotEmpty) SwayveCapability.scrobbling,
        if (_artworkProviders.isNotEmpty) SwayveCapability.artwork,
        if (_playlistProviders.isNotEmpty) SwayveCapability.playlistRead,
        if (_artistActivityProviders.isNotEmpty)
          SwayveCapability.artistActivity,
        if (_authProviders.isNotEmpty) SwayveCapability.authentication,
        if (_libraryProviders.isNotEmpty) SwayveCapability.personalLibrary,
        if (_libraryPushProviders.isNotEmpty)
          SwayveCapability.personalLibraryPush,
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
  SwayveSessionCaptureController get sessionCapture => guardAll(
        const {SwayvePermission.webview, SwayvePermission.externalAuth},
        () => fakeSessionCapture,
      );

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
  void registerMetadataSearchProvider(SwayveMetadataSearchProvider provider) =>
      _metadataSearchProviders.add(provider);

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
  void registerArtistActivityProvider(
    SwayveArtistActivityProvider provider,
  ) =>
      _artistActivityProviders.add(provider);

  @override
  void registerAuthProvider(SwayveAuthProvider provider) =>
      _authProviders.add(provider);

  @override
  void registerLibraryProvider(SwayveLibraryProvider provider) =>
      _libraryProviders.add(provider);

  @override
  void registerLibraryPushProvider(SwayveLibraryPushProvider provider) =>
      _libraryPushProviders.add(provider);
}
