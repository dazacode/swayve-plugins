import 'enums.dart';
import 'exceptions.dart';

/// The reference implementation of permission checking.
///
/// The host mixes this into its real `SwayvePluginContext`, and the test
/// harness mixes it into `FakeSwayvePluginContext`, so a plugin that
/// over-reaches fails identically in a unit test and on a user's phone. That
/// symmetry is the whole point: permission bugs are found by the plugin
/// author, not by the user.
///
/// Principle 4: permissions are the security model. Checks are synchronous
/// and happen at the moment the facility is *accessed*, not when it is used,
/// so the stack trace points at the line that over-reached.
mixin SwayvePermissionEnforcement {
  /// The permissions the plugin declared in its manifest and the user
  /// granted.
  ///
  /// Implementers must return the effective set — the intersection of
  /// declared and granted — not merely what the manifest asked for.
  Set<SwayvePermission> get grantedPermissions;

  /// Whether [permission] is available to this plugin.
  bool hasPermission(SwayvePermission permission) =>
      grantedPermissions.contains(permission);

  /// Throws [SwayvePermissionDeniedException] unless [permission] is
  /// granted.
  ///
  /// Call this at the top of every getter that exposes a guarded facility.
  void requirePermission(SwayvePermission permission) {
    if (!hasPermission(permission)) {
      throw SwayvePermissionDeniedException(
        permission,
        message: "This plugin did not declare the '${permission.wireName}' "
            'permission.',
      );
    }
  }

  /// Returns [facility] if [permission] is granted, and throws
  /// [SwayvePermissionDeniedException] otherwise.
  ///
  /// The value is produced lazily so that a host need not construct a
  /// facility it is about to refuse.
  T guard<T>(SwayvePermission permission, T Function() facility) {
    requirePermission(permission);
    return facility();
  }
}
