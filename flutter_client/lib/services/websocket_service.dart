import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';

/// WebSocket connection states
enum _WsState { disconnected, connecting, connected }

/// Callback for received raw messages
typedef OnMessage = void Function(Map<String, dynamic>);
typedef OnStatusChange = void Function(bool connected);

/// Manages the WebSocket connection to the Node.js Bridge.
class WebSocketService {
  final String url;
  final String? authToken;
  final int _maxRetries = 10;
  final Duration _baseDelay = const Duration(seconds: 1);

  WebSocketChannel? _channel;
  _WsState _state = _WsState.disconnected;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  Timer? _keepAliveTimer;
  int _retryCount = 0;
  bool _intentionalClose = false;

  /// Exposed message stream for the protocol decoder
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  /// Connection status stream
  final _statusController = StreamController<bool>.broadcast();
  Stream<bool> get onStatusChange => _statusController.stream;

  bool get isConnected => _state == _WsState.connected;

  WebSocketService({required this.url, this.authToken});

  /// Connect to the WebSocket bridge
  Future<void> connect() async {
    if (_state == _WsState.connecting || _state == _WsState.connected) return;

    _state = _WsState.connecting;
    _intentionalClose = false;
    _statusController.add(false);

    try {
      final uri = Uri.parse(url);
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      _state = _WsState.connected;
      _retryCount = 0;
      _statusController.add(true);

      _subscription = _channel!.stream.listen(
        (data) {
          try {
            final decoded = jsonDecode(data as String) as Map<String, dynamic>;
            _messageController.add(decoded);
          } catch (_) {
            // ignore malformed JSON
          }
        },
        onError: (_) => _onDisconnected(),
        onDone: () => _onDisconnected(),
      );

      // Send client.hello
      _sendHello();

      // Start keep-alive ping
      _keepAliveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _channel?.sink.add(jsonEncode({
          'v': 1,
          'type': 'client.ping',
          'seq': 0,
          'payload': {},
        }));
      });

      // Cancel any pending reconnect
      _reconnectTimer?.cancel();
    } catch (_) {
      _state = _WsState.disconnected;
      _statusController.add(false);
      _scheduleReconnect();
    }
  }

  /// Send a raw envelope to the bridge
  void send(Map<String, dynamic> envelope) {
    if (_state != _WsState.connected || _channel == null) return;
    _channel!.sink.add(jsonEncode(envelope));
  }

  /// Intentional disconnect
  void disconnect() {
    _intentionalClose = true;
    _cleanup();
    _state = _WsState.disconnected;
    _statusController.add(false);
  }

  void _onDisconnected() {
    if (_intentionalClose) return;
    _state = _WsState.disconnected;
    _statusController.add(false);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_retryCount >= _maxRetries) {
      _state = _WsState.disconnected;
      _statusController.add(false);
      return;
    }

    _state = _WsState.disconnected;
    _statusController.add(false);
    _cleanup();

    final delay = _baseDelay * pow(2, _retryCount).toInt();
    _retryCount++;

    _reconnectTimer = Timer(
      delay > const Duration(seconds: 60)
          ? const Duration(seconds: 60)
          : delay,
      () => connect(),
    );
  }

  void _sendHello() {
    send({
      'v': 1,
      'seq': 0,
      'type': 'client.hello',
      'payload': {
        'clientId': 'flutter-mobile',
        'platform': 'flutter',
        'capabilities': ['delta', 'commands'],
        if (authToken != null) 'auth': {'token': authToken},
      },
    });
  }

  void _cleanup() {
    _subscription?.cancel();
    _subscription = null;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    _intentionalClose = true;
    _cleanup();
    _reconnectTimer?.cancel();
    _messageController.close();
    _statusController.close();
  }
}
