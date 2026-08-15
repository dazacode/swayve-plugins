/// Structural equality and hashing helpers for the SDK's value types.
///
/// The SDK is dependency-free by contract, so it cannot use
/// `package:collection`. These helpers are intentionally small: they cover
/// the shapes the normalized models actually use — lists, sets and string
/// keyed maps of JSON-ish values — and nothing more.
library;

/// Compares [a] and [b] structurally, recursing through lists, sets and maps.
///
/// Sets are compared by membership, which relies on their elements having
/// sensible `==`/`hashCode`. Every set in the SDK holds enum values or
/// strings, so that holds.
bool deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is List) {
    if (b is! List || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Set) {
    if (b is! Set || a.length != b.length) return false;
    for (final element in a) {
      if (!b.contains(element)) return false;
    }
    return true;
  }
  if (a is Map) {
    if (b is! Map || a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (!deepEquals(entry.value, b[entry.key])) return false;
    }
    return true;
  }
  return a == b;
}

/// A hash code consistent with [deepEquals].
///
/// Lists hash in order; sets and maps hash without regard to iteration order,
/// so two equal collections built in different orders still agree.
int deepHash(Object? value) {
  if (value is List) {
    return Object.hashAll(value.map(deepHash));
  }
  if (value is Set) {
    return Object.hashAllUnordered(value.map(deepHash));
  }
  if (value is Map) {
    final entryHashes = <int>[];
    for (final entry in value.entries) {
      entryHashes.add(Object.hash(deepHash(entry.key), deepHash(entry.value)));
    }
    return Object.hashAllUnordered(entryHashes);
  }
  return value.hashCode;
}
