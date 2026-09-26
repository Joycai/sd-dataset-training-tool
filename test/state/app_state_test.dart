import 'package:dataset_training_tool/services/settings_service.dart';
import 'package:dataset_training_tool/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('settingsService is the instance the state was built with', () {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    final state = AppState(settings);
    addTearDown(state.dispose);
    expect(state.settingsService, same(settings));
  });
}
