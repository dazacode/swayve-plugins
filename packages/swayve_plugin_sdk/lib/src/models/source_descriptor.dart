import 'package:meta/meta.dart';

import '../enums.dart';
import '../internal/equality.dart';
import '../internal/json.dart';

/// How a plugin describes itself as a *place a query can be sent*, rather than
/// as a bundle of capabilities.
///
/// The host's search is federated: this phone, every paired computer that is
/// awake, and every plugin that says it can answer all receive the same query
/// and their results come back as one set with the provenance kept. For that to
/// work the host has to be able to draw a source row — a name, a mark, what it
/// can be asked for, whether it can be asked right now — for a plugin it knows
/// nothing else about. Before this, it could not: a manifest said what provider
/// interfaces a plugin implements, which is a fact about code, and the interface
/// needed a fact about a *service*.
///
/// The rejected alternative was to let the host derive all of this from the
/// capability list — `search` means searchable, `catalog` means it has albums,
/// and so on. That reads plausibly and is wrong in both directions. A catalogue
/// provider for a service built on user uploads has no albums to offer however
/// firmly it declares `catalog`; a service with a video half and a music half
/// declares one `search` capability for two very different things. Deriving
/// would have the host inventing claims on a plugin's behalf and then rendering
/// them as though the plugin had made them.
///
/// ## What is declared once and what changes
///
/// [sourceId], [displayName], [iconName], [contentTypes] and [supportedHosts]
/// are facts about the service and are declared in `plugin.json`, so the host
/// can draw the row before the plugin has been started at all — which is
/// exactly the moment the import screen needs them.
///
/// [availability] is not that kind of fact. Whether a service can answer *right
/// now* is knowable only to the running plugin, and putting it in a manifest
/// would be a plugin claiming at packaging time to know what its service would
/// be doing months later. It is on this type because the same type serves both
/// purposes: a descriptor read from a manifest carries the declared default,
/// and a running plugin republishes the same descriptor with the live value
/// when it changes. One shape, read twice, rather than a static half and a
/// runtime half that drift.
@immutable
final class SwayveSourceDescriptor {
  /// Creates a source descriptor.
  const SwayveSourceDescriptor({
    required this.sourceId,
    required this.displayName,
    this.iconName,
    this.contentTypes = const {},
    this.capabilities = const {},
    this.availability = SwayveSourceAvailability.ready,
    this.supportedHosts = const {},
  });

  /// This source's stable identity, distinct from the plugin id.
  ///
  /// They are usually the same thing spelled differently, and deliberately not
  /// required to be: a plugin may one day front two services, and the plugin id
  /// is the identity of a *package* while this is the identity of a *place
  /// music comes from*. The host keys a person's source selection on this, so
  /// it must survive the plugin being updated, disabled and switched back on.
  final String sourceId;

  /// What a person calls this service — *Nebula Music*, *Wavecast*. Never a
  /// package name, never an id.
  ///
  /// Kept separate from the manifest's `name`, which names the plugin. They are
  /// the same string today for every first-party plugin and they are not the
  /// same thing: "Wavecast" is the service, and a plugin free to call itself
  /// "Wavecast (unofficial)" should not have that appear in a filter row as
  /// the name of the service.
  final String displayName;

  /// A name the host resolves to a glyph, or null.
  ///
  /// A name rather than an asset, because the host draws the source row and
  /// principle 5 says no image crosses this boundary for the host to lay out
  /// blind. The manifest's `icon` is the plugin's own artwork for the settings
  /// screen; this is a mark small enough for a chip, and a host that has never
  /// heard of the name falls back to a generic source mark.
  ///
  /// Null is a perfectly good answer and must stay one. A plugin shipping no
  /// icon still appears everywhere it should; inventing a glyph for it would be
  /// the host deciding what somebody else's service looks like.
  final String? iconName;

  /// What this source can be asked for.
  ///
  /// Empty means it publishes a catalogue but is not worth putting a query to —
  /// which is a real position for a plugin that only supplies a chart, and is
  /// why this is a declared set rather than an assumed one.
  final Set<SwayveContentType> contentTypes;

