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
  playlistRead,

  /// An artist's own public activity on the provider's service — what they
  /// liked, what they reposted. Requires a `SwayveArtistActivityProvider`.
  ///
  /// Unlike every capability above it, most providers have nothing here: this
  /// is a fact about a specific service's social features, not something every
  /// catalogue can be expected to answer. A provider declares it only when it
  /// genuinely has this concept — the vocabulary is generic so any provider
  /// that grows one can say so, not a promise that all of them will.
  ///
  /// Its wire name is `artist_activity`.
  artistActivity;

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
        SwayveCapability.artistActivity => 'artist_activity',
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

/// What a recording is, as the provider that published it understands it.
///
/// Not a kind of *entity* — everything here is still a `SwayveTrack`, still
/// playable, still likeable, still queueable. It is a note about where the
/// recording came from, and it exists because for several services that
/// difference is real and the host cannot infer it.
///
/// The case it was added for: a music service usually has two catalogues behind
/// one search box. One holds licensed releases, with an album, a sleeve and a
/// credit behind every row. The other holds whatever people uploaded — and that
/// is where the unreleased track, the remix, the demo, the live rip and the
/// edit live, very often as the only copy in existence. A host that cannot tell
/// them apart must either mix them into one list, which buries a known release
/// under nine covers of it, or drop the second catalogue, which is the same as
/// telling somebody a song they can hear right now does not exist.
///
/// A provider that does not draw this distinction leaves it at [song], which is
/// what the default means: *a recording, nothing further claimed*. It is not a
/// promise that a release exists behind it.
enum SwayveTrackKind {
  /// A recording from the provider's own music catalogue.
  ///
  /// The default, and the honest answer whenever a provider has only one
  /// catalogue or cannot tell which one a row came from.
  song,

  /// A video upload, published outside the music catalogue.
  ///
  /// Expect no album, no release year, and artwork that is a frame rather than
  /// a sleeve. Expect the audio to be worth having anyway.
  video;

  /// The wire spelling of this kind.
  String get wireName => name;

  /// The kind named [wire], or `null` if unknown.
  ///
  /// An unknown spelling is a provider built against a later SDK than this
  /// host. Callers read it as [song] rather than as an error: a recording whose
  /// provenance cannot be read is still a recording, and refusing to parse the
  /// track would lose the music over a label.
  static SwayveTrackKind? fromWire(String wire) {
    for (final value in SwayveTrackKind.values) {
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

/// A kind of thing a source can be asked for.
///
/// Declared per source rather than assumed of every source, because sources
/// genuinely differ: a service built on user uploads has no album to speak of,
/// a video service answers with uploads and nothing else, and a plugin that
/// only publishes a chart cannot be searched at all. The host draws a filter
/// row from this, and a filter row offering *Albums* when the only source
/// selected has never heard of an album is an interface lying about what it
/// can do.
///
/// The rejected alternative was to reuse [SwayveSearchKind], which already
/// names tracks, albums, artists and playlists. It is the wrong list twice
/// over: it has no word for a video upload, which is exactly the distinction
/// [SwayveTrackKind] exists to draw, and it names playlists, which are browsed
/// rather than filtered for. A request parameter and a declaration of reach
/// are different vocabularies that happen to overlap, and collapsing them
/// would mean neither could grow a member without disturbing the other.
enum SwayveContentType {
  /// Individual recordings.
  songs,

  /// Releases.
  albums,

  /// Artists in their own right, not merely as a track's credit.
  artists,

  /// Video uploads — the [SwayveTrackKind.video] half of a catalogue.
  videos;

  /// The wire spelling of this content type.
  String get wireName => name;

  /// The content type named [wire], or `null` if unknown.
  ///
  /// A caller reading a manifest drops an unknown member rather than failing
  /// the read. A plugin built against a later SDK naming a fifth kind of
  /// content is describing reach this host has no way to offer anyway, and
  /// refusing the whole source over a word in a list would lose the four kinds
  /// it does understand.
  static SwayveContentType? fromWire(String wire) {
    for (final value in SwayveContentType.values) {
      if (value.wireName == wire) return value;
    }
    return null;
  }
}

/// Whether a source can answer right now, and why not when it cannot.
///
/// Deliberately not a bool, and deliberately finer-grained than the four states
/// the host displays. "Cannot answer" has causes a person responds to
/// completely differently — a service that is rate limited will come back on
/// its own, a lapsed session needs signing into again, a plugin somebody
/// switched off is doing exactly what it was told — and collapsing them into
/// `available: false` is what produces an interface that says *unavailable* and
/// leaves somebody with nothing to do about it.
///
/// The plugin names the cause; the host decides how many buckets to draw it in.
/// That direction matters: a plugin knows why its own service is quiet and the
/// host never can, so widening this list later costs the host nothing — an
/// unrecognised cause reads as [offline], which is the honest default for
/// *something is wrong and nobody here can say what*.
enum SwayveSourceAvailability {
  /// Answering now.
  ready,

  /// Reachable in principle, not right now — no network, the service
  /// unreachable, a request that timed out. Nothing needs doing.
  offline,

  /// The service answered, and said this account is asking too often. Comes
  /// back on its own, so nothing needs doing here either — but it is worth
  /// telling apart from [offline], because the music is there and the plugin
  /// is working.
  ///
  /// Its wire name is `rate_limited`.
  rateLimited,

  /// Needs the person to do something: sign in, sign in again, re-authorise.
  ///
  /// Its wire name is `signed_out`.
  signedOut,

  /// Deliberately switched off, by the person or by the plugin itself.
  off;

  /// The wire spelling of this availability.
  String get wireName => switch (this) {
        SwayveSourceAvailability.ready => 'ready',
        SwayveSourceAvailability.offline => 'offline',
        SwayveSourceAvailability.rateLimited => 'rate_limited',
        SwayveSourceAvailability.signedOut => 'signed_out',
        SwayveSourceAvailability.off => 'off',
      };

  /// Whether a query sent now could produce anything.
  bool get canAnswer => this == SwayveSourceAvailability.ready;

  /// The availability named [wire], or `null` if unknown.
  static SwayveSourceAvailability? fromWire(String wire) {
    for (final value in SwayveSourceAvailability.values) {
      if (value.wireName == wire) return value;
    }
    return null;
  }
}
