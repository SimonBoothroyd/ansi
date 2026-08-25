import 'bootstrap.dart';

/// App entrypoint. All real startup lives in [bootstrap] so it can be reused by
/// integration tests and alternate entrypoints (e.g. a `main_dev.dart`).
void main() => bootstrap();