  /// The capabilities this source stands behind.
  ///
  /// The same [SwayveCapability] vocabulary the manifest's `capabilities` array
  /// has always used, carried here rather than re-derived, so that "can this be
  /// searched" has exactly one answer in the system. A descriptor read out of a
  /// manifest is filled from that array; nothing parallel was invented for it,
  /// because two vocabularies for one question is how they come to disagree.
  final Set<SwayveCapability> capabilities;

  /// Whether this source can answer right now. See the class comment for why
  /// this one field is not a manifest fact.
  final SwayveSourceAvailability availability;

  /// The website hostnames a pasted URL must match for the host to route it
  /// to this plugin's `resolveUrl` — `nebula.example`, `music.nebula.example`.
  ///
  /// Exists so the host's "paste a link" metadata fallback can find the
  /// right plugin without core containing a single line of per-provider URL
  /// knowledge: the plugin names the hosts it understands, once, in its own
  /// manifest, the same way [contentTypes] names what it can be searched
  /// for. Empty is the ordinary answer for a plugin that does not implement
  /// `metadata_search`'s `resolveUrl` at all.
  final Set<String> supportedHosts;

  /// Whether a text query means anything to this source.
  ///
  /// Read off [capabilities] rather than stored, so it cannot contradict them.
  /// A plugin can publish a chart without being searchable, and asking one that
  /// cannot search is a round trip that always returns nothing.
  bool get canSearch => capabilities.contains(SwayveCapability.search);

  /// Whether sending [type] to this source now could produce anything.
  bool answers(SwayveContentType type) =>
      canSearch && availability.canAnswer && contentTypes.contains(type);

  /// Returns a copy with the given fields replaced.
  ///
  /// The shape a running plugin uses to republish itself as its service's
  /// standing changes: `descriptor.copyWith(availability: signedOut)`.
  SwayveSourceDescriptor copyWith({
    String? sourceId,
    String? displayName,
    String? iconName,
    Set<SwayveContentType>? contentTypes,
    Set<SwayveCapability>? capabilities,
    SwayveSourceAvailability? availability,
    Set<String>? supportedHosts,
  }) =>
      SwayveSourceDescriptor(
        sourceId: sourceId ?? this.sourceId,
        displayName: displayName ?? this.displayName,
        iconName: iconName ?? this.iconName,
        contentTypes: contentTypes ?? this.contentTypes,
        capabilities: capabilities ?? this.capabilities,
        availability: availability ?? this.availability,
        supportedHosts: supportedHosts ?? this.supportedHosts,
      );

  /// The wire form. Null fields are omitted.
  ///
  /// Both sets are written in enum declaration order rather than iteration
  /// order, so the same descriptor serializes to the same bytes however it was
  /// built. A host that caches or checksums a descriptor should not see it
  /// change because a plugin happened to add its content types in a different
  /// order this time.
  Map<String, Object?> toJson() => pruneNulls({
        'sourceId': sourceId,
        'displayName': displayName,
        'iconName': iconName,
        'contentTypes': [
          for (final type in SwayveContentType.values)
            if (contentTypes.contains(type)) type.wireName,
        ],
        'capabilities': [
          for (final capability in SwayveCapability.values)
            if (capabilities.contains(capability)) capability.wireName,
        ],
        'availability': availability.wireName,
        'supportedHosts':
            supportedHosts.isEmpty ? null : (supportedHosts.toList()..sort()),
      });

  /// Parses the wire form produced by [toJson], strictly.
  ///
  /// Strict because this reads a running plugin's own output, where a value
  /// this SDK does not recognise is a bug worth surfacing rather than a
  /// difference of vintage. Reading a *manifest* — which may have been written
  /// against any version of the format — is the other job entirely, and
  /// [fromManifest] does it forgivingly.
  static SwayveSourceDescriptor fromJson(Map<String, Object?> json) {
    final reader = JsonReader('SwayveSourceDescriptor', json);
    return SwayveSourceDescriptor(
      sourceId: reader.string('sourceId'),
      displayName: reader.string('displayName'),
      iconName: reader.stringOrNull('iconName'),
      contentTypes: reader.enumSet('contentTypes', SwayveContentType.fromWire),
      capabilities: reader.enumSet('capabilities', SwayveCapability.fromWire),
      availability: reader.has('availability')
          ? reader.enumValue('availability', SwayveSourceAvailability.fromWire)
          : SwayveSourceAvailability.ready,
      supportedHosts: reader.stringList('supportedHosts').toSet(),
    );
  }

