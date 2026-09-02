import 'package:meta/meta.dart';

import 'internal/json.dart';

/// The vocabulary a host and an embedded player use to talk to each other.
///
/// ## The problem this solves
///
/// `SwayveWebEmbed.controls` has always been able to say that a page *could* be
/// paused. Nothing could act on it. Pausing a specific service's player means
/// calling that service's JavaScript, and a host that knew the call would be a
/// host with hardcoded knowledge of one plugin — precisely what principle 2
/// rules out. So hosts rendered embeds as sealed rectangles: the service's own
/// chrome, the service's own controls, and the app's transport standing down
/// for the duration.
///
/// The way out is not to teach the host the incantation but to move the
/// incantation to where the knowledge already is. A plugin ships a small page —
/// `SwayveWebEmbed.document` — that loads its player and re-exposes it under the
/// fixed names below. The host loads that page, calls those names, and listens
/// on one channel. Neither side learns anything about the other: the host does
/// not know whose player it is driving, and the plugin does not know what the
/// controls look like.
///
/// ## The contract, in full
///
/// A document must:
///
/// 1. Define an object at [objectName] on the global scope, carrying whichever
///    of [play], [pause], [seek], [setMuted] correspond to the controls the
///    embed declared. A control declared but not defined is a broken promise; a
///    function defined but not declared is never called.
/// 2. Post [SwayveEmbedEvent]s, JSON-encoded, to the host channel at
///    [channelName], by calling its `postMessage` with one string argument.
/// 3. Post a [SwayveEmbedEventType.ready] event once its player can accept
///    calls, and never before. The host queues nothing: a call made earlier is
///    a call that lands on a player that does not exist yet.
///
/// A host must:
///
/// 1. Register the channel at [channelName] *before* loading the document, or
///    a page that is ready immediately will post into nothing.
/// 2. Load the document with the embed's `uri` as the base address, so the
///    page's origin is the service's own. A player API script will refuse to
///    run from `about:blank`.
/// 3. Never call a function the embed did not declare in its controls.
/// 4. Treat a silent page as a page that failed. A document that never says
///    [SwayveEmbedEventType.ready] is not a document to wait on forever.
///
/// ## Why the names are ugly
///
/// [objectName] and [channelName] are written into a page the host does not
/// own, alongside whatever globals the service's own player defines. Two
/// underscores and a namespace is what keeps this from colliding with a
/// `player` or a `state` that was already there.
abstract final class SwayveEmbedBridge {
  /// The global object a document defines, carrying the control functions.
  static const String objectName = '__swayve';

  /// The host channel a document posts its events to.
  static const String channelName = '__swayveHost';

  /// Starts or resumes playback. No arguments.
  static const String play = 'play';

  /// Pauses playback, leaving the position where it is. No arguments.
  static const String pause = 'pause';

  /// Seeks to a position, in **seconds** as a number.
  ///
  /// Seconds rather than milliseconds because every web media API in existence
  /// — `HTMLMediaElement.currentTime`, and every major embedded player API
  /// built over it — measures in seconds, and a bridge that converted at the
  /// boundary would make every adapter convert it back.
  static const String seek = 'seek';

  /// Sets muting, as a boolean.
  ///
  /// Muting rather than a volume level, because that is what the control
  /// actually needs to be: a phone's volume belongs to its hardware keys and
  /// its operating system, and an in-page slider fighting them is the shape of
  /// a web player nobody enjoys. A host wanting a volume level should use
  /// `SwayveEmbedControl.volume` and a document that offers `setVolume`.
  static const String setMuted = 'setMuted';
}

/// What an embedded player is doing, as it reports it.
@immutable
final class SwayveEmbedEvent {
  /// Creates an event.
  const SwayveEmbedEvent({
    required this.type,
    this.playing = false,
    this.position = Duration.zero,
    this.duration,
    this.message,
  });

  /// What happened.
  final SwayveEmbedEventType type;

  /// Whether the player is playing right now.
  final bool playing;

  /// How far in it is.
  final Duration position;

  /// How long the item is, when the player knows.
  ///
  /// Null before a player has loaded enough to say, and for a live stream,
  /// which has no end to measure against.
  final Duration? duration;

  /// What went wrong, for [SwayveEmbedEventType.error]. Already a sentence.
  final String? message;

  /// Parses one event as a document posts it.
  ///
  /// Lenient on purpose, and it is the one place in this SDK that is. Everything
  /// else parsed here crossed a boundary the SDK controls; this crossed a
  /// JavaScript channel out of a page written by a plugin author, where a number
  /// may arrive as a string and a missing field is a script that has not
  /// finished loading rather than a bug worth throwing over. A malformed event
  /// is dropped by the host; a throw here would take the player down with it.
  static SwayveEmbedEvent fromJson(Map<String, Object?> json) {
    final reader = JsonReader('SwayveEmbedEvent', json);
    return SwayveEmbedEvent(
      type: SwayveEmbedEventType.fromWire(
            reader.stringOrNull('type') ?? '',
          ) ??
          SwayveEmbedEventType.state,
      playing: json['playing'] == true,
      position: _seconds(json['position']) ?? Duration.zero,
      duration: _seconds(json['duration']),
      message: reader.stringOrNull('message'),
    );
  }

  /// The wire form.
  Map<String, Object?> toJson() => pruneNulls({
        'type': type.wireName,
        'playing': playing,
        'position': position.inMilliseconds / 1000,
        'duration': duration == null ? null : duration!.inMilliseconds / 1000,
        'message': message,
      });

  /// A number of seconds as a [Duration], or null when it is not one.
  ///
  /// Accepts a string as well as a number: JavaScript's `JSON.stringify` is
  /// consistent, but the value handed to it may have come from a player API
  /// that reports `"12.5"`, and refusing that would be pedantry at the cost of
  /// a working scrubber.
  static Duration? _seconds(Object? raw) {
    final value = switch (raw) {
      final num number => number.toDouble(),
      final String text => double.tryParse(text),
      _ => null,
    };
    if (value == null || value.isNaN || value.isNegative) return null;
    // Guarded against infinity, which a live stream's duration is reported as
    // by more than one player API and which would overflow the conversion.
    if (!value.isFinite) return null;
    return Duration(milliseconds: (value * 1000).round());
  }

  @override
  String toString() =>
      'SwayveEmbedEvent(${type.wireName}, playing: $playing, $position)';

  @override
  bool operator ==(Object other) =>
      other is SwayveEmbedEvent &&
      type == other.type &&
      playing == other.playing &&
      position == other.position &&
      duration == other.duration &&
      message == other.message;

  @override
  int get hashCode => Object.hash(type, playing, position, duration, message);
}

/// The kinds of thing an embedded player reports.
enum SwayveEmbedEventType {
  /// The player exists and will accept calls. Sent exactly once, first.
  ready,

  /// Playing, position or duration changed.
  state,

  /// The item finished on its own.
  ended,

  /// The player failed. Carries a message.
  error;

  /// The wire spelling.
  String get wireName => name;

  /// The type named [wire], or null if unknown.
  static SwayveEmbedEventType? fromWire(String wire) {
    for (final value in SwayveEmbedEventType.values) {
      if (value.wireName == wire) return value;
    }
    return null;
  }
}
