import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:clash/services/clash_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('Private rules enable/disable and unlock flow', () async {
    final state = ClashState();
    await state.init();

    expect(state.privateRulesEnabled, false);
    expect(state.privateRulesUnlocked, false);

    // Enable with a 4-char pass
    final okEnable = await state.setPrivateRules(true, password: '1234');
    expect(okEnable, true);
    expect(state.privateRulesEnabled, true);
    expect(state.privateRulesUnlocked, true);

    // Lock in-memory
    state.lockPrivateRules();
    expect(state.privateRulesUnlocked, false);

    // Unlock with correct pass
    final okUnlock = await state.unlockPrivateRules('1234');
    expect(okUnlock, true);
    expect(state.privateRulesUnlocked, true);

    // Attempt to disable with wrong pass
    final okDisableFail = await state.setPrivateRules(false, password: '0000');
    expect(okDisableFail, false);
    expect(state.privateRulesEnabled, true);

    // Disable with correct pass
    final okDisable = await state.setPrivateRules(false, password: '1234');
    expect(okDisable, true);
    expect(state.privateRulesEnabled, false);
    expect(state.privateRulesUnlocked, false);
  });
}
