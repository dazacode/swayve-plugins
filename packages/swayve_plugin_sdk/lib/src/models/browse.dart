import 'package:meta/meta.dart';

import '../enums.dart';
import '../internal/equality.dart';
import '../internal/json.dart';

/// One page's worth of a browse request.
///
/// Paging is cursor-based, never offset-based: providers backed by feeds and
/// providers backed by databases can both honour a cursor, and a cursor stays
/// correct when the underlying collection changes between pages.
@immutable
final class SwayveBrowseRequest {
  /// Creates a browse request.
  const SwayveBrowseRequest({
    this.limit = 50,
    this.cursor,
    this.sort,
  });

  /// The first page of a default-sized listing.
  static const SwayveBrowseRequest first = SwayveBrowseRequest();

  /// The maximum number of items to return.
  ///
  /// A provider may return fewer — including zero with a cursor, if that is
  /// how its upstream pages — but never more.
  final int limit;

  /// An opaque continuation token from the previous page, or `null` for the
  /// first page.
  ///
  /// The host treats it as an opaque string and hands back exactly what it
  /// was given.
  final String? cursor;

  /// The requested ordering, or `null` to accept the provider's default.
  ///
  /// A hint: a provider that cannot sort this way returns its natural order
  /// rather than failing.
  final SwayveSortOrder? sort;

  /// Returns a request for the page following [cursor].
  SwayveBrowseRequest next(String cursor) =>
      SwayveBrowseRequest(limit: limit, cursor: cursor, sort: sort);

  /// Returns a copy with the given fields replaced.
  SwayveBrowseRequest copyWith({
    int? limit,
    String? cursor,
    SwayveSortOrder? sort,
  }) =>
      SwayveBrowseRequest(
        limit: limit ?? this.limit,
        cursor: cursor ?? this.cursor,
        sort: sort ?? this.sort,
      );

  /// The wire form. Null fields are omitted.
  Map<String, Object?> toJson() => pruneNulls({
        'limit': limit,
        'cursor': cursor,
        'sort': sort?.wireName,
      });

  /// Parses the wire form produced by [toJson].
  static SwayveBrowseRequest fromJson(Map<String, Object?> json) {
    final reader = JsonReader('SwayveBrowseRequest', json);
    return SwayveBrowseRequest(
      limit: reader.integerOrNull('limit') ?? 50,
      cursor: reader.stringOrNull('cursor'),
      sort: reader.enumValueOrNull('sort', SwayveSortOrder.fromWire),
    );
  }

  @override
  String toString() =>
      'SwayveBrowseRequest(limit: $limit, cursor: $cursor, sort: $sort)';

  @override
  bool operator ==(Object other) =>
      other is SwayveBrowseRequest &&
      limit == other.limit &&
      cursor == other.cursor &&
      sort == other.sort;

  @override
  int get hashCode => Object.hash(limit, cursor, sort);
}

/// One page of results, plus the cursor that fetches the next one.
///
/// [hasMore] is defined purely by the presence of [cursor]: a provider that
/// has reached the end must return `null`, and a provider that has more must
/// return a token, even if this page happened to come back empty.
@immutable
final class SwayvePage<T> {
  /// Creates a page of [items], optionally continued by [cursor].
  const SwayvePage({this.items = const [], this.cursor});

  /// The items on this page, in provider order.
  final List<T> items;

  /// An opaque token that fetches the next page, or `null` at the end.
  final String? cursor;

  /// Whether another page can be fetched.
  bool get hasMore => cursor != null;

  /// Whether this page carries no items.
  bool get isEmpty => items.isEmpty;

  /// Returns a copy with the given fields replaced.
  SwayvePage<T> copyWith({List<T>? items, String? cursor}) =>
      SwayvePage<T>(items: items ?? this.items, cursor: cursor ?? this.cursor);

  /// Returns a page whose items have been mapped through [convert].
  SwayvePage<R> map<R>(R Function(T item) convert) =>
      SwayvePage<R>(items: items.map(convert).toList(), cursor: cursor);

  /// The wire form, using [itemToJson] to serialize each item.
  ///
  /// The page is generic, so it cannot know how to serialize its contents;
  /// pass the element type's `toJson`.
  Map<String, Object?> toJson(
    Map<String, Object?> Function(T item) itemToJson,
  ) =>
      pruneNulls({
        'items': items.map(itemToJson).toList(),
        'cursor': cursor,
      });

  /// Parses the wire form, using [itemFromJson] for each item.
  static SwayvePage<T> fromJson<T>(
    Map<String, Object?> json,
    T Function(Map<String, Object?> json) itemFromJson,
  ) {
    final reader = JsonReader('SwayvePage', json);
    return SwayvePage<T>(
      items: reader.objectList('items', itemFromJson),
      cursor: reader.stringOrNull('cursor'),
    );
  }

  @override
  String toString() =>
      'SwayvePage<$T>(items: ${items.length}, hasMore: $hasMore)';

  @override
  bool operator ==(Object other) =>
      other is SwayvePage<T> &&
      deepEquals(items, other.items) &&
      cursor == other.cursor;

  @override
  int get hashCode => Object.hash(deepHash(items), cursor);
}
