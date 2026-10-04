/// Connection-only QR. It is read by GESTCOURS, never opened as a web link.
class PairingCode {
  final String address;
  final String code;
  final String principalId;
  const PairingCode(this.address, this.code, [this.principalId = '']);
  factory PairingCode.parse(String raw) {
    if (raw.length > 1024) throw const FormatException('QR non reconnu.');
    final parts = raw.trim().split('|');
    late String address, code;
    var principal = '';
    if ((parts.length == 3 || parts.length == 4) &&
        parts.first == 'GESTCOURS') {
      address = parts[1].trim();
      code = parts[2].trim();
      if (parts.length == 4) principal = parts[3].trim();
    } else if (parts.length == 5 && parts.first == 'ECOLEPRO') {
      address = '${parts[1].trim()}:${parts[2].trim()}';
      code = parts[4].trim();
    } else {
      throw const FormatException('QR non reconnu.');
    }
    final uri = Uri.tryParse('http://$address');
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.path.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.hasPort && (uri.port < 1 || uri.port > 65535)) ||
        !RegExp(r'^\d{6}$').hasMatch(code) ||
        principal.contains(RegExp(r'[\s|]'))) {
      throw const FormatException('QR de connexion invalide.');
    }
    return PairingCode(address, code, principal);
  }
}
