import 'semver.dart';
import 'vocabulary.dart';

/// One node of the manifest's structure.
///
/// This tree is the Dart half of the contract in
/// `schema/swayve-plugin.schema.json`. The schema is what third parties
/// consume; this is what the validator actually runs. `test/schema_sync_test`
/// walks both and fails if either grows a field the other has not heard of, so
/// the published contract cannot drift away from the enforced one.
sealed class TypeSpec {
  const TypeSpec();

  /// The JSON type name used in diagnostics.
  String get typeName;
}

/// A JSON string, with the usual string constraints.
final class StringSpec extends TypeSpec {
  /// Creates a string spec.
  const StringSpec({
    this.minLength,
    this.maxLength,
    this.pattern,
    this.values,
    this.noEmoji = false,
  });

  /// Minimum length in code units.
  final int? minLength;

  /// Maximum length in code units.
  final int? maxLength;

  /// A regular expression the value must match end to end.
  final RegExp? pattern;

  /// A closed vocabulary. When set, [pattern] is not consulted.
  final List<String>? values;

  /// Whether the value must be free of emoji.
  final bool noEmoji;

  @override
  String get typeName => 'string';
}

/// A JSON integer.
final class IntSpec extends TypeSpec {
  /// Creates an integer spec.
  const IntSpec({this.minimum, this.maximum});

  /// Inclusive lower bound.
  final int? minimum;

  /// Inclusive upper bound.
  final int? maximum;

  @override
  String get typeName => 'integer';
}

/// A JSON boolean.
final class BoolSpec extends TypeSpec {
  /// Creates a boolean spec.
  const BoolSpec();

  @override
  String get typeName => 'boolean';
}

/// A scalar that may be any one of several JSON types.
///
/// Used only by a setting's `default`, which takes whatever shape its `type`
/// calls for. Which shape that is gets checked in the setting rules.
final class ScalarUnionSpec extends TypeSpec {
  /// Creates a union of scalar types.
  const ScalarUnionSpec(this.jsonTypes);

  /// The permitted JSON type names.
  final List<String> jsonTypes;

  @override
  String get typeName => jsonTypes.join(' or ');
}

/// A JSON array.
final class ArraySpec extends TypeSpec {
  /// Creates an array spec.
  const ArraySpec(
    this.items, {
    this.minItems,
    this.maxItems,
    this.uniqueItems = false,
  });

  /// The spec every element must satisfy.
  final TypeSpec items;

  /// Minimum element count.
  final int? minItems;

  /// Maximum element count.
  final int? maxItems;

  /// Whether repeats are rejected.
  final bool uniqueItems;

  @override
  String get typeName => 'array';
}

/// A JSON object with a closed property set.
///
/// Every object in the manifest is closed: `additionalProperties: false` in the
/// schema, an unknown-field error here.
final class ObjectSpec extends TypeSpec {
  /// Creates an object spec.
  const ObjectSpec({
    required this.properties,
    this.required = const <String>{},
  });

  /// Property name to the spec its value must satisfy.
  final Map<String, TypeSpec> properties;

  /// Properties that must be present.
  final Set<String> required;

  @override
  String get typeName => 'object';
}

// --- shared leaf specs, mirroring the schema's $defs -------------------------

/// Strict SemVer 2.0.0.
final StringSpec semverSpec = StringSpec(
  minLength: 5,
  maxLength: 128,
  pattern: SemVer.pattern,
);

/// Reverse-DNS plugin id with three or more segments.
final StringSpec pluginIdSpec = StringSpec(
  minLength: 5,
  maxLength: 128,
  pattern: RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*){2,}$'),
);

/// An http(s) URL.
final StringSpec httpUrlSpec = StringSpec(
  minLength: 8,
  maxLength: 512,
  pattern: RegExp(r'^https?://[^\s]+$'),
);

/// An email address, checked only as far as it is worth checking.
final StringSpec emailSpec = StringSpec(
  minLength: 3,
  maxLength: 254,
  pattern: RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$'),
);

/// A relative path under `assets/` ending in `.png` or `.svg`.
final StringSpec assetPathSpec = StringSpec(
  minLength: 8,
  maxLength: 256,
  pattern: RegExp(r'^assets/(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_-]+\.(?:png|svg)$'),
);

/// A hostname, optionally with one leading `*.` wildcard label.
final StringSpec hostPatternSpec = StringSpec(
  minLength: 4,
  maxLength: 253,
  pattern: RegExp(r'^(\*\.)?[a-z0-9]([a-z0-9-]*[a-z0-9])?'
      r'(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$'),
);

/// A lowercase discovery keyword.
final StringSpec keywordSpec = StringSpec(
  minLength: 2,
  maxLength: 32,
  pattern: RegExp(r'^[a-z0-9][a-z0-9-]*$'),
);

/// An SPDX licence identifier.
final StringSpec licenseSpec = StringSpec(
  minLength: 1,
  maxLength: 64,
  pattern: RegExp(r'^[A-Za-z0-9][A-Za-z0-9.+-]*$'),
);

