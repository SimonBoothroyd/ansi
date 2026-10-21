/// Reading who is signed in off the access token's `member_id` claim.
library;

import 'dart:convert';

import 'package:ansi/core/sync/session.dart';
import 'package:flutter_test/flutter_test.dart';

/// An unsigned JWT with [claims] — only the payload is read.
String _token(Map<String, Object?> claims) {
  String part(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part(claims)}.sig';
}

void main() {
  test('reads the member_id claim', () {
    expect(
      memberIdFromAccessToken(_token({'sub': 'u', 'member_id': 'm1'})),
      'm1',
    );
  });

  test('a token from before the claim, or none at all, is null', () {
    expect(memberIdFromAccessToken(_token({'sub': 'u'})), isNull);
    expect(memberIdFromAccessToken(null), isNull);
  });

  test('a token it cannot read is null, never a throw', () {
    expect(memberIdFromAccessToken('not.a.jwt'), isNull);
    expect(memberIdFromAccessToken('nodots'), isNull);
  });
}
