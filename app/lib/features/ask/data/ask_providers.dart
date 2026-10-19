/// The ask relay, wired.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/config/env.dart';
import '../../../core/sync/session.dart';
import '../domain/ask_repository.dart';
import 'remote_ask_repository.dart';

part 'ask_providers.g.dart';

/// The `ask` edge function when Supabase is configured. Unconfigured, it says
/// so rather than pretending to answer. Tests override this with a fake.
@Riverpod(keepAlive: true)
AskRepository askRepository(Ref ref) {
  if (!Env.isConfigured) return const _UnconfiguredAsk();
  return EdgeAskRepository(
    functions: ref.watch(supabaseClientProvider).functions,
  );
}

/// The signed-in account's own name and email, which tell "I" apart in the
/// household (`askMe`). Empty when there is no session, or no cloud.
@Riverpod(keepAlive: true)
({String? fullName, String? email}) askAccount(Ref ref) {
  if (!Env.isConfigured) return (fullName: null, email: null);
  final user = ref.watch(supabaseClientProvider).auth.currentUser;
  final name = user?.userMetadata?['full_name'];
  return (fullName: name is String ? name : null, email: user?.email);
}

class _UnconfiguredAsk implements AskRepository {
  const _UnconfiguredAsk();

  @override
  Future<AskReplyData> turn(List<Map<String, Object?>> messages) async =>
      throw const AskException(
        'Ask Ansi needs the cloud, and this build is not connected to it',
      );
}
