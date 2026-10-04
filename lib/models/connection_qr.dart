/// Local connection details. QR credentials are never opened as external URLs.
class ConnectionQr {
  final String address, code, principalId;
  const ConnectionQr(this.address, this.code, this.principalId);
  factory ConnectionQr.parse(String input) {
    if (input.length > 2048) throw const FormatException('QR GESTCOURS non reconnu.');
    final parts = input.trim().split('|');
    String address, code, id = '';
    if ((parts.length == 3 || parts.length == 4) && parts[0] == 'GESTCOURS') {
      address = parts[1].trim(); code = parts[2].trim();
      if (parts.length == 4) id = parts[3].trim();
    } else if (parts.length == 5 && parts[0] == 'ECOLEPRO') {
      final host = parts[1].trim(); final port = int.tryParse(parts[2].trim());
      if (port == null || port < 1 || port > 65535) {
        throw const FormatException('Le QR contient une adresse de connexion incorrecte.');
      }
      address = '$host:$port'; code = parts[4].trim();
    } else {
      throw const FormatException('QR GESTCOURS non reconnu. Utilisez le QR affiché par le Principal.');
    }
    final uri = Uri.tryParse(address.contains('://') ? address : 'http://$address');
    if (uri == null || uri.scheme != 'http' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        (uri.hasPort && (uri.port < 1 || uri.port > 65535)) ||
        !RegExp(r'^\d{6}$').hasMatch(code) || id.length > 128) {
      throw const FormatException('Le QR contient des informations de connexion incorrectes.');
    }
    return ConnectionQr(address, code, id);
  }
}
