import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Anki's own base91 alphabet: printable ASCII minus quote, backslash and
/// space, in Anki's order (lowercase, uppercase, digits, then punctuation).
///
/// This is *not* standard base91 and not base64. Verified character for
/// character against `genanki.util.BASE91_TABLE` (genanki 0.13.1), and the
/// guids produced here were diffed against `genanki.util.guid_for` on a
/// sample including accented and multi-byte input.
const String base91Table =
    'abcdefghijklmnopqrstuvwxyz'
    'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    '0123456789'
    r'!#$%&()*+,-./:;<=>?@[]^_`{|}~';

/// Encodes [value] in Anki's base91, most-significant digit first.
///
/// Returns the empty string for zero, matching Anki and genanki: their loop is
/// `while n > 0`, so a hash whose first 8 bytes are all zero yields `''`. That
/// is astronomically unlikely, but emitting `'a'` instead would be a silent
/// divergence from every other Anki implementation, so the behaviour is copied
/// rather than "fixed".
String encodeBase91(BigInt value) {
  if (value == BigInt.zero) return '';
  final radix = BigInt.from(base91Table.length);
  final buffer = StringBuffer();
  var remaining = value;
  final digits = <String>[];
  while (remaining > BigInt.zero) {
    digits.add(base91Table[(remaining % radix).toInt()]);
    remaining = remaining ~/ radix;
  }
  for (var i = digits.length - 1; i >= 0; i--) {
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Returns the Anki note guid for [key].
///
/// The guid is base91 over the **first 8 bytes of SHA-256** of [key] — not
/// sha1, not standard base64. Anki treats the guid as a note's stable identity
/// across imports, so the same key must always produce the same string: this is
/// what makes a re-import update a note in place instead of duplicating it.
///
/// Per decision Q19 the caller passes `"<lang>|<lemma>"`, giving one card per
/// word per language, so a word met again in another song updates its card.
String guidFor(String key) {
  final digest = sha256.convert(utf8.encode(key)).bytes.sublist(0, 8);
  var value = BigInt.zero;
  for (final byte in digest) {
    value = (value << 8) + BigInt.from(byte);
  }
  return encodeBase91(value);
}

/// Returns the `notes.csum` value for a note's [firstField].
///
/// AnkiDroid uses this checksum for duplicate detection, so it must be
/// populated: **genanki writes a literal 0 here** (`genanki/note.py`, "csum,
/// can be ignored"), which is exactly why a deck exported through genanki can
/// duplicate on re-import. Writing the real value is the other half of the
/// "updates in place, does not duplicate" done condition.
///
/// The value is the first 8 hex digits of SHA-1 of the field, read as an
/// integer. Anki strips HTML before hashing; the fields written here are plain
/// text, so there is nothing to strip.
int csumFor(String firstField) {
  final hex = sha1.convert(utf8.encode(firstField)).toString().substring(0, 8);
  return int.parse(hex, radix: 16);
}
