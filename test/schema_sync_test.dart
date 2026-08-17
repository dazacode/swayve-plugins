import 'dart:convert';
import 'dart:io';

import 'package:swayve_plugin_tools/swayve_plugin_tools.dart';
import 'package:test/test.dart';

/// Walks `schema/swayve-plugin.schema.json` and the Dart [manifestSpec] side by
/// side.
///
/// The schema is what third parties consume; the Dart spec is what the
/// validator runs. Nothing stops the two drifting apart except this test, so it
/// compares every field name, every constraint and every closed vocabulary,
/// recursively, in both directions.
void main() {
  late Map<String, Object?> schema;
  late Map<String, Object?> defs;

  setUpAll(() {
    final String text =
        File('schema/swayve-plugin.schema.json').readAsStringSync();
    schema = jsonDecode(text)! as Map<String, Object?>;
    defs = schema[r'$defs']! as Map<String, Object?>;
  });

  Map<String, Object?> resolve(Map<String, Object?> node) {
    var current = node;
    while (current.containsKey(r'$ref')) {
      final String ref = current[r'$ref']! as String;
      const String prefix = r'#/$defs/';
      expect(
        ref,
        startsWith(prefix),
        reason: r'only local $defs refs are used',
      );
      current = defs[ref.substring(prefix.length)]! as Map<String, Object?>;
    }
    return current;
  }

  void compare(TypeSpec spec, Map<String, Object?> rawNode, String path) {
    final Map<String, Object?> node = resolve(rawNode);
    switch (spec) {
      case ObjectSpec():
        expect(node['type'], 'object', reason: '$path type');
        expect(
          node['additionalProperties'],
          isFalse,
          reason: '$path must close its property set',
        );
        final Map<String, Object?> properties =
            node['properties']! as Map<String, Object?>;
        expect(
          properties.keys.toSet(),
          spec.properties.keys.toSet(),
          reason: '$path properties differ between schema and Dart model',
        );
        expect(
          ((node['required'] as List<Object?>?) ?? const <Object?>[])
              .cast<String>()
              .toSet(),
          spec.required,
          reason: '$path required set differs',
        );
        for (final MapEntry<String, TypeSpec> entry
            in spec.properties.entries) {
          compare(
            entry.value,
            properties[entry.key]! as Map<String, Object?>,
            '$path/${entry.key}',
          );
        }
      case ArraySpec():
        expect(node['type'], 'array', reason: '$path type');
        expect(node['minItems'], spec.minItems, reason: '$path minItems');
        expect(node['maxItems'], spec.maxItems, reason: '$path maxItems');
        expect(
          node['uniqueItems'] ?? false,
          spec.uniqueItems,
          reason: '$path uniqueItems',
        );
        compare(spec.items, node['items']! as Map<String, Object?>, '$path[]');
      case StringSpec():
        expect(node['type'], 'string', reason: '$path type');
        final List<String>? values = spec.values;
        if (values != null) {
          expect(
            (node['enum']! as List<Object?>).cast<String>(),
            values,
            reason: '$path enum',
          );
        } else {
          expect(node['enum'], isNull, reason: '$path should not be an enum');
          expect(
            node['pattern'],
            spec.pattern?.pattern,
            reason: '$path pattern',
          );
        }
        expect(node['minLength'], spec.minLength, reason: '$path minLength');
        expect(node['maxLength'], spec.maxLength, reason: '$path maxLength');
      case IntSpec():
        expect(node['type'], 'integer', reason: '$path type');
        expect(node['minimum'], spec.minimum, reason: '$path minimum');
        expect(node['maximum'], spec.maximum, reason: '$path maximum');
      case BoolSpec():
        expect(node['type'], 'boolean', reason: '$path type');
      case ScalarUnionSpec():
        expect(
          (node['type']! as List<Object?>).cast<String>(),
          spec.jsonTypes,
          reason: '$path type union',
        );
    }
  }

  test('the schema and the Dart model describe the same manifest', () {
    compare(manifestSpec, schema, '#');
  });

  test('the schema declares the draft and id the contract fixes', () {
    expect(schema[r'$schema'], 'https://json-schema.org/draft/2020-12/schema');
    expect(
      schema[r'$id'],
      'https://swayve.app/schema/swayve-plugin.schema.json',
    );
  });

  test('every closed vocabulary matches the one the tools enforce', () {
    Map<String, Object?> def(String name) =>
        defs[name]! as Map<String, Object?>;
    List<String> enumOf(String name) =>
        (def(name)['enum']! as List<Object?>).cast<String>();
    expect(enumOf('capability'), kCapabilities);
    expect(enumOf('permission'), kPermissions);
    expect(enumOf('platform'), kPlatforms);
    expect(enumOf('runtime'), kRuntimes);
    expect(enumOf('settingType'), kSettingTypes);
  });

  test('every capability the schema allows is accounted for by a rule', () {
    for (final String capability in kCapabilities) {
      expect(
        kCapabilityRequiredPermission.containsKey(capability) ||
            kNetworkExpectingCapabilities.contains(capability),
        isTrue,
        reason: '$capability is in neither the required-permission table nor '
            'the network-expecting set, so no rule would ever mention it',
      );
    }
    expect(
      kCapabilityRequiredPermission.keys
          .toSet()
          .intersection(kNetworkExpectingCapabilities),
      isEmpty,
      reason: 'a capability belongs to one table or the other, never both',
    );
    for (final String permission in <String>[
      ...kCapabilityRequiredPermission.values,
      'network',
    ]) {
      expect(
        kPermissions,
        contains(permission),
        reason: '$permission is referenced but is not in the vocabulary',
      );
    }
  });

  test('only webview and authentication are structural implications', () {
    expect(kCapabilityRequiredPermission, <String, String>{
      'webview': 'webview',
      'authentication': 'external_auth',
    });
    expect(kNetworkExpectingCapabilities, hasLength(9));
  });

  test(r'every $defs entry is reachable from the manifest', () {
    final Set<String> referenced = <String>{};
    void walk(Object? node) {
      if (node is Map<String, Object?>) {
        final Object? ref = node[r'$ref'];
        if (ref is String && ref.startsWith(r'#/$defs/')) {
          final String name = ref.substring(r'#/$defs/'.length);
          if (referenced.add(name)) {
            walk(defs[name]);
          }
        }
        for (final Object? value in node.values) {
          walk(value);
        }
      } else if (node is List<Object?>) {
        node.forEach(walk);
      }
    }

    walk(schema['properties']);
    expect(
      defs.keys.toSet().difference(referenced),
      isEmpty,
      reason: r'unreachable $defs entries are dead contract',
    );
  });

  test('the schema accepts the fixture manifest it is meant to describe', () {
    final String text = File('test/fixtures/plugins/demo_source/plugin.json')
        .readAsStringSync();
    final Report report = validateManifestText(
      text,
      target: 'fixture',
      directoryName: 'demo_source',
    ).report;
    expect(report.diagnostics, isEmpty);
  });
}
