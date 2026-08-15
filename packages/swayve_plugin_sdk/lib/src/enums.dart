/// A unit of behaviour a plugin declares in its manifest.
///
/// The vocabulary is closed: a manifest carrying an unknown capability string
/// is rejected by the validator, and [fromWire] returns `null` for it. Each
/// capability maps one-to-one onto a provider interface, and declaring a
/// capability obliges the plugin to register that provider during
/// `initialize`.
enum SwayveCapability {
  /// Free-text search. Requires a `SwayveSearchProvider`.
  search,

  /// Browsing albums, artists and tracks. Requires a `SwayveCatalogProvider`.
  catalog,

  /// Resolving a media id to something playable. Requires a
  /// `SwayveStreamProvider`.
  streaming,

  /// Enriching a track the host already has. Requires a
  /// `SwayveMetadataProvider`.
  metadata,

  /// Plain or synced lyrics. Requires a `SwayveLyricsProvider`.
  lyrics,

  /// Reporting plays to an external service. Requires a
  /// `SwayveScrobbleProvider`.
  scrobbling,

  /// A user-facing sign-in flow. Requires a `SwayveAuthProvider` and the
  /// `externalAuth` permission.
  authentication,

  /// Host-rendered web views, for auth or embedded playback. Requires the
  /// `webview` permission.
  webview,

  /// Cover art and images. Requires a `SwayveArtworkProvider`.
  artwork,

  /// Read-only playlist browsing. Requires a `SwayvePlaylistProvider`.
  ///
  /// Its wire name is `playlist_read`.
  playlistRead;

  /// The manifest spelling of this capability.
  ///
  /// This is the only representation that may appear in `plugin.json`, in a
  /// bundle, or on the wire. The Dart name is an implementation detail and
  /// may be camelCase where the wire name is snake_case.
  String get wireName => switch (this) {
        SwayveCapability.search => 'search',
        SwayveCapability.catalog => 'catalog',
        SwayveCapability.streaming => 'streaming',
        SwayveCapability.metadata => 'metadata',
        SwayveCapability.lyrics => 'lyrics',
        SwayveCapability.scrobbling => 'scrobbling',
        SwayveCapability.authentication => 'authentication',
        SwayveCapability.webview => 'webview',
        SwayveCapability.artwork => 'artwork',
        SwayveCapability.playlistRead => 'playlist_read',
      };

  /// The capability named [wire], or `null` if the name is not in the v1
  /// vocabulary.
  ///
  /// Returning `null` rather than throwing is deliberate: a host reading a
  /// manifest from a newer plugin must be able to report "unknown capability"
  /// as a validation problem instead of crashing.
  static SwayveCapability? fromWire(String wire) {
    for (final value in SwayveCapability.values) {
      if (value.wireName == wire) return value;
    }
    return null;
  }
}

/// A right a plugin must declare in its manifest before the host will grant
/// the matching context facility.
///
/// Principle 4: permissions are the security model. The set is closed and
/// deliberately small; anything not listed here — user music files, Swayve
/// account credentials, other plugins' storage, arbitrary filesystem paths,
/// device secrets, background execution — is not grantable in v1.
enum SwayvePermission {
  /// Outbound HTTP(S) through the host-provided client, restricted to the
  /// hostnames declared in the manifest. Guards `SwayvePluginContext.http`.
  network,

  /// The host may render a plugin-requested web view. Guards
  /// `SwayvePluginContext.webView`.
  webview,

  /// A host-mediated sign-in flow plus the plugin's own credential slot.
  /// Guards `SwayvePluginContext.credentials`.
  ///
  /// Its wire name is `external_auth`.
  externalAuth,

  /// Read/write access to the plugin's isolated storage namespace. Guards
  /// `SwayvePluginContext.storage`.
  ///
  /// Its wire name is `local_plugin_storage`.
  localPluginStorage,

  /// Write-only access to the system clipboard. The host never grants read
  /// access.
  clipboard;

  /// The manifest spelling of this permission.
  String get wireName => switch (this) {
        SwayvePermission.network => 'network',
        SwayvePermission.webview => 'webview',
        SwayvePermission.externalAuth => 'external_auth',
        SwayvePermission.localPluginStorage => 'local_plugin_storage',
        SwayvePermission.clipboard => 'clipboard',
      };

  /// The permission named [wire], or `null` if the name is not in the v1
  /// vocabulary.
  static SwayvePermission? fromWire(String wire) {
    for (final value in SwayvePermission.values) {
      if (value.wireName == wire) return value;
    }
    return null;
  }
}

/// A platform Swayve runs on.
///
/// A plugin declares the platforms it supports; the host refuses to load a
/// plugin that does not list the platform it is running on.
enum SwayvePlatform {
  /// Android.
  android,

  /// iOS and iPadOS. Note that `runtime: bundled` plugins are never loaded
  /// here.
  ios,

  /// Windows.
  windows,

  /// macOS.
  macos,

  /// Linux.
  linux;

  /// The manifest spelling of this platform.
  String get wireName => name;

  /// The platform named [wire], or `null` if unknown.
  static SwayvePlatform? fromWire(String wire) {
    for (final value in SwayvePlatform.values) {
      if (value.wireName == wire) return value;
    }
    return null;
  }
}

/// The size class a caller wants artwork in.
///
/// These are intents, not pixel guarantees. A provider returns the closest
/// asset it has and reports the real dimensions on the returned image.
enum SwayveArtworkSize {
  /// List-row sized art.
  thumbnail,

  /// Grid-tile sized art.
  medium,

  /// Now-playing sized art.
  large,

