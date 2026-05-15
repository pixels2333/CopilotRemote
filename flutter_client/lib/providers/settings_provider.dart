import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier();
});

class SettingsState {
  final String bridgeUrl;
  const SettingsState({this.bridgeUrl = "ws://127.0.0.1:17321/copilot-mirror/ws"});
  SettingsState copyWith({String? bridgeUrl}) {
    return SettingsState(bridgeUrl: bridgeUrl ?? this.bridgeUrl);
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(const SettingsState()) { _load(); }
  static const _fn = "copilot_mirror_settings.json";
  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(dir.path + "/" + _fn);
  }
  Future<void> _load() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        final url = json["bridge_url"] as String?;
        if (url != null && url.isNotEmpty) state = state.copyWith(bridgeUrl: url);
      }
    } catch (_) {}
  }
  Future<void> setBridgeUrl(String url) async {
    state = state.copyWith(bridgeUrl: url);
    try {
      final file = await _getFile();
      await file.writeAsString(jsonEncode({"bridge_url": url}));
    } catch (_) {}
  }
}