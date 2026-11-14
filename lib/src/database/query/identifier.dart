/// A plain name: letters, digits and underscores, optionally dotted
/// (`users.id`, `cache.items`). Nothing else is ever quoted.
final RegExp _plainName = RegExp(
  r'^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$',
);

/// Whether [name] is a plain name or a dotted chain of them, the only shape
/// the helpers below quote.
bool isPlainName(String name) => _plainName.hasMatch(name);

/// Quotes [name] as one SQLite identifier when it is a single plain name, so
/// a keyword such as `order` stays a name. Anything else (an expression, a
/// hand-quoted `"order"`, a dotted name) is returned as written.
String quoteIdentifier(String name) =>
    isPlainName(name) && !name.contains('.') ? '"$name"' : name;

/// Quotes each part of a plain or dotted plain name, so `users.id` becomes
/// `"users"."id"`. Anything else, such as `lower(email)`,
/// `name COLLATE NOCASE` or `RANDOM()`, is returned as written.
String wrapIdentifier(String name) => isPlainName(name)
    ? name.split('.').map((part) => '"$part"').join('.')
    : name;

/// The key SQLite gives the result column of [name] in a `SELECT`: the last
/// part of a plain or dotted plain name, and the text itself otherwise.
String resultKey(String name) =>
    isPlainName(name) ? name.split('.').last : name;

/// Quotes [value] as a SQLite string literal, doubling every embedded `'`.
String quoteString(String value) => "'${value.replaceAll("'", "''")}'";
