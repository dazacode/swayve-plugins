/// A host-rendered web view, presented on the plugin's behalf.
///
/// Permission: `webview`. Principle 5 holds even here — the plugin does not
/// build a view, it asks the host to show a URL and tell it when a
/// recognised destination is reached. The user always sees that a web page
/// is being shown, and can always dismiss it.
///
/// The typical use is an OAuth-style sign-in: present the provider's login
/// page, watch for the redirect that carries the code, and hand the plugin
/// back that URL.
abstract interface class SwayveWebViewController {
  /// Presents [start] and completes when [isComplete] first accepts a URL
  /// the view navigates to.
  ///
  /// Returns the URL that satisfied [isComplete], or `null` when the user
  /// dismissed the view. Throws `SwayvePluginTimeoutException` if [timeout]
  /// elapses first.
  ///
  /// [isComplete] must be a pure, fast predicate: it runs on every
  /// navigation, and it must not touch the network or block. It is the
  /// plugin's only view of what happens inside the web view — no cookies, no
  /// page content, no script injection. A plugin that needs the *contents*
  /// of a page must fetch it itself through `SwayveHttpClient`.
  Future<Uri?> presentForResult(
    Uri start, {
    required bool Function(Uri url) isComplete,
    Duration? timeout,
  });
}
