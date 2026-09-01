import 'package:swayve_plugin_registry/swayve_plugin_registry.dart';
import 'package:swayve_plugin_sdk/swayve_plugin_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('lists youtube_music under its manifest id', () {
    expect(
      firstPartyCompiledPlugins.keys,
      contains('app.swayve.plugins.youtube_music'),
    );
  });

  test('lists soundcloud under its manifest id', () {
    expect(
      firstPartyCompiledPlugins.keys,
      contains('app.swayve.plugins.soundcloud'),
    );
  });

  test('lists ibroadcast under its manifest id', () {
    expect(
      firstPartyCompiledPlugins.keys,
      contains('dev.dazacode.swayve.ibroadcast'),
    );
  });

  test('every factory builds a plugin whose identity id matches its key', () {
    for (final entry in firstPartyCompiledPlugins.entries) {
      final SwayvePlugin plugin = entry.value();
      expect(plugin.identity.id, entry.key);
    }
  });

  test('every factory is cheap and side-effect free to call', () {
    // A registry entry must be safe to instantiate speculatively (e.g. to
    // read `identity` before a bundle is actually imported) without that
    // call reaching the network, touching disk, or throwing.
    for (final factory in firstPartyCompiledPlugins.values) {
      expect(factory, returnsNormally);
    }
  });

  group('compiled manifests', () {
    test('every manifest belongs to a plugin this registry can activate', () {
      // A manifest for an id with no factory would be a manifest the host
      // could refresh a row to and then have nothing to run.
      for (final id in firstPartyCompiledManifests.keys) {
        expect(
          firstPartyCompiledPlugins,
          contains(id),
          reason: '$id has a compiled manifest but no compiled factory',
        );
      }
    });

    test('each manifest declares the id it is filed under', () {
      firstPartyCompiledManifests.forEach((id, manifest) {
        expect(manifest()['id'], id);
      });
    });

    test('each manifest matches its running plugin identity', () {
      // The check that makes a host's refresh safe: the manifest it would
      // store has to describe the code it is about to run.
      firstPartyCompiledManifests.forEach((id, manifest) {
        final identity = firstPartyCompiledPlugins[id]!().identity;
        final declared = manifest();
        expect(declared['name'], identity.name);
        expect(declared['version'], identity.version.toString());
        expect(
          (declared['capabilities']! as List<Object?>).toSet(),
          identity.capabilities.map((c) => c.wireName).toSet(),
        );
      });
    });

    test('a plugin with no compiled manifest is absent, not empty', () {
      // Absent means "nothing fresher to offer, leave the stored row alone".
      // An empty map would mean "this plugin declares nothing", which would
      // wipe a perfectly good stored manifest.
      for (final manifest in firstPartyCompiledManifests.values) {
        expect(manifest(), isNotEmpty);
      }
    });
  });
}
