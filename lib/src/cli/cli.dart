import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import '../diagnostics.dart';
import '../tool_version.dart';

/// Process exit codes, fixed by CONTRACT section 9.
abstract final class ExitCodes {
  /// Everything passed.
  static const int ok = 0;

  /// Validation or verification failed.
  static const int failed = 1;

  /// The command line was wrong.
  static const int badUsage = 2;

  /// The tool hit something it did not expect.
  static const int internalError = 3;
}

/// The command line was wrong. Always becomes [ExitCodes.badUsage].
final class CliUsageError implements Exception {
  /// Creates a usage error.
  const CliUsageError(this.message);

  /// What was wrong, phrased for the person who typed it.
  final String message;

  @override
  String toString() => message;
}

/// The three flags every tool in this repository shares.
final class CliOptions {
  /// Creates options.
  const CliOptions({
    required this.json,
    required this.quiet,
    required this.strict,
  });

  /// Emit a machine-readable report instead of human output.
  final bool json;

  /// Say as little as possible: errors only, no summary.
  final bool quiet;

  /// Treat warnings as errors. CI uses this.
  final bool strict;
}

/// An [ArgParser] carrying the flags every tool shares.
ArgParser baseParser() => ArgParser(usageLineLength: 80)
  ..addFlag(
    'json',
    negatable: false,
    help: 'Emit a machine-readable report on stdout.',
  )
  ..addFlag(
    'quiet',
    abbr: 'q',
    negatable: false,
    help: 'Print errors only; no summary.',
  )
  ..addFlag(
    'strict',
    negatable: false,
    help: 'Treat warnings as errors.',
  )
  ..addFlag(
    'help',
    abbr: 'h',
    negatable: false,
    help: 'Show this help.',
  );

/// Runs one of the three CLIs end to end and returns its exit code.
///
/// Every tool goes through here so that the flag set, the output format and the
/// exit codes cannot drift apart between them.
Future<int> runCli({
  required String tool,
  required String usage,
  required ArgParser parser,
  required List<String> arguments,
  required Future<List<Report>> Function(ArgResults args, CliOptions options)
      body,
  List<String> Function()? epilogue,
}) async {
  final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (e) {
    return _usageFailure(
      tool: tool,
      usage: usage,
      parser: parser,
      message: e.message,
      json: arguments.contains('--json'),
    );
  }

  final CliOptions options = CliOptions(
    json: results.flag('json'),
    quiet: results.flag('quiet'),
    strict: results.flag('strict'),
  );

  if (results.flag('help')) {
    stdout
      ..writeln(usage)
      ..writeln()
      ..writeln(parser.usage);
    return ExitCodes.ok;
  }

  final List<Report> reports;
  try {
    reports = await body(results, options);
  } on CliUsageError catch (e) {
    return _usageFailure(
      tool: tool,
      usage: usage,
      parser: parser,
      message: e.message,
      json: options.json,
    );
  } on Object catch (e, stackTrace) {
    if (options.json) {
      _writeJson(<String, Object?>{
        'tool': tool,
        'toolVersion': kToolsVersion,
        'ok': false,
        'strict': options.strict,
        'results': <Object?>[],
        'summary': _summaryJson(0, 0, 0),
        'error': <String, Object?>{
          'code': DiagnosticCodes.internalError,
          'message': '$e',
        },
      });
    } else {
      stderr
        ..writeln('$tool: internal error: $e')
        ..writeln(stackTrace);
    }
    return ExitCodes.internalError;
  }

  emitReports(reports, tool: tool, options: options);
  if (epilogue != null && !options.json && !options.quiet) {
    for (final String line in epilogue()) {
      stdout.writeln(line);
    }
  }
  final bool ok = reports.every((Report r) => r.passed(strict: options.strict));
  return ok ? ExitCodes.ok : ExitCodes.failed;
}

