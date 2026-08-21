import 'package:meta/meta.dart';

/// A one-shot, host-mediated capture of a sign-in session, for the plugins
/// whose only path to "signed in" is a set of values sitting in a page the
/// user is about to sign into — not a redirect URL `presentForResult`
/// already hands back.
///
/// Permission: `webview` **and** `external_auth`. Principle 5 still holds:
/// the plugin does not read the web view, does not see a cookie jar and does
/// not run its own script inside the page. It names, in its manifest's
/// `session_capture` block, a closed set of artifacts to capture and the
/// credential-store key each lands in; the host extracts exactly those and
/// writes them straight to `SwayveCredentialStore` under the declared keys.
/// The plugin never receives the captured values — [presentForSessionCapture]
/// returns only whether the capture succeeded and the URL that completed it,
/// the same shape `SwayveWebViewController.presentForResult` returns today.
/// A plugin that wants the values afterward reads them back through
/// `SwayvePluginContext.credentials`, exactly as it would for a manually
/// pasted secret.
abstract interface class SwayveSessionCaptureController {
  /// Presents [start] like `presentForResult`; on the same completion match,
  /// extracts exactly the artifacts named in the manifest's
  /// `session_capture` block and writes them to the credential store under
  /// their declared keys.
  ///
  /// [isComplete] must be a pure, fast predicate: it runs on every
  /// navigation, and it must not touch the network or block. Extraction only
  /// runs after [isComplete] first accepts a URL the view navigated to.
  ///
  /// Returns a [SwayveSessionCaptureResult] describing what happened —
  /// **never** the captured values themselves. Throws
  /// `SwayvePluginTimeoutException` if [timeout] elapses first.
  Future<SwayveSessionCaptureResult> presentForSessionCapture(
    Uri start, {
    required bool Function(Uri url) isComplete,
    Duration? timeout,
  });
}

/// How a [SwayveSessionCaptureController.presentForSessionCapture] call
/// concluded.
enum SwayveSessionCaptureOutcome {
  /// [isComplete] matched and every declared artifact was captured and
  /// written to the credential store.
  succeeded,

  /// The user backed out of the presented view before [isComplete] matched.
  dismissed,

  /// The call's [Duration] elapsed before [isComplete] matched.
  timedOut,

  /// [isComplete] matched, but one or more declared artifacts could not be
  /// extracted — nothing was written to the credential store.
  captureFailed,
}

/// What a [SwayveSessionCaptureController.presentForSessionCapture] call
/// returned.
///
/// This is deliberately as narrow as `Uri?`, the return type of
/// `SwayveWebViewController.presentForResult` — it carries no secret, no
/// header, no cookie, no page content. A plugin that needs the captured
/// values reads them back through `SwayvePluginContext.credentials` after
/// [outcome] is [SwayveSessionCaptureOutcome.succeeded].
@immutable
final class SwayveSessionCaptureResult {
  /// Creates a session-capture result.
  const SwayveSessionCaptureResult({
    required this.outcome,
    this.completionUrl,
  });

  /// A dismissal: the user backed out before completion.
  static const SwayveSessionCaptureResult dismissed =
      SwayveSessionCaptureResult(outcome: SwayveSessionCaptureOutcome.dismissed);

  /// How the call concluded.
  final SwayveSessionCaptureOutcome outcome;

  /// The URL that satisfied `isComplete`, when [outcome] is
  /// [SwayveSessionCaptureOutcome.succeeded] or
  /// [SwayveSessionCaptureOutcome.captureFailed].
  ///
  /// `null` for [SwayveSessionCaptureOutcome.dismissed] and
  /// [SwayveSessionCaptureOutcome.timedOut], where no completion URL was ever
  /// reached.
  final Uri? completionUrl;

  /// Whether the credential store now holds every artifact the manifest
  /// declared.
  bool get isSuccess => outcome == SwayveSessionCaptureOutcome.succeeded;

  @override
  String toString() =>
      'SwayveSessionCaptureResult(${outcome.name}, $completionUrl)';

  @override
  bool operator ==(Object other) =>
      other is SwayveSessionCaptureResult &&
      outcome == other.outcome &&
      completionUrl == other.completionUrl;

  @override
  int get hashCode => Object.hash(outcome, completionUrl);
}
