import 'package:flutter_test/flutter_test.dart';
import 'package:kulcskod/main.dart';

void main() {
  testWidgets('shows setup instructions when backend is not configured', (tester) async {
    await tester.pumpWidget(const KulcskodApp());
    expect(find.text('Kulcskód'), findsOneWidget);
    expect(find.textContaining('A backend még nincs konfigurálva'), findsOneWidget);
  });
}
