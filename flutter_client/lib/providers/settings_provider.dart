import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier();
});

class SettingsState {
  final String bridgeUrl;
  final ThemeMode themeMode;
  const SettingsState({
    this.bridgeUrl = "ws://127.0.0.1:17321/copilot-mirror/ws",
    this.themeMode = ThemeMode.dark,
  });
  SettingsState copyWith({String? bridgeUrl, ThemeMode? themeMode}) {
    return SettingsState(
      bridgeUrl: bridgeUrl ?? this.bridgeUrl,
      themeMode: themeMode ?? this.themeMode,
    );
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
        final themeStr = json["theme_mode"] as String?;
        if (themeStr != null) {
          state = state.copyWith(
            themeMode: themeStr == 'light' ? ThemeMode.light : ThemeMode.dark,
          );
        }
      }
    } catch (_) {}
  }
  Future<void> setBridgeUrl(String url) async {
    state = state.copyWith(bridgeUrl: url);
    await _save();
  }
  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _save();
  }
  Future<void> _save() async {
    try {
      final file = await _getFile();
      await file.writeAsString(jsonEncode({
        "bridge_url": state.bridgeUrl,
        "theme_mode": state.themeMode == ThemeMode.light ? 'light' : 'dark',
      }));
    } catch (_) {}
  }
}