/// Writes [reports] in whichever format [options] asked for.
void emitReports(
  List<Report> reports, {
  required String tool,
  required CliOptions options,
}) {
  if (options.json) {
    _writeJson(<String, Object?>{
      'tool': tool,
      'toolVersion': kToolsVersion,
      'ok': reports.every((Report r) => r.passed(strict: options.strict)),
      'strict': options.strict,
      'results': reports
          .map((Report r) => r.toJson(strict: options.strict))
          .toList(growable: false),
      'summary': _summaryJson(
        _total(reports, Severity.error),
        _total(reports, Severity.warning),
        _total(reports, Severity.info),
      ),
    });
    return;
  }

  for (final Report report in reports) {
    final List<Diagnostic> shown = options.quiet
        ? report.diagnostics
            .where((Diagnostic d) => d.severity == Severity.error)
            .toList(growable: false)
        : report.diagnostics;
    if (options.quiet && shown.isEmpty) {
      continue;
    }
    stdout.writeln(report.target);
    for (final Diagnostic diagnostic in shown) {
      stdout.writeln('  ${formatDiagnostic(diagnostic)}');
    }
    if (!options.quiet && reports.length == 1) {
      stdout.writeln(
        summaryLine(report.errorCount, report.warningCount),
      );
    }
  }

  if (!options.quiet && reports.length != 1) {
    stdout.writeln(
      summaryLine(
        _total(reports, Severity.error),
        _total(reports, Severity.warning),
      ),
    );
  }
}

/// One diagnostic line, without its leading indent.
///
/// `ERROR   capabilities: 'streaming' requires permission 'network'`
/// `   (plugin.json:14)`
String formatDiagnostic(Diagnostic diagnostic) {
  final StringBuffer buffer = StringBuffer()
    ..write(diagnostic.severity.label.padRight(8))
    ..write(diagnostic.message);
  final String? source = diagnostic.source;
  if (source != null) {
    buffer.write('   ($source');
    if (diagnostic.line != null) {
      buffer.write(':${diagnostic.line}');
    }
    buffer.write(')');
  }
  return buffer.toString();
}

/// The trailing count line: `2 problems (1 error, 1 warning)`.
///
/// Info notes are not problems and are deliberately left out of the count.
String summaryLine(int errors, int warnings) {
  final int total = errors + warnings;
  if (total == 0) {
    return '0 problems';
  }
  final List<String> parts = <String>[
    if (errors > 0) '$errors ${errors == 1 ? 'error' : 'errors'}',
    if (warnings > 0) '$warnings ${warnings == 1 ? 'warning' : 'warnings'}',
  ];
  return '$total ${total == 1 ? 'problem' : 'problems'} (${parts.join(', ')})';
}

int _total(List<Report> reports, Severity severity) => reports.fold<int>(
      0,
      (int sum, Report r) =>
          sum +
          r.diagnostics.where((Diagnostic d) => d.severity == severity).length,
    );

Map<String, Object?> _summaryJson(int errors, int warnings, int infos) =>
    <String, Object?>{
      'errors': errors,
      'warnings': warnings,
      'infos': infos,
    };

void _writeJson(Map<String, Object?> document) {
  const JsonEncoder encoder = JsonEncoder.withIndent('  ');
  stdout.writeln(encoder.convert(document));
}

int _usageFailure({
  required String tool,
  required String usage,
  required ArgParser parser,
  required String message,
  required bool json,
}) {
  if (json) {
    _writeJson(<String, Object?>{
      'tool': tool,
      'toolVersion': kToolsVersion,
      'ok': false,
      'strict': false,
      'results': <Object?>[],
      'summary': _summaryJson(1, 0, 0),
      'error': <String, Object?>{
        'code': DiagnosticCodes.badUsage,
        'message': message,
      },
    });
  } else {
    stderr
      ..writeln('$tool: $message')
      ..writeln()
      ..writeln(usage)
      ..writeln()
      ..writeln(parser.usage);
  }
  return ExitCodes.badUsage;
}
