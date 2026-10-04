/// Connection QR generated locally by the Principal. No external website is opened.
class ConnectionQr {
  final String address;
  final String code;
  final String principalId;
  const ConnectionQr(this.address, this.code, this.principalId);

  factory ConnectionQr.parse(String raw) {
    if (raw.length > 512 || RegExp(r'[\x00-\x1f]').hasMatch(raw)) {
      throw const FormatException('QR de connexion non reconnu.');
    }
    final parts = raw.trim().split('|').map((s) => s.trim()).toList();
    String address, code, principal = '';
    if ((parts.length == 3 || parts.length == 4) && parts[0] == 'GESTCOURS') {
      address = parts[1];
      code = parts[2];
      if (parts.length == 4) principal = parts[3];
    } else if (parts.length == 5 && parts[0] == 'ECOLEPRO') {
      address = '${parts[1]}:${parts[2]}';
      code = parts[4];
    } else {
      throw const FormatException('QR de connexion non reconnu.');
    }
    final uri = Uri.tryParse('http://$address');
    if (!RegExp(r'^\d{6}$').hasMatch(code) ||
        uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.path.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.hasPort && (uri.port < 1 || uri.port > 65535)) ||
        !RegExp(r'^[a-zA-Z0-9_.:-]+$').hasMatch(address) ||
        !RegExp(r'^[a-zA-Z0-9_-]{0,100}$').hasMatch(principal)) {
      throw const FormatException('QR de connexion non reconnu.');
    }
    return ConnectionQr(address, code, principal);
  }
}
