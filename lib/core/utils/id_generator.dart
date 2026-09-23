import 'dart:math';

final _random = Random();
int _counter = 0;

/// Generates a prefixed id (e.g. `Smfd3k2a01x7q`) that is unique across
/// devices — several phones write to the same backend, so a per-process
/// sequential counter would collide. Layout: prefix + base36 millis +
/// 2-char in-process sequence + 3 random chars, so ids of one prefix sort
/// chronologically (collections are ordered by id).
String nextId(String prefix) {
  final time = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final seq = (_counter++ % 1296).toRadixString(36).padLeft(2, '0');
  final rand = _random.nextInt(46656).toRadixString(36).padLeft(3, '0');
  return '$prefix$time$seq$rand';
}
