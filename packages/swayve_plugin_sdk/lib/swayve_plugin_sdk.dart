/// The contract between the Swayve music client and a Swayve plugin.
///
/// This library is pure Dart. It has no Flutter dependency, no `dart:io` and
/// no `dart:ui`, so a plugin built against it can be unit-tested with
/// `dart test` and compiled into a host that uses any UI toolkit.
///
/// The shape of the whole thing follows from a few rules:
///
/// 1. **Swayve works with zero plugins.** Nothing here is required for the
///    client to build or run.
/// 2. **The host has no hardcoded knowledge of any plugin.** It resolves
///    behaviour through the provider interfaces in this library and nothing
///    else — there is no place for `if (plugin.id == ...)`.
/// 3. **Plugins talk to their own services from the user's device.** Swayve
///    hosts no per-plugin proxy.
/// 4. **Permissions, not encryption, are the security model.** A facility a
///    plugin did not declare is not reachable.
/// 5. **Plugins supply data; the host renders UI.** No widgets cross this
///    boundary.
/// 6. **Streamable, downloadable and on-device are three independent
///    facts.** See `SwayveAvailability`.
/// 7. **A broken plugin must never break Swayve.** Every call is
///    timeout-bounded, cancellable and error-isolated.
///
/// Start at `SwayvePlugin` for the entry point, `SwayvePluginContext` for
/// what a plugin may touch, and the `Swayve*Provider` interfaces for the
/// behaviour a plugin supplies. Fakes for testing all of it live in
/// `package:swayve_plugin_sdk/testing.dart`.
library;

export 'src/cancellation.dart';
export 'src/constants.dart';
export 'src/context.dart';
export 'src/embed_bridge.dart';
export 'src/enums.dart';
export 'src/exceptions.dart';
export 'src/host/http.dart';
export 'src/host/logger.dart';
export 'src/host/session_capture.dart';
export 'src/host/settings.dart';
export 'src/host/storage.dart';
export 'src/host/webview.dart';
export 'src/host_info.dart';
export 'src/models/album.dart';
export 'src/models/alternate_names.dart';
export 'src/models/artist.dart';
export 'src/models/auth_state.dart';
export 'src/models/availability.dart';
export 'src/models/browse.dart';
export 'src/models/image_ref.dart';
export 'src/models/lyrics.dart';
export 'src/models/media_id.dart';
export 'src/models/metadata_search.dart';
export 'src/models/playlist.dart';
export 'src/models/radio.dart';
export 'src/models/refs.dart';
export 'src/models/scrobble.dart';
export 'src/models/search.dart';
export 'src/models/source_descriptor.dart';
export 'src/models/track.dart';
export 'src/models/upload.dart';
export 'src/models/visual.dart';
export 'src/permission_enforcement.dart';
export 'src/playback.dart';
export 'src/plugin.dart';
export 'src/providers.dart';
export 'src/timeouts.dart';
export 'src/version.dart';
