/// Unit tests for the PowerSync <-> Supabase connector's decision logic:
/// which upload errors are fatal (dropped) vs retryable, and that
/// [MiseConnector.fetchCredentials] declines to sync when signed out.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mise/core/sync/connector.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockSupabase extends Mock implements SupabaseClient {}

class _MockAuth extends Mock implements GoTrueClient {}

PostgrestException _err(String code) =>
    PostgrestException(message: 'x', code: code);

void main() {
  group('isFatalPostgrestError', () {
    test('integrity / access / data errors are fatal (drop the write)', () {
      expect(isFatalPostgrestError(_err('23505')), isTrue); // unique violation
      expect(isFatalPostgrestError(_err('23503')), isTrue); // FK violation
      expect(isFatalPostgrestError(_err('42501')), isTrue); // RLS denied
      expect(isFatalPostgrestError(_err('22P02')), isTrue); // bad input syntax
    });

    test('other / missing codes are treated as retryable', () {
      expect(isFatalPostgrestError(_err('08006')), isFalse); // connection
      expect(isFatalPostgrestError(_err('PGRST301')), isFalse);
      expect(isFatalPostgrestError(_err('')), isFalse);
    });
  });

  group('fetchCredentials', () {
    late _MockSupabase supabase;
    late _MockAuth auth;

    setUp(() {
      supabase = _MockSupabase();
      auth = _MockAuth();
      when(() => supabase.auth).thenReturn(auth);
    });

    test('returns null when there is no session (signed out)', () async {
      when(() => auth.currentSession).thenReturn(null);
      final creds = await MiseConnector(supabase).fetchCredentials();
      expect(creds, isNull);
    });
  });
}