  /// Whatever the provider considers the source asset.
  original;

  /// The wire spelling of this size.
  String get wireName => name;

  /// The size named [wire], or `null` if unknown.
  static SwayveArtworkSize? fromWire(String wire) {
    for (final value in SwayveArtworkSize.values) {
      if (value.wireName == wire) return value;
    }
    return null;
  }
}

/// A kind of entity a search may ask for.
enum SwayveSearchKind {
  /// Individual tracks.
  track,

  /// Albums.
  album,

  /// Artists.
  artist,

  /// Playlists.
  playlist;

  /// The wire spelling of this kind.
  String get wireName => name;

  /// The kind named [wire], or `null` if unknown.
  static SwayveSearchKind? fromWire(String wire) {
    for (final value in SwayveSearchKind.values) {
      if (value.wireName == wire) return value;
    }
    return null;
  }
}

/// The ordering a browse request asks for.
///
/// A provider that cannot honour the requested order must still return
/// results; ordering is a hint, not a guarantee.
enum SwayveSortOrder {
  /// The provider's own notion of relevance.
  relevance,

  /// A to Z by the entity's display name.
  alphabetical,

  /// Most recently added or released first.
  recent,

  /// Most popular first.
  popular;

  /// The wire spelling of this order.
  String get wireName => name;

  /// The order named [wire], or `null` if unknown.
  static SwayveSortOrder? fromWire(String wire) {
    for (final value in SwayveSortOrder.values) {
      if (value.wireName == wire) return value;
    }
    return null;
  }
}

/// How the host should play a resolved source.
///
/// The host switches on this and nothing else. It never learns which service
/// produced the source (principle 2).
enum SwayvePlayableKind {
  /// A single progressive media URL. Wire name `direct_url`.
  directUrl,

  /// An HLS manifest URL. Wire name `hls_url`.
  hlsUrl,

  /// A DASH manifest URL. Wire name `dash_url`.
  dashUrl,

  /// A file already on the device. Wire name `local_file`.
  localFile,

  /// Playback inside a host-rendered web surface. Wire name `web_embed`.
  webEmbed;

  /// The wire spelling of this kind.
  String get wireName => switch (this) {
        SwayvePlayableKind.directUrl => 'direct_url',
        SwayvePlayableKind.hlsUrl => 'hls_url',
        SwayvePlayableKind.dashUrl => 'dash_url',
        SwayvePlayableKind.localFile => 'local_file',
        SwayvePlayableKind.webEmbed => 'web_embed',
      };

  /// The kind named [wire], or `null` if unknown.
  static SwayvePlayableKind? fromWire(String wire) {
    for (final value in SwayvePlayableKind.values) {
      if (value.wireName == wire) return value;
    }
    return null;
  }
}

/// A web playback surface the host is able to render.
///
/// A plugin must check `SwayveHostInfo.supportedEmbeds` before returning a
/// web embed: an unsupported embed kind is an unplayable track.
enum SwayveWebEmbedKind {
  /// An `<iframe>` on a web build.
  iframe,

  /// An in-app web view on a native build. Wire name `in_app_web_view`.
  inAppWebView;

  /// The wire spelling of this embed kind.
  String get wireName => switch (this) {
        SwayveWebEmbedKind.iframe => 'iframe',
        SwayveWebEmbedKind.inAppWebView => 'in_app_web_view',
      };

  /// The embed kind named [wire], or `null` if unknown.
  static SwayveWebEmbedKind? fromWire(String wire) {
    for (final value in SwayveWebEmbedKind.values) {
      if (value.wireName == wire) return value;
    }
    return null;
  }
}

/// A transport control the host may drive on a web embed.
///
/// A control that is not listed is not available: the host must hide or
/// disable the corresponding affordance rather than trying it and failing.
enum SwayveEmbedControl {
  /// The host may start playback.
  play,

  /// The host may pause playback.
  pause,

  /// The host may seek to a position.
  seek,

  /// The host may set the volume.
  volume,

  /// The embed reports playback position back to the host. Wire name
  /// `position_updates`.
  positionUpdates;

  /// The wire spelling of this control.
  String get wireName => switch (this) {
        SwayveEmbedControl.play => 'play',
        SwayveEmbedControl.pause => 'pause',
        SwayveEmbedControl.seek => 'seek',
        SwayveEmbedControl.volume => 'volume',
        SwayveEmbedControl.positionUpdates => 'position_updates',
      };

  /// The control named [wire], or `null` if unknown.
  static SwayveEmbedControl? fromWire(String wire) {
    for (final value in SwayveEmbedControl.values) {
      if (value.wireName == wire) return value;
    }
    return null;
  }
}

/// Where a plugin's authentication stands.
enum SwayveAuthStatus {
  /// The user has not signed in, and the plugin can work without it.
  signedOut,

  /// A sign-in flow is in progress.
  authenticating,

  /// The user is signed in.
  signedIn,

  /// The stored session expired or was revoked; the user must sign in again.
  expired,

  /// The last sign-in attempt failed.
  failed;

  /// The wire spelling of this status.
  String get wireName => switch (this) {
        SwayveAuthStatus.signedOut => 'signed_out',
        SwayveAuthStatus.authenticating => 'authenticating',
        SwayveAuthStatus.signedIn => 'signed_in',
        SwayveAuthStatus.expired => 'expired',
        SwayveAuthStatus.failed => 'failed',
      };

  /// The status named [wire], or `null` if unknown.
  static SwayveAuthStatus? fromWire(String wire) {
    for (final value in SwayveAuthStatus.values) {
      if (value.wireName == wire) return value;
    }
    return null;
  }
}
