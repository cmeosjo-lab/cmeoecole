import 'dart:convert';

class ConnectionQr {
  final String address;
  final String code;
  final String principalId;
  const ConnectionQr(this.address, this.code, this.principalId);
  static ConnectionQr parse(String raw) {
    String host = '', code = '', principalId = '';
    int port = 47831;
    final value = raw.trim();
    if (value.startsWith('{')) {
      final data = jsonDecode(value);
      if (data is! Map || data['app'] != 'GESTCOURS' || data['v'] != 1)
        throw const FormatException('QR inconnu');
      host = (data['host'] ?? '').toString();
      code = (data['code'] ?? '').toString();
      port = int.tryParse((data['port'] ?? '').toString()) ?? 0;
      principalId = (data['principalId'] ?? '').toString();
    } else {
      final parts = value.split('|');
      if (parts.length == 5 && parts[0] == 'ECOLEPRO') {
        host = parts[1];
        port = int.tryParse(parts[2]) ?? 0;
        code = parts[4];
      } else if (parts.length == 3 && parts[0] == 'GESTCOURS') {
        final u = Uri.tryParse(
          parts[1].contains('://') ? parts[1] : 'http://${parts[1]}',
        );
        if (u == null ||
            u.scheme != 'http' ||
            u.userInfo.isNotEmpty ||
            (u.path.isNotEmpty && u.path != '/') ||
            u.hasQuery ||
            u.hasFragment)
          throw const FormatException('Adresse QR invalide');
        host = u.host;
        port = u.hasPort ? u.port : 47831;
        code = parts[2];
      }
    }
    host = host.trim();
    code = code.trim();
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9.\-]*$').hasMatch(host) ||
        port < 1 ||
        port > 65535 ||
        !RegExp(r'^\d{6}$').hasMatch(code))
      throw const FormatException('QR de connexion incomplet');
    return ConnectionQr('$host:$port', code, principalId);
  }
}