/// A Dart library / registration symbol, also the plugin's directory name.
final StringSpec entrypointSpec = StringSpec(
  minLength: 1,
  maxLength: 64,
  pattern: RegExp(r'^[a-z][a-z0-9_]*$'),
);

/// A setting identifier.
final StringSpec settingIdSpec = StringSpec(
  minLength: 1,
  maxLength: 48,
  pattern: RegExp(r'^[a-z][a-z0-9_]*$'),
);

/// One entry of the capability vocabulary.
final StringSpec capabilitySpec = const StringSpec(values: kCapabilities);

/// One entry of the permission vocabulary.
final StringSpec permissionSpec = const StringSpec(values: kPermissions);

/// One platform.
final StringSpec platformSpec = const StringSpec(values: kPlatforms);

/// One runtime kind.
final StringSpec runtimeSpec = const StringSpec(values: kRuntimes);

/// One setting type.
final StringSpec settingTypeSpec = const StringSpec(values: kSettingTypes);

/// `author`.
final ObjectSpec authorSpec = ObjectSpec(
  required: const <String>{'name'},
  properties: <String, TypeSpec>{
    'name': const StringSpec(minLength: 1, maxLength: 64),
    'url': httpUrlSpec,
    'email': emailSpec,
  },
);

/// `media`.
final ObjectSpec mediaSpec = const ObjectSpec(
  properties: <String, TypeSpec>{
    'streamable': BoolSpec(),
    'downloadable': BoolSpec(),
    'offlineCache': BoolSpec(),
  },
);

/// `network`.
final ObjectSpec networkSpec = ObjectSpec(
  required: const <String>{'hosts'},
  properties: <String, TypeSpec>{
    'hosts': ArraySpec(
      hostPatternSpec,
      minItems: 0,
      maxItems: 64,
      uniqueItems: true,
    ),
  },
);

/// `timeouts`.
final ObjectSpec timeoutsSpec = const ObjectSpec(
  properties: <String, TypeSpec>{
    'requestMs': IntSpec(minimum: 1000, maximum: 30000),
    'operationMs': IntSpec(minimum: 1000, maximum: 60000),
  },
);

/// One entry of a `select` setting's `options`.
final ObjectSpec settingOptionSpec = const ObjectSpec(
  required: <String>{'value', 'label'},
  properties: <String, TypeSpec>{
    'value': StringSpec(minLength: 1, maxLength: 64),
    'label': StringSpec(minLength: 1, maxLength: 48),
  },
);

/// One setting descriptor.
final ObjectSpec settingDescriptorSpec = ObjectSpec(
  required: const <String>{'id', 'type', 'label'},
  properties: <String, TypeSpec>{
    'id': settingIdSpec,
    'type': settingTypeSpec,
    'label': const StringSpec(minLength: 1, maxLength: 48),
    'description': const StringSpec(minLength: 1, maxLength: 160),
    'default': const ScalarUnionSpec(<String>['string', 'boolean', 'integer']),
    'required': const BoolSpec(),
    'options': ArraySpec(
      settingOptionSpec,
      minItems: 1,
      maxItems: 64,
      uniqueItems: true,
    ),
    'min': const IntSpec(),
    'max': const IntSpec(),
  },
);

/// The whole manifest.
final ObjectSpec manifestSpec = ObjectSpec(
  required: const <String>{
    'schemaVersion',
    'id',
    'name',
    'description',
    'version',
    'author',
    'license',
    'swayvePluginApi',
    'minimumSwayveVersion',
    'runtime',
    'platforms',
    'capabilities',
    'permissions',
    'entrypoint',
  },
  properties: <String, TypeSpec>{
    'schemaVersion': const IntSpec(minimum: 1),
    'id': pluginIdSpec,
    'name': const StringSpec(minLength: 1, maxLength: 64, noEmoji: true),
    'description': const StringSpec(minLength: 1, maxLength: 280),
    'version': semverSpec,
    'author': authorSpec,
    'license': licenseSpec,
    'swayvePluginApi': const IntSpec(minimum: 1),
    'minimumSwayveVersion': semverSpec,
    'runtime': runtimeSpec,
    'platforms': ArraySpec(platformSpec, minItems: 1, uniqueItems: true),
    'capabilities': ArraySpec(capabilitySpec, minItems: 1, uniqueItems: true),
    'permissions': ArraySpec(permissionSpec, minItems: 0, uniqueItems: true),
    'entrypoint': entrypointSpec,
    'homepage': httpUrlSpec,
    'repository': httpUrlSpec,
    'icon': assetPathSpec,
    'media': mediaSpec,
    'settings': ArraySpec(settingDescriptorSpec, minItems: 0, maxItems: 32),
    'network': networkSpec,
    'timeouts': timeoutsSpec,
    'keywords': ArraySpec(
      keywordSpec,
      minItems: 0,
      maxItems: 10,
      uniqueItems: true,
    ),
  },
);
