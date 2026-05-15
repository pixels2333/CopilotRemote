const fs = require('fs');

const code = `import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier();
});

class SettingsState {
  final String bridgeUrl;
  final bool isLoading;

  const SettingsState({
    this.bridgeUrl = 'ws://127.0.0.1:17321/copilot-mirror/ws',
    this.isLoading = true,
  });

  SettingsState copyWith({String? bridgeUrl, bool? isLoading}) {
    return SettingsState(
      bridgeUrl: bridgeUrl ?? this.bridgeUrl,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(const SettingsState()) {
    _load();
  }

  String get _fileName => 'copilot_mirror_settings.json';

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('\${dir.path}/\$_fileName');
  }

  Future<void> _load() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final url = json['bridge_url'] as String?;
        if (url != null && url.isNotEmpty) {
          state = state.copyWith(bridgeUrl: url);
        }
      }
    } catch (_) {}
    state = state.copyWith(isLoading: false);
  }

  Future<void> setBridgeUrl(String url) async {
    state = state.copyWith(bridgeUrl: url);
    try {
      final file = await _getFile();
      await file.writeAsString(jsonEncode({'bridge_url': url}));
    } catch (_) {}
  }
`;

fs.writeFileSync(
  'D:/programme/CopilotRemote/flutter_client/lib/providers/settings_provider.dart',
  code,
  'utf8'
);
console.log('OK');
