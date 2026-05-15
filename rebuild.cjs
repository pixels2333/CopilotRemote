const fs = require('fs');
const path = require('path');

// 1. Clean all dirty data from all source files
const regex = /\n?\{\"\$mid\":24,\"mimeType\":\"cache_control\",\"data\":\"[^\"]+\"\}\n?/g;

function cleanDir(dir) {
  for (const f of fs.readdirSync(dir)) {
    const fp = path.join(dir, f);
    if (fs.statSync(fp).isDirectory()) { cleanDir(fp); }
    else if (f.endsWith('.ts') || f.endsWith('.dart')) {
      const c = fs.readFileSync(fp, 'utf8').replace(regex, '\n');
      fs.writeFileSync(fp, c);
    }
  }
['D:/programme/CopilotRemote/src', 'D:/programme/CopilotRemote/flutter_client/lib'].forEach(cleanDir);

// 2. Rebuild settings_provider.dart
fs.writeFileSync('D:/programme/CopilotRemote/flutter_client/lib/providers/settings_provider.dart', 
`import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier();
});

class SettingsState {
  final String bridgeUrl;
  const SettingsState({this.bridgeUrl = 'ws://127.0.0.1:17321/copilot-mirror/ws'});

  SettingsState copyWith({String? bridgeUrl}) {
    return SettingsState(bridgeUrl: bridgeUrl ?? this.bridgeUrl);
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(const SettingsState()) { _load(); }

  String get fn => 'copilot_mirror_settings.json';
  Future<File> get f async => File('${(await getApplicationDocumentsDirectory()).path}/$fn');

  Future<void> _load() async {
    try {
      final file = await f;
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        final url = json['bridge_url'] as String?;
        if (url != null && url.isNotEmpty) state = state.copyWith(bridgeUrl: url);
      }
    } catch (_) {}
  }

  Future<void> setBridgeUrl(String url) async {
    state = state.copyWith(bridgeUrl: url);
    try { await (await f).writeAsString(jsonEncode({'bridge_url': url})); } catch (_) {}
  }
`);

console.log('ALL DONE');
