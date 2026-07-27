import 'package:flutter/foundation.dart';

/// Which view the inspector (right column) is showing.
enum InspectorTab { library, dataset }

/// Chrome state of the workbench shell: which side columns are visible and
/// which inspector tab is active.
///
/// Lifted out of the panels themselves because two surfaces now drive it —
/// the icon rail and the title bar's sidebar toggles — and the panels
/// cannot own state their siblings need to set.
///
/// Deliberately not persisted: hiding a column is a momentary "give me room"
/// gesture, and a workbench that starts with panels missing reads as broken.
class WorkbenchLayout extends ChangeNotifier {
  InspectorTab _inspectorTab = InspectorTab.library;
  bool _navigatorVisible = true;
  bool _inspectorVisible = true;

  InspectorTab get inspectorTab => _inspectorTab;
  bool get navigatorVisible => _navigatorVisible;
  bool get inspectorVisible => _inspectorVisible;

  /// Selects [tab] and reveals the inspector — picking a tab from the rail
  /// should always end with that tab on screen, even if the column was
  /// hidden.
  void showInspectorTab(InspectorTab tab) {
    if (_inspectorTab == tab && _inspectorVisible) return;
    _inspectorTab = tab;
    _inspectorVisible = true;
    notifyListeners();
  }

  void toggleNavigator() {
    _navigatorVisible = !_navigatorVisible;
    notifyListeners();
  }

  void toggleInspector() {
    _inspectorVisible = !_inspectorVisible;
    notifyListeners();
  }

  void showNavigator() {
    if (_navigatorVisible) return;
    _navigatorVisible = true;
    notifyListeners();
  }
}
