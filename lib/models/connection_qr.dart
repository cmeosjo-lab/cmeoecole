import 'dart:convert';

class ConnectionQr {
  final String host, code, principalId;
  final int port;
  const ConnectionQr(this.host, this.port, this.code, this.principalId);
  String get address => '$host:$port';
  static ConnectionQr parse(String raw) {
    if (raw.length > 4096) throw const FormatException('QR non reconnu');
    String host = '', code = '', principalId = '';
    int port = 47831;
    final text = raw.trim();
    if (text.startsWith('{')) {
      final data = jsonDecode(text);
      if (data is! Map || data['app'] != 'GESTCOURS' || data['version'] != 1) {
        throw const FormatException('QR non reconnu');
      }
      host = (data['host'] ?? '').toString();
      code = (data['code'] ?? '').toString();
      principalId = (data['principalId'] ?? '').toString();
      port = int.tryParse((data['port'] ?? '').toString()) ?? 0;
    } else {
      final parts = text.split('|');
      if (parts.length == 5 && parts[0] == 'ECOLEPRO') {
        host = parts[1];
        port = int.tryParse(parts[2]) ?? 0;
        code = parts[4];
      } else if (parts.length == 3 && parts[0] == 'GESTCOURS') {
        final u = Uri.tryParse('http://${parts[1]}');
        if (u == null ||
            u.userInfo.isNotEmpty ||
            (u.path.isNotEmpty && u.path != '/'))
          throw const FormatException('QR non reconnu');
        host = u.host;
        port = u.hasPort ? u.port : 47831;
        code = parts[2];
      } else {
        throw const FormatException('QR non reconnu');
      }
    }
    host = host.trim();
    code = code.trim();
    principalId = principalId.trim();
    final ip = host.split('.').map(int.tryParse).toList();
    final localIPv4 =
        ip.length == 4 &&
        ip.every((x) => x != null && x >= 0 && x <= 255) &&
        (ip[0] == 10 ||
            (ip[0] == 192 && ip[1] == 168) ||
            (ip[0] == 172 && ip[1]! >= 16 && ip[1]! <= 31));
    final localName = RegExp(
      r'^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}\.local$',
    ).hasMatch(host);
    if ((!localIPv4 && !localName) ||
        port < 1 ||
        port > 65535 ||
        !RegExp(r'^\d{6}$').hasMatch(code) ||
        principalId.length > 128)
      throw const FormatException('QR non reconnu');
    return ConnectionQr(host, port, code, principalId);
  }
}
