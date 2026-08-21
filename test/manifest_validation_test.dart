import 'package:swayve_plugin_tools/swayve_plugin_tools.dart';
import 'package:test/test.dart';

import 'support/manifests.dart';

void main() {
  group('a valid manifest', () {
    test('passes with nothing to report', () {
      final Report report = validate(cleanManifest());
      expect(report.diagnostics, isEmpty, reason: codesOf(report).toString());
      expect(report.passed(strict: true), isTrue);
    });

    test('passes when read off disk, with its directory name checked', () {
      final ManifestValidation result =
          validatePluginDirectory('test/fixtures/plugins/demo_source');
      expect(
        result.report.diagnostics,
        isEmpty,
        reason: codesOf(result.report).toString(),
      );
      expect(result.manifest.entrypoint, 'demo_source');
    });
  });

  group('cross-field rule', () {
    test('1a: webview and authentication require their own permissions', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['capabilities'] = <String>['webview', 'authentication']
        ..['permissions'] = <String>[];
      final List<Diagnostic> hits = validate(manifest)
          .diagnostics
          .where(
            (Diagnostic d) =>
                d.code == DiagnosticCodes.capabilityRequiresPermission,
          )
          .toList();
      expect(hits, hasLength(2));
      expect(hits[0].severity, Severity.error);
      expect(
        hits[0].message,
        contains("'webview' requires permission 'webview'"),
      );
      expect(hits[0].pointer, '/capabilities/0');
      expect(hits[1].severity, Severity.error);
      expect(
        hits[1].message,
        contains("'authentication' requires permission 'external_auth'"),
      );
      expect(hits[1].pointer, '/capabilities/1');
    });

    test('1a: those two are the only structural implications', () {
      // Anything a data capability needs is advisory, so nothing but webview
      // and authentication may ever produce this error code.
      final Map<String, Object?> manifest = cleanManifest()
        ..['capabilities'] = <String>[
          'search',
          'catalog',
          'streaming',
          'metadata',
          'lyrics',
          'scrobbling',
          'artwork',
          'playlist_read',
        ]
        ..['permissions'] = <String>[];
      expect(
        codesOf(validate(manifest)),
        isNot(contains(DiagnosticCodes.capabilityRequiresPermission)),
      );
    });

    test('1b: a data capability without network is an info note only', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['capabilities'] = <String>['search', 'streaming']
        ..['permissions'] = <String>[]
        ..remove('network');
      final Report report = validate(manifest);

      final List<Diagnostic> hits = report.diagnostics
          .where(
            (Diagnostic d) =>
                d.code == DiagnosticCodes.capabilityExpectsNetwork,
          )
          .toList();
      expect(hits, hasLength(2));
      expect(hits[0].severity, Severity.info);
      expect(
        hits[0].message,
        "capabilities: 'search' usually reaches an external service; declare "
        "the 'network' permission unless this plugin serves purely local data",
      );
      expect(hits[0].pointer, '/capabilities/0');
      expect(hits[1].pointer, '/capabilities/1');

      expect(report.errorCount, 0);
      expect(report.warningCount, 0);
      expect(report.problemCount, 0, reason: 'an info is not a problem');
    });

    test('1b: --strict does not promote the note to a failure', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['capabilities'] = <String>['search', 'catalog']
        ..['permissions'] = <String>[]
        ..remove('network');
      final Report report = validate(manifest);
      expect(
        codesOf(report),
        everyElement(DiagnosticCodes.capabilityExpectsNetwork),
      );
      expect(
        report.passed(strict: true),
        isTrue,
        reason: 'an offline plugin must not fail CI for being honest',
      );
    });

    test('1b: the note is silent once network is declared', () {
      expect(
        codesOf(validate(cleanManifest())),
        isNot(contains(DiagnosticCodes.capabilityExpectsNetwork)),
      );
    });

    test('1b: a capability outside the data set never raises it', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['capabilities'] = <String>['webview']
        ..['permissions'] = <String>['webview']
        ..remove('network');
      expect(
        codesOf(validate(manifest)),
        isNot(contains(DiagnosticCodes.capabilityExpectsNetwork)),
      );
    });

    test('1b: a fully offline plugin on disk has nothing above INFO', () {
      final Report report = validatePluginDirectory(
        'test/fixtures/plugins/offline_catalogue',
      ).report;
      expect(report.errorCount, 0, reason: codesOf(report).toString());
      expect(report.warningCount, 0, reason: codesOf(report).toString());
      expect(
        report.diagnostics.map((Diagnostic d) => d.severity).toSet(),
        <Severity>{Severity.info},
      );
      expect(
        codesOf(report),
        <String>[
          DiagnosticCodes.capabilityExpectsNetwork,
          DiagnosticCodes.capabilityExpectsNetwork,
        ],
      );
      expect(report.passed(strict: true), isTrue);
    });

    test('2: a permission nothing implies is a warning', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['permissions'] = <String>['network', 'webview'];
      final Diagnostic d = diagnosticFor(
        validate(manifest),
        DiagnosticCodes.permissionNotImplied,
      );
      expect(d.severity, Severity.warning);
      expect(d.pointer, '/permissions/1');
    });

    test('2: local_plugin_storage and clipboard justify themselves', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['permissions'] = <String>[
          'network',
          'local_plugin_storage',
          'clipboard',
        ];
      expect(
        codesOf(validate(manifest)),
        isNot(contains(DiagnosticCodes.permissionNotImplied)),
      );
    });

    test('3: downloadable media without the streaming capability', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['media'] = <String, Object?>{'downloadable': true};
      final Diagnostic d = diagnosticFor(
        validate(manifest),
        DiagnosticCodes.downloadableRequiresStreaming,
      );
      expect(d.severity, Severity.error);
      expect(d.pointer, '/media/downloadable');
    });

    test('3: downloadable is fine once streaming is declared', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['capabilities'] = <String>['search', 'streaming']
        ..['media'] = <String, Object?>{'downloadable': true};
      expect(
        codesOf(validate(manifest)),
        isNot(contains(DiagnosticCodes.downloadableRequiresStreaming)),
      );
    });

    test('4: runtime bundled cannot list ios', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['runtime'] = 'bundled'
        ..['platforms'] = <String>['android', 'ios'];
      final Diagnostic d = diagnosticFor(
        validate(manifest),
        DiagnosticCodes.bundledRuntimeNotAllowedOnIos,
      );
      expect(d.severity, Severity.error);
      expect(d.pointer, '/platforms/1');
    });

    test('4: runtime bundled is fine everywhere else', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['runtime'] = 'bundled'
        ..['platforms'] = <String>['android', 'windows', 'macos', 'linux'];
      expect(
        codesOf(validate(manifest)),
        isNot(contains(DiagnosticCodes.bundledRuntimeNotAllowedOnIos)),
      );
    });

    test('4: compiled on ios is allowed', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['platforms'] = <String>['ios'];
      expect(
        codesOf(validate(manifest)),
        isNot(contains(DiagnosticCodes.bundledRuntimeNotAllowedOnIos)),
      );
    });

    test('5: the network permission with no hosts is a warning', () {
      final Map<String, Object?> manifest = cleanManifest()..remove('network');
      final Diagnostic d = diagnosticFor(
        validate(manifest),
        DiagnosticCodes.networkPermissionWithoutHosts,
      );
      expect(d.severity, Severity.warning);
      expect(d.message, contains('no network.hosts listed'));
    });

    test('5: an empty hosts list counts as none', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['network'] = <String, Object?>{'hosts': <String>[]};
      final Diagnostic d = diagnosticFor(
        validate(manifest),
        DiagnosticCodes.networkPermissionWithoutHosts,
      );
      expect(d.pointer, '/network/hosts');
    });

    test("6: entrypoint that is not the id's last segment is a warning", () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['entrypoint'] = 'something_else';
      final Diagnostic d = diagnosticFor(
        validate(manifest),
        DiagnosticCodes.entrypointIdMismatch,
      );
      expect(d.severity, Severity.warning);
      expect(d.pointer, '/entrypoint');
    });

    test('7: a directory name that is not the entrypoint is an error', () {
      final Diagnostic d = diagnosticFor(
        validate(cleanManifest(), directoryName: 'not_demo_source'),
        DiagnosticCodes.directoryNameMismatch,
      );
      expect(d.severity, Severity.error);
      expect(d.message, contains('not_demo_source'));
    });

    test('7: fires against a real misnamed plugin directory', () {
      final Report report = validatePluginDirectory(
        'test/fixtures/plugins/misnamed_directory',
      ).report;
      expect(codesOf(report), contains(DiagnosticCodes.directoryNameMismatch));
    });

    test('8: the first-party namespace requires the Swayve author', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['id'] = 'app.swayve.plugins.demo_source'
        ..['author'] = <String, Object?>{'name': 'Someone Else'};
      final Diagnostic d = diagnosticFor(
        validate(manifest),
        DiagnosticCodes.firstPartyAuthorMismatch,
      );
      expect(d.severity, Severity.error);
      expect(d.pointer, '/author/name');
    });

    test('8: a first-party plugin authored by Swayve is fine', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['id'] = 'app.swayve.plugins.demo_source'
        ..['author'] = <String, Object?>{'name': 'Swayve'};
      expect(
        codesOf(validate(manifest)),
        isNot(contains(DiagnosticCodes.firstPartyAuthorMismatch)),
      );
    });

    test('9: a 0.x version is an info note, not a problem', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['version'] = '0.1.0';
      final Report report = validate(manifest);
      final Diagnostic d =
          diagnosticFor(report, DiagnosticCodes.prereleaseApiUnstable);
      expect(d.severity, Severity.info);
      expect(d.message, contains('pre-1.0'));
      expect(report.problemCount, 0);
      expect(report.passed(strict: true), isTrue);
    });

    test('9: a version that is not strict SemVer fails the pattern', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['version'] = '1.0.0.0';
      expect(
        codesOf(validate(manifest)),
        contains(DiagnosticCodes.fieldPattern),
      );
    });

    test('10: a path-valued field must be relative and must stay put', () {
      for (final String bad in <String>[
        '/etc/passwd',
        '../outside/icon.png',
        r'assets\icon.png',
        'C:/windows/icon.png',
      ]) {
        final Map<String, Object?> manifest = cleanManifest()..['icon'] = bad;
        expect(
          codesOf(validate(manifest)),
          contains(DiagnosticCodes.unsafeRelativePath),
          reason: 'expected $bad to be rejected',
        );
      }
    });

    test('10: a legitimate icon path is accepted', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['icon'] = 'assets/icon.svg';
      expect(
        codesOf(validate(manifest)),
        isNot(contains(DiagnosticCodes.unsafeRelativePath)),
      );
    });
  });

  group('compatibility', () {
    test('swayvePluginApi 2 is rejected as needing a newer Swayve', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['swayvePluginApi'] = 2;
      final Diagnostic d = diagnosticFor(
        validate(manifest),
        DiagnosticCodes.unsupportedPluginApi,
      );
      expect(d.severity, Severity.error);
      expect(d.message, contains('requires a newer version of Swayve'));
      expect(d.pointer, '/swayvePluginApi');
    });

    test('a future schemaVersion is rejected the same way', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['schemaVersion'] = 5;
      final Diagnostic d = diagnosticFor(
        validate(manifest),
        DiagnosticCodes.unsupportedSchemaVersion,
      );
      expect(d.message, contains('requires a newer version of Swayve'));
    });

    test('schemaVersion 1 with no artist_activity capability still validates',
        () {
      // cleanManifest() is already schemaVersion: 1 with capabilities:
      // ['search']. The artist_activity capability widened the vocabulary in
      // schemaVersion 2, but a plugin written before that addition must keep
      // validating exactly as it did in v1.
      final Report report = validate(cleanManifest());
      expect(report.diagnostics, isEmpty, reason: codesOf(report).toString());
    });

    test('schemaVersion 2 with the artist_activity capability validates', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['schemaVersion'] = 2
        ..['capabilities'] = <String>['search', 'artist_activity'];
      final Report report = validate(manifest);
      expect(report.diagnostics, isEmpty, reason: codesOf(report).toString());
    });

    test(
        'schemaVersion 3 with the personal_library capability validates', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['schemaVersion'] = 3
        ..['capabilities'] = <String>[
          'search',
          'authentication',
          'personal_library',
        ]
        ..['permissions'] = <String>['network', 'external_auth'];
      final Report report = validate(manifest);
      expect(report.diagnostics, isEmpty, reason: codesOf(report).toString());
    });

    test('schemaVersion 4 with the session_capture capability validates', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['schemaVersion'] = 4
        ..['capabilities'] = <String>['search', 'session_capture']
        ..['permissions'] = <String>['network', 'webview', 'external_auth']
        ..['settings'] = <Object?>[
          <String, Object?>{
            'id': 'session_cookie',
            'type': 'secret',
            'label': 'Session cookie',
          },
        ]
        ..['session_capture'] = <String, Object?>{
          'hosts': <String>['music.example.test'],
          'capture': <Object?>[
            <String, Object?>{
              'from': 'cookie_header',
              'as_secret': 'session_cookie',
            },
          ],
        };
      final Report report = validate(manifest);
      expect(report.diagnostics, isEmpty, reason: codesOf(report).toString());
    });
  });

  group('cross-field rule 1c', () {
    test('personal_library requires authentication', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['capabilities'] = <String>['search', 'personal_library'];
      final Diagnostic d = diagnosticFor(
        validate(manifest),
        DiagnosticCodes.capabilityRequiresCapability,
      );
      expect(d.severity, Severity.error);
      expect(
        d.message,
        contains("'personal_library' requires capability 'authentication'"),
      );
      expect(d.pointer, '/capabilities/1');
    });

    test('personal_library alongside authentication is clean', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['capabilities'] = <String>[
          'search',
          'authentication',
          'personal_library',
        ]
        ..['permissions'] = <String>['network', 'external_auth'];
      expect(
        codesOf(validate(manifest)),
        isNot(contains(DiagnosticCodes.capabilityRequiresCapability)),
      );
    });

    test('every other capability is unaffected by rule 1c', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['capabilities'] = <String>[
          'search',
          'catalog',
          'streaming',
          'metadata',
          'lyrics',
          'scrobbling',
          'artwork',
          'playlist_read',
          'artist_activity',
        ]
        ..['permissions'] = <String>['network'];
      expect(
        codesOf(validate(manifest)),
        isNot(contains(DiagnosticCodes.capabilityRequiresCapability)),
      );
    });
  });

  group('cross-field rule 1a (session_capture)', () {
    test(
        'session_capture requires both webview and external_auth, one '
        'diagnostic per missing permission', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['capabilities'] = <String>['session_capture']
        ..['permissions'] = <String>[]
        ..['settings'] = <Object?>[
          <String, Object?>{
            'id': 'session_cookie',
            'type': 'secret',
            'label': 'Session cookie',
          },
        ]
        ..['session_capture'] = <String, Object?>{
          'hosts': <String>['music.example.test'],
          'capture': <Object?>[
            <String, Object?>{
              'from': 'cookie_header',
              'as_secret': 'session_cookie',
            },
          ],
        };
      final List<Diagnostic> hits = validate(manifest)
          .diagnostics
          .where(
            (Diagnostic d) =>
                d.code == DiagnosticCodes.capabilityRequiresPermission,
          )
          .toList();
      expect(hits, hasLength(2));
      expect(hits[0].severity, Severity.error);
      expect(
        hits[0].message,
        contains("'session_capture' requires permission 'webview'"),
      );
      expect(hits[0].pointer, '/capabilities/0');
      expect(hits[1].severity, Severity.error);
      expect(
        hits[1].message,
        contains("'session_capture' requires permission 'external_auth'"),
      );
      expect(hits[1].pointer, '/capabilities/0');
    });
  });

  group('cross-field rule 12', () {
    Map<String, Object?> withSessionCapture(Map<String, Object?> block) =>
        cleanManifest()
          ..['capabilities'] = <String>['search', 'session_capture']
          ..['permissions'] = <String>['network', 'webview', 'external_auth']
          ..['settings'] = <Object?>[
            <String, Object?>{
              'id': 'session_cookie',
              'type': 'secret',
              'label': 'Session cookie',
            },
          ]
          ..['session_capture'] = block;

    test('a fully declared session_capture block passes with nothing to '
        'report', () {
      final Report report = validate(
        withSessionCapture(<String, Object?>{
          'hosts': <String>['music.example.test'],
          'capture': <Object?>[
            <String, Object?>{
              'from': 'cookie_header',
              'as_secret': 'session_cookie',
            },
          ],
        }),
      );
      expect(report.diagnostics, isEmpty, reason: codesOf(report).toString());
    });

    test('the capability declared without the object is an error', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['capabilities'] = <String>['search', 'session_capture']
        ..['permissions'] = <String>['network', 'webview', 'external_auth'];
      final Diagnostic d = diagnosticFor(
        validate(manifest),
        DiagnosticCodes.sessionCaptureObjectMissing,
      );
      expect(d.severity, Severity.error);
      expect(d.pointer, '/capabilities/1');
    });

    test('the object without the capability is an info note', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['permissions'] = <String>['network', 'external_auth']
        ..['settings'] = <Object?>[
          <String, Object?>{
            'id': 'session_cookie',
            'type': 'secret',
            'label': 'Session cookie',
          },
        ]
        ..['session_capture'] = <String, Object?>{
          'hosts': <String>['music.example.test'],
          'capture': <Object?>[
            <String, Object?>{
              'from': 'cookie_header',
              'as_secret': 'session_cookie',
            },
          ],
        };
      final Report report = validate(manifest);
      final Diagnostic d = diagnosticFor(
        report,
        DiagnosticCodes.sessionCaptureObjectWithoutCapability,
      );
      expect(d.severity, Severity.info);
      expect(d.pointer, '/session_capture');
      // Info, so --strict must not promote it.
      expect(report.passed(strict: true), isTrue);
    });

    test('hosts empty is an error', () {
      final Diagnostic d = diagnosticFor(
        validate(
          withSessionCapture(<String, Object?>{
            'hosts': <String>[],
            'capture': <Object?>[
              <String, Object?>{
                'from': 'cookie_header',
                'as_secret': 'session_cookie',
              },
            ],
          }),
        ),
        DiagnosticCodes.sessionCaptureHostsEmpty,
      );
      expect(d.severity, Severity.error);
      expect(d.pointer, '/session_capture/hosts');
    });

    test('an unknown capture[].from is an error', () {
      final Diagnostic d = diagnosticFor(
        validate(
          withSessionCapture(<String, Object?>{
            'hosts': <String>['music.example.test'],
            'capture': <Object?>[
              <String, Object?>{
                'from': 'response_header:x-goog-pageid',
                'as_secret': 'session_cookie',
              },
            ],
          }),
        ),
        DiagnosticCodes.sessionCaptureUnknownSource,
      );
      expect(d.severity, Severity.error);
      expect(d.pointer, '/session_capture/capture/0/from');
    });

    test('an as_secret not matching a declared secret setting is an error',
        () {
      final Diagnostic d = diagnosticFor(
        validate(
          withSessionCapture(<String, Object?>{
            'hosts': <String>['music.example.test'],
            'capture': <Object?>[
              <String, Object?>{
                'from': 'cookie_header',
                'as_secret': 'not_declared',
              },
            ],
          }),
        ),
        DiagnosticCodes.sessionCaptureSecretNotDeclared,
      );
      expect(d.severity, Severity.error);
      expect(d.pointer, '/session_capture/capture/0/as_secret');
    });
  });

  group('setting descriptors', () {
    Map<String, Object?> withSettings(List<Object?> settings) =>
        cleanManifest()..['settings'] = settings;

    test('a select must declare options', () {
      final Report report = validate(
        withSettings(<Object?>[
          <String, Object?>{
            'id': 'region',
            'type': 'select',
            'label': 'Region',
          },
        ]),
      );
      expect(codesOf(report), contains(DiagnosticCodes.settingOptionsRequired));
    });

    test('a non-select must not declare options', () {
      final Report report = validate(
        withSettings(<Object?>[
          <String, Object?>{
            'id': 'region',
            'type': 'string',
            'label': 'Region',
            'options': <Object?>[
              <String, Object?>{'value': 'US', 'label': 'United States'},
            ],
          },
        ]),
      );
      expect(
        codesOf(report),
        contains(DiagnosticCodes.settingOptionsNotAllowed),
      );
    });

    test('a default must match the declared type', () {
      final Report report = validate(
        withSettings(<Object?>[
          <String, Object?>{
            'id': 'limit',
            'type': 'int',
            'label': 'Limit',
            'default': 'ten',
          },
        ]),
      );
      expect(
        codesOf(report),
        contains(DiagnosticCodes.settingDefaultTypeMismatch),
      );
    });

    test('a select default must be one of its options', () {
      final Report report = validate(
        withSettings(<Object?>[
          <String, Object?>{
            'id': 'region',
            'type': 'select',
            'label': 'Region',
            'default': 'FR',
            'options': <Object?>[
              <String, Object?>{'value': 'US', 'label': 'United States'},
            ],
          },
        ]),
      );
      expect(
        codesOf(report),
        contains(DiagnosticCodes.settingDefaultNotAnOption),
      );
    });

    test('duplicate setting ids are rejected', () {
      final Report report = validate(
        withSettings(<Object?>[
          <String, Object?>{'id': 'a', 'type': 'string', 'label': 'A'},
          <String, Object?>{'id': 'a', 'type': 'string', 'label': 'B'},
        ]),
      );
      expect(codesOf(report), contains(DiagnosticCodes.settingDuplicateId));
    });

    test('a range outside an int setting is rejected', () {
      final Report report = validate(
        withSettings(<Object?>[
          <String, Object?>{
            'id': 'a',
            'type': 'string',
            'label': 'A',
            'min': 1,
            'max': 2,
          },
        ]),
      );
      expect(codesOf(report), contains(DiagnosticCodes.settingRangeNotAllowed));
    });

    test('an inverted range and an out-of-range default are rejected', () {
      final Report report = validate(
        withSettings(<Object?>[
          <String, Object?>{
            'id': 'a',
            'type': 'int',
            'label': 'A',
            'min': 10,
            'max': 1,
            'default': 50,
          },
        ]),
      );
      expect(codesOf(report), contains(DiagnosticCodes.settingRangeInverted));
      expect(
        codesOf(report),
        contains(DiagnosticCodes.settingDefaultOutOfRange),
      );
    });

    test('a secret setting requires external_auth', () {
      final Report report = validate(
        withSettings(<Object?>[
          <String, Object?>{'id': 'token', 'type': 'secret', 'label': 'Token'},
        ]),
      );
      expect(
        codesOf(report),
        contains(DiagnosticCodes.secretSettingRequiresExternalAuth),
      );
    });

    test('external_auth held for a secret is not over-permissioning', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['permissions'] = <String>['network', 'external_auth']
        ..['settings'] = <Object?>[
          <String, Object?>{'id': 'token', 'type': 'secret', 'label': 'Token'},
        ];
      final Report report = validate(manifest);
      expect(report.diagnostics, isEmpty, reason: codesOf(report).toString());
    });
  });

  group('structural checks', () {
    test('a missing required field is named, not guessed at', () {
      final Map<String, Object?> manifest = cleanManifest()..remove('license');
      final Diagnostic d =
          diagnosticFor(validate(manifest), DiagnosticCodes.fieldRequired);
      expect(d.pointer, '/license');
      expect(d.message, contains('required field is missing'));
    });

    test('an unknown field is rejected: the schema is closed', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['pluginKind'] = 'source';
      final Diagnostic d =
          diagnosticFor(validate(manifest), DiagnosticCodes.fieldUnknown);
      expect(d.pointer, '/pluginKind');
    });

    test('an unknown nested field is rejected too', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['author'] = <String, Object?>{'name': 'Example Co', 'twitter': '@x'};
      expect(
        diagnosticFor(validate(manifest), DiagnosticCodes.fieldUnknown).pointer,
        '/author/twitter',
      );
    });

    test('a value outside a closed vocabulary is rejected', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['capabilities'] = <String>['telepathy'];
      final Diagnostic d =
          diagnosticFor(validate(manifest), DiagnosticCodes.fieldEnum);
      expect(d.pointer, '/capabilities/0');
      expect(d.message, contains("'telepathy' is not one of"));
    });

    test('a duplicate array entry is rejected', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['platforms'] = <String>['android', 'android'];
      expect(
        diagnosticFor(validate(manifest), DiagnosticCodes.fieldDuplicate)
            .pointer,
        '/platforms/1',
      );
    });

    test('an empty required array is rejected', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['capabilities'] = <String>[];
      expect(
        codesOf(validate(manifest)),
        contains(DiagnosticCodes.fieldLength),
      );
    });

    test('a number outside its range is rejected', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['timeouts'] = <String, Object?>{'requestMs': 999};
      expect(
        diagnosticFor(validate(manifest), DiagnosticCodes.fieldRange).pointer,
        '/timeouts/requestMs',
      );
    });

    test('emoji in the plugin name are rejected', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['name'] = 'Demo Source \u{1f3b5}';
      expect(codesOf(validate(manifest)), contains(DiagnosticCodes.fieldEmoji));
    });
  });

  group('malformed input', () {
    test('broken JSON reports where it broke instead of crashing', () {
      final ManifestValidation result = validateManifestText(
        '{\n  "schemaVersion": 1,\n  "id": \n}',
        target: 'fixture',
      );
      final Diagnostic d = diagnosticFor(
        result.report,
        DiagnosticCodes.manifestMalformedJson,
      );
      expect(d.severity, Severity.error);
      expect(d.line, isNotNull);
      expect(result.manifest.json, isEmpty);
    });

    test('an empty file is a diagnostic, not an exception', () {
      expect(
        codesOf(validateManifestText('', target: 'fixture').report),
        contains(DiagnosticCodes.manifestMalformedJson),
      );
    });

    test('a top-level array is rejected as the wrong shape', () {
      expect(
        codesOf(validateManifestText('[]', target: 'fixture').report),
        contains(DiagnosticCodes.manifestNotObject),
      );
    });

    test('wrong types everywhere produce diagnostics, never a crash', () {
      final String text = '''
{
  "schemaVersion": "one",
  "id": 42,
  "name": [],
  "description": {},
  "version": true,
  "author": "Example Co",
  "license": null,
  "swayvePluginApi": 1.5,
  "minimumSwayveVersion": 1,
  "runtime": 7,
  "platforms": "android",
  "capabilities": {},
  "permissions": "network",
  "entrypoint": false,
  "media": [],
  "settings": "none",
  "network": 0,
  "timeouts": "fast",
  "keywords": 3
}
''';
      final Report report =
          validateManifestText(text, target: 'fixture').report;
      expect(report.errorCount, greaterThan(15));
      expect(codesOf(report), everyElement(isNotEmpty));
      for (final Diagnostic d in report.diagnostics) {
        expect(d.pointer, startsWith('/'));
        expect(d.line, isNotNull);
      }
    });

    test('a manifest of nulls does not crash the cross-field rules', () {
      const String text =
          '{"id": null, "capabilities": null, "settings": null}';
      final Report report =
          validateManifestText(text, target: 'fixture').report;
      expect(report.errorCount, greaterThan(0));
    });

    test('the manifest file being absent is a diagnostic', () {
      final Report report =
          validatePluginDirectory('test/fixtures/plugins/does_not_exist')
              .report;
      expect(codesOf(report), contains(DiagnosticCodes.manifestNotFound));
    });
  });

  group('the source block', () {
    Map<String, Object?> withSource(Map<String, Object?> source) =>
        cleanManifest()..['source'] = source;

    test('a manifest that declares no source is unchanged by the rule', () {
      final Report report = validate(cleanManifest());
      expect(report.diagnostics, isEmpty, reason: codesOf(report).toString());
    });

    test('a fully declared source passes with nothing to report', () {
      final Report report = validate(
        withSource(<String, Object?>{
          'sourceId': 'demo_source',
          'displayName': 'Demo Source',
          'iconName': 'demo_source',
          'contentTypes': <String>['songs', 'albums', 'artists', 'videos'],
        }),
      );
      expect(report.diagnostics, isEmpty, reason: codesOf(report).toString());
    });

    test('a source that names nothing beyond its identity still passes', () {
      // Everything but the id is optional, and it has to stay that way: a
      // plugin that will not commit to a display name or a glyph is still a
      // place a query can be sent, and the host has honest fallbacks for both.
      final Report report = validate(
        withSource(<String, Object?>{
          'sourceId': 'demo_source',
          'contentTypes': <String>['songs'],
        }),
      );
      expect(report.diagnostics, isEmpty, reason: codesOf(report).toString());
    });

    test('an unknown content type is an enum failure, not a crash', () {
      final Report report = validate(
        withSource(<String, Object?>{
          'sourceId': 'demo_source',
          'contentTypes': <String>['songs', 'podcasts'],
        }),
      );
      final Diagnostic d = diagnosticFor(report, DiagnosticCodes.fieldEnum);
      expect(d.pointer, '/source/contentTypes/1');
    });

    test('a field the block does not define is rejected like any other', () {
      final Report report = validate(
        withSource(<String, Object?>{
          'sourceId': 'demo_source',
          'contentTypes': <String>['songs'],
          'canSearch': true,
        }),
      );
      // The whole point of reusing the capability vocabulary is that there is
      // no second place to say a source is searchable. A manifest inventing
      // one must not quietly work.
      final Diagnostic d = diagnosticFor(report, DiagnosticCodes.fieldUnknown);
      expect(d.pointer, '/source/canSearch');
    });

    test('a source object with no sourceId is a missing required field', () {
      final Report report = validate(
        withSource(<String, Object?>{'displayName': 'Demo Source'}),
      );
      final Diagnostic d = diagnosticFor(report, DiagnosticCodes.fieldRequired);
      expect(d.pointer, '/source/sourceId');
    });

    test('11: searchable but naming no content types is advisory', () {
      final Report report = validate(
        withSource(<String, Object?>{'sourceId': 'demo_source'}),
      );
      final Diagnostic d = diagnosticFor(
        report,
        DiagnosticCodes.sourceDeclaresNoContentTypes,
      );
      expect(d.severity, Severity.info);
      expect(d.pointer, '/source/contentTypes');
      // Info, so --strict must not promote it: a plugin part-way through
      // adopting the field has broken nothing.
      expect(report.passed(strict: true), isTrue);
    });

    test('11: a source nothing can be asked of is advisory', () {
      final Map<String, Object?> manifest = cleanManifest()
        ..['capabilities'] = <String>['metadata']
        ..['source'] = <String, Object?>{'sourceId': 'demo_source'};
      final Diagnostic d = diagnosticFor(
        validate(manifest),
        DiagnosticCodes.sourceWithoutReachableCapability,
      );
      expect(d.severity, Severity.info);
      expect(d.pointer, '/source');
    });

    test('the typed view reads every field back', () {
      final ManifestValidation result = validateManifestText(
        encodeManifest(
          withSource(<String, Object?>{
            'sourceId': 'demo_source',
            'displayName': 'Demo Source',
            'iconName': 'demo_source',
            'contentTypes': <String>['songs', 'videos'],
            'availability': 'ready',
          }),
        ),
        target: 'fixture',
      );
      expect(result.manifest.hasSourceObject, isTrue);
      expect(result.manifest.sourceId, 'demo_source');
      expect(result.manifest.sourceDisplayName, 'Demo Source');
      expect(result.manifest.sourceIconName, 'demo_source');
      expect(result.manifest.sourceContentTypes, <String>['songs', 'videos']);
      expect(result.manifest.sourceAvailability, 'ready');
    });

    test('the typed view answers nothing for a manifest with no source', () {
      final ManifestValidation result = validateManifestText(
        encodeManifest(cleanManifest()),
        target: 'fixture',
      );
      expect(result.manifest.hasSourceObject, isFalse);
      expect(result.manifest.sourceId, isNull);
      expect(result.manifest.sourceContentTypes, isEmpty);
    });
  });

  group('diagnostic locations', () {
    test('a diagnostic points at the line the field is on', () {
      const String text = '''
{
  "schemaVersion": 1,
  "id": "com.example.plugins.demo_source",
  "capabilities": ["webview"],
  "permissions": []
}
''';
      final Report report =
          validateManifestText(text, target: 'fixture').report;
      final Diagnostic d = diagnosticFor(
        report,
        DiagnosticCodes.capabilityRequiresPermission,
      );
      expect(d.source, 'plugin.json');
      expect(d.line, 4);
    });
  });
}
