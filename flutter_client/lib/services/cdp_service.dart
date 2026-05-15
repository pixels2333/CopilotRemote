import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class CdpTarget {
  final String id;
  final String url;
  final String title;
  final int score;
  final String type;
  final String webSocketDebuggerUrl;
  CdpTarget({required this.id, required this.url, required this.title, required this.score, required this.type, required this.webSocketDebuggerUrl});
  factory CdpTarget.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final url = json['url'] as String? ?? '';
    final title = json['title'] as String? ?? '';
    final type = json['type'] as String? ?? '';
    final wsUrl = json['webSocketDebuggerUrl'] as String? ?? '';
    return CdpTarget(id: id, url: url, title: title, score: _scoreTarget(url, title, type), type: type, webSocketDebuggerUrl: wsUrl);
  }
  static int _scoreTarget(String url, String title, String type) {
    final lowerUrl = url.toLowerCase();
    final lowerTitle = title.toLowerCase();
    int score = 0;
    if (lowerUrl.startsWith('vscode-file://')) score += 50;
    if (lowerTitle.contains('copilot mirror') || lowerTitle == 'copilot_mirror') score -= 40;
    final isLocalhost = lowerUrl.contains('localhost') || lowerUrl.contains('127.0.0.1');
    if (!isLocalhost) {
      if (lowerUrl.contains('github') && lowerUrl.contains('copilot')) score += 100;
      if (lowerUrl.contains('copilot')) score += 80;
      if (lowerUrl.contains('webview') || lowerUrl.contains('vscode-webview')) score += 20;
    }
    if (!isLocalhost) {
      if (lowerTitle.contains('copilot')) score += 80;
      if (lowerTitle.contains('chat')) score += 20;
    }
    if (lowerTitle.contains('visual studio code')) score += 5;
    if (type == 'webview') score += 15;
    if (type == 'page') score += 5;
    return score;
  }
}

enum CdpConnectionState { disconnected, discovering, connecting, connected }

class CdpClient {
  final String host;
  final int port;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  int _msgId = 0;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _eventController.stream;
  bool _connected = false;
  Timer? _reconnectTimer;
  CdpConnectionState get state => _connected ? CdpConnectionState.connected : CdpConnectionState.disconnected;
  bool get isConnected => _connected;
  CdpClient({this.host = '127.0.0.1', this.port = 9229});

  Future<List<CdpTarget>> discoverTargets() async {
    try {
      final uri = Uri.parse("http://$host:$port/json/list");
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return [];
      final list = jsonDecode(response.body) as List<dynamic>;
      final targets = list.map((e) => CdpTarget.fromJson(e as Map<String, dynamic>)).where((t) => t.webSocketDebuggerUrl.isNotEmpty).toList();
      targets.sort((a, b) => b.score.compareTo(a.score));
      return targets;
    } catch (_) { return []; }
  }

  Future<String?> connectToCopilot() async {
    disconnect();
    final targets = await discoverTargets();
    if (targets.isEmpty) return null;
    final candidates = targets.where((t) => (t.type == 'page' || t.type == 'webview') && t.score > 0).toList();
    final target = candidates.isNotEmpty ? candidates.first : targets.first;
    return connectToTarget(target.webSocketDebuggerUrl);
  }

  Future<String> connectToTarget(String wsUrl) async {
    disconnect();
    _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    await _channel!.ready;
    _connected = true;
    _sub = _channel!.stream.listen(
      (data) {
        final msg = jsonDecode(data as String) as Map<String, dynamic>;
        if (msg.containsKey('id')) {
          final id = msg['id'] as int;
          final completer = _pending.remove(id);
          if (completer != null) {
            if (msg.containsKey('error')) { completer.completeError(msg['error']); }
            else { completer.complete(msg); }
          }
        }
        _eventController.add(msg);
      },
      onError: (_) => _onDisconnect(),
      onDone: () => _onDisconnect(),
    );
    return wsUrl;
  }

  void _onDisconnect() {
    _connected = false;
    for (final c in _pending.values) { if (!c.isCompleted) c.completeError('CDP disconnected'); }
    _pending.clear();
  }

  Future<Map<String, dynamic>> call(String method, [Map<String, dynamic>? params]) async {
    if (!_connected) throw Exception('CDP not connected');
    final id = ++_msgId;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _channel!.sink.add(jsonEncode({'id': id, 'method': method, 'params': params ?? {}}));
    return completer.future;
  }

  Future<dynamic> evaluate(String expression, {bool awaitPromise = true}) async {
    final resp = await call('Runtime.evaluate', {'expression': expression, 'awaitPromise': awaitPromise, 'returnByValue': true});
    final result = resp['result'] as Map<String, dynamic>;
    if (result.containsKey('exceptionDetails') && result['exceptionDetails'] != null) {
      throw Exception('JS eval error: ${result['exceptionDetails']}');
    }
    return result['result']?['value'];
  }

  Future<void> enableRuntimeAndBinding() async {
    await call('Runtime.enable');
    await call('Runtime.addBinding', {'name': '__copilotMirrorEmit'});
  }

  Future<dynamic> injectObserver(String script) async {
    return evaluate(script);
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _connected = false;
    _onDisconnect();
  }

  void dispose() {
    disconnect();
    _eventController.close();
  }
}