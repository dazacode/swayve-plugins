import 'package:meta/meta.dart';

import '../enums.dart';
import '../internal/json.dart';

/// Where a plugin's sign-in stands, as the host understands it.
///
/// The host renders this — a "Sign in" button, an account row, a
/// "session expired" prompt — and never sees the credentials behind it
/// (principle 5). A plugin's tokens live in its own credential slot and are
/// never part of this object; a plugin that puts a token in
/// [SwayveAuthState.accountLabel] is leaking it into host logs.
@immutable
final class SwayveAuthState {
  /// Creates an auth state.
  const SwayveAuthState({
    required this.status,
    this.accountLabel,
    this.expiresAt,
    this.message,
  });

  /// Nobody is signed in.
  static const SwayveAuthState signedOut =
      SwayveAuthState(status: SwayveAuthStatus.signedOut);

  /// Where the sign-in stands.
  final SwayveAuthStatus status;

  /// A display name for the signed-in account, when there is one.
  ///
  /// Shown to the user verbatim. Never a token, never an internal id.
  final String? accountLabel;

  /// When the current session expires, in UTC, when the plugin knows.
  final DateTime? expiresAt;

  /// A short explanation for a `failed` or `expired` status.
  ///
  /// Developer-facing; the host decides what, if anything, to show the user.
  final String? message;

  /// Whether the user is currently signed in.
  bool get isSignedIn => status == SwayveAuthStatus.signedIn;

  /// Returns a copy with the given fields replaced.
  SwayveAuthState copyWith({
    SwayveAuthStatus? status,
    String? accountLabel,
    DateTime? expiresAt,
    String? message,
  }) =>
      SwayveAuthState(
        status: status ?? this.status,
        accountLabel: accountLabel ?? this.accountLabel,
        expiresAt: expiresAt ?? this.expiresAt,
        message: message ?? this.message,
      );

  /// The wire form. Null fields are omitted.
  Map<String, Object?> toJson() => pruneNulls({
        'status': status.wireName,
        'accountLabel': accountLabel,
        'expiresAt': expiresAt?.toUtc().toIso8601String(),
        'message': message,
      });

  /// Parses the wire form produced by [toJson].
  static SwayveAuthState fromJson(Map<String, Object?> json) {
    final reader = JsonReader('SwayveAuthState', json);
    return SwayveAuthState(
      status: reader.enumValue('status', SwayveAuthStatus.fromWire),
      accountLabel: reader.stringOrNull('accountLabel'),
      expiresAt: reader.has('expiresAt') ? reader.dateTime('expiresAt') : null,
      message: reader.stringOrNull('message'),
    );
  }

  @override
  String toString() => 'SwayveAuthState(${status.wireName}, $accountLabel)';

  @override
  bool operator ==(Object other) =>
      other is SwayveAuthState &&
      status == other.status &&
      accountLabel == other.accountLabel &&
      expiresAt == other.expiresAt &&
      message == other.message;

  @override
  int get hashCode => Object.hash(status, accountLabel, expiresAt, message);
}
