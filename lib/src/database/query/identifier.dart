/// Quotes [name] as a single SQLite identifier.
///
/// The name is wrapped in double quotes and every embedded `"` is doubled, so
/// a keyword such as `order` or a name carrying a quote reaches SQLite as one
/// identifier and never as SQL.
String quoteIdentifier(String name) => '"${name.replaceAll('"', '""')}"';

/// Quotes each dot-separated segment of [name], so `users.id` becomes
/// `"users"."id"` and keeps addressing the column of a qualified table.
String wrapIdentifier(String name) =>
    name.split('.').map(quoteIdentifier).join('.');

/// Quotes [value] as a SQLite string literal, doubling every embedded `'`.
String quoteString(String value) => "'${value.replaceAll("'", "''")}'";