  /// Reads a manifest's optional `source` object, or `null` when there is not
  /// a usable one.
  ///
  /// Forgiving by construction, and that is the point of it existing beside
  /// [fromJson]. A manifest is an untrusted document from outside the app that
  /// a host reads before it has decided whether to trust the plugin at all, so
  /// nothing here may throw: a `source` block that is not an object, or that
  /// names no [sourceId], reads as a plugin that declared no source rather than
  /// as a bundle to reject. A plugin is entitled not to be a source.
  ///
  /// Unknown members of `contentTypes` are dropped one at a time rather than
  /// failing the block. A plugin built against a later SDK naming a fifth kind
  /// of content is describing reach this host could not offer anyway, and
  /// throwing the source away over one word would lose the four kinds it does
  /// understand — the same widening rule the manifest format has always
  /// followed.
  ///
  /// [capabilities] is the manifest's own top-level `capabilities` array, in
  /// wire spelling. It is passed in rather than read from the `source` block
  /// because the block deliberately does not repeat it: one list, in the place
  /// it has always been.
  static SwayveSourceDescriptor? fromManifest(
    Object? source, {
    Iterable<String> capabilities = const [],
  }) {
    if (source is! Map) return null;

    String? text(String key) {
      final value = source[key];
      if (value is! String) return null;
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    final id = text('sourceId');
    if (id == null) return null;

    final rawTypes = source['contentTypes'];
    final types = <SwayveContentType>{};
    if (rawTypes is List) {
      for (final raw in rawTypes) {
        final type = raw is String ? SwayveContentType.fromWire(raw) : null;
        if (type != null) types.add(type);
      }
    }
    final declared = <SwayveCapability>{};
    for (final wire in capabilities) {
      final capability = SwayveCapability.fromWire(wire);
      if (capability != null) declared.add(capability);
    }

    final rawHosts = source['supportedHosts'];
    final hosts = <String>{};
    if (rawHosts is List) {
      for (final raw in rawHosts) {
        if (raw is String && raw.trim().isNotEmpty) hosts.add(raw.trim());
      }
    }

    return SwayveSourceDescriptor(
      sourceId: id,
      // A source that named itself but not its display name is named after
      // itself. Falling back beats refusing the block: the id is a poor label
      // and it is a true one, and a source row with no name at all is worse.
      displayName: text('displayName') ?? id,
      iconName: text('iconName'),
      contentTypes: types,
      capabilities: declared,
      supportedHosts: hosts,
      // Absent, unreadable and unknown all read as `ready`, because a manifest
      // states a default rather than an observation — see the class comment.
      // A plugin that starts up unable to answer says so at runtime, which is
      // the only place that answer can be true.
      availability: SwayveSourceAvailability.fromWire(
            source['availability'] is String
                ? source['availability']! as String
                : '',
          ) ??
          SwayveSourceAvailability.ready,
    );
  }

  @override
  String toString() =>
      'SwayveSourceDescriptor($displayName, $sourceId, ${availability.wireName})';

  @override
  bool operator ==(Object other) =>
      other is SwayveSourceDescriptor &&
      sourceId == other.sourceId &&
      displayName == other.displayName &&
      iconName == other.iconName &&
      deepEquals(contentTypes, other.contentTypes) &&
      deepEquals(capabilities, other.capabilities) &&
      availability == other.availability &&
      deepEquals(supportedHosts, other.supportedHosts);

  @override
  int get hashCode => Object.hash(
        sourceId,
        displayName,
        iconName,
        deepHash(contentTypes),
        deepHash(capabilities),
        availability,
        deepHash(supportedHosts),
      );
}
