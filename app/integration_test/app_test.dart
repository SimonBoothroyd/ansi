import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Skipped: no UI yet — enable once a first screen lands.
  testWidgets('app boots', (tester) async {
    // TODO(step-2): bootstrap the app and assert the first screen renders.
  }, skip: true);
}
