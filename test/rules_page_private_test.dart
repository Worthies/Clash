import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:clash/pages/rules_page.dart';
import 'package:clash/services/clash_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Rules page shows locked overlay when private mode enabled', (
    WidgetTester tester,
  ) async {
    final state = ClashState();
    await state.init();
    await state.setPrivateRules(true, password: '1234');
    state.lockPrivateRules();

    await tester.pumpWidget(
      ChangeNotifierProvider<ClashState>.value(
        value: state,
        child: const MaterialApp(home: Scaffold(body: RulesPage())),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Rules are private'), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
  });

  testWidgets('Unlocking rules allows viewing rules', (
    WidgetTester tester,
  ) async {
    final state = ClashState();
    await state.init();
    await state.setPrivateRules(true, password: '1234');
    state.lockPrivateRules();

    await tester.pumpWidget(
      ChangeNotifierProvider<ClashState>.value(
        value: state,
        child: const MaterialApp(home: Scaffold(body: RulesPage())),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Rules are private'), findsOneWidget);

    // Tap Unlock button and enter password
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '1234');
    await tester.tap(find.text('Unlock').last);
    await tester.pumpAndSettle();

    expect(find.text('Rules are private'), findsNothing);
  });
}
