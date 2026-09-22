/// The seam behind the form's `Read a label` door, wired.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/config/env.dart';
import '../../../core/sync/session.dart';
import '../../import/data/remote_import_repository.dart';
import '../domain/label_read_repository.dart';
import '../domain/label_reading.dart';
import 'remote_label_repository.dart';

part 'label_read_provider.g.dart';

/// The `read-label` edge function when Supabase is configured. Unconfigured,
/// it refuses out loud rather than pretending to read. Widget tests override
/// this with a reader that answers from a fixture.
@Riverpod(keepAlive: true)
LabelReadRepository labelReadRepository(Ref ref) {
  if (!Env.isConfigured) return const _UnconfiguredLabelReader();
  return EdgeLabelRepository(
    functions: ref.watch(supabaseClientProvider).functions,
  );
}

class _UnconfiguredLabelReader implements LabelReadRepository {
  const _UnconfiguredLabelReader();

  @override
  Future<LabelReading> readLabel(String photoPath) async {
    throw const ImportException(
      'reading a label needs a connection to the Ansi backend, and this '
      'build has none configured — sign in against a configured backend to '
      'read one',
    );
  }
}
