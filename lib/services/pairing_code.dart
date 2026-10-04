import 'dart:io';

/// Codes are generated locally by the Principal. Never accept a web login URL.
class PairingCode {
  final String address, code, principalId;
  const PairingCode(this.address, this.code, this.principalId);
  factory PairingCode.parse(String text) {
    final parts = text.trim().split('|');
    String host, code, principal = '';
    if (parts.length >= 3 && parts.length <= 4 && parts[0] == 'GESTCOURS') {
      host = parts[1].trim();
      code = parts[2].trim();
      if (parts.length == 4) principal = parts[3].trim();
    } else if (parts.length == 5 && parts[0] == 'ECOLEPRO') {
      host = '${parts[1].trim()}:${parts[2].trim()}';
      code = parts[4].trim();
    } else {
      throw const FormatException('QR GESTCOURS non reconnu.');
    }
    final uri = Uri.tryParse('http://$host');
    final ip = uri == null ? null : InternetAddress.tryParse(uri.host);
    final bytes = ip?.rawAddress;
    final local =
        bytes != null &&
        bytes.length == 4 &&
        (bytes[0] == 10 ||
            (bytes[0] == 192 && bytes[1] == 168) ||
            (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31));
    if (uri == null ||
        !local ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        (uri.hasPort && (uri.port < 1 || uri.port > 65535)) ||
        !RegExp(r'^\d{6}$').hasMatch(code) ||
        principal.length > 128) {
      throw const FormatException(
        'QR invalide. Utilisez le QR affiché par le Principal.',
      );
    }
    return PairingCode(
      '${uri.host}:${uri.hasPort ? uri.port : 47831}',
      code,
      principal,
    );
  }
}
