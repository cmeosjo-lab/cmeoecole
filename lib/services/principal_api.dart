import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/principal_config.dart';
import '../models/school_data.dart';
import '../models/teacher_event.dart';

class PrincipalApiException implements Exception {
  final String message;
  PrincipalApiException(this.message);
  @override
  String toString() => message;
}
class PrincipalApi {
  static const int supportedProtocol = 6;
  static const int defaultPort = 47831;
  final Duration timeout;
  const PrincipalApi({this.timeout = const Duration(seconds: 20)});
  Uri _uri(PrincipalConfig c, String path, [Map<String, String>? query]) =>
      Uri.parse('${c.baseUrl}$path').replace(queryParameters: query);
  Map<String, String> _auth(PrincipalConfig c, String deviceId) => {
    'teacher': c.teacher, 'code': c.code,
    if (deviceId.isNotEmpty) 'deviceId': deviceId,
    if (deviceId.isNotEmpty) 'deviceName': 'GESTCOURS Android/iOS',
  };
  Future<http.Response> _request(Future<http.Response> Function() send) async {
    try { return await send().timeout(timeout); }
    on TimeoutException { throw PrincipalApiException('Le Principal ne répond pas dans le délai prévu. Vos saisies sont conservées ; vous pouvez réessayer.'); }
    on SocketException { throw PrincipalApiException('PC Principal inaccessible. Vérifiez son adresse, le réseau local et son démarrage.'); }
    on http.ClientException { throw PrincipalApiException('Connexion réseau interrompue. Les saisies non confirmées sont conservées.'); }
  }
  Map<String, dynamic> _decode(http.Response r, {bool pairing = false}) {
    final body = utf8.decode(r.bodyBytes).trim();
    if (r.statusCode == 403) {
      if (body.contains('appareil')) {
        throw PrincipalApiException('Cet appareil doit être autorisé dans Principal > Réseau enseignants > Appareils.');
      }
      throw PrincipalApiException(pairing ? 'Le Principal répond, mais le code professeur est refusé.' : 'Accès refusé. Vérifiez le code professeur enregistré.');
    }
    if (r.statusCode == 413) throw PrincipalApiException('Le lot dépasse la taille acceptée par le Principal. Les saisies sont conservées.');
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw PrincipalApiException('Réponse du Principal ${r.statusCode} : ${body.length > 300 ? body.substring(0, 300) : body}');
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException { /* Retain local events on malformed replies. */ }
    throw PrincipalApiException('Réponse du Principal illisible. Aucune saisie non confirmée n’a été supprimée.');
  }
  Future<bool> ping(PrincipalConfig c) async {
    try {
      final d = _decode(await _request(() => http.get(_uri(c, '/api/v1/ping'))));
      return d['ok'] == true;
    } catch (_) { return false; }
  }
  Future<PrincipalConfig> pairAddress(String rawHost, String rawCode) async {
    final text = rawHost.trim();
    final parsed = Uri.tryParse(text.contains('://') ? text : 'http://$text');
    if (parsed == null || parsed.host.isEmpty || parsed.userInfo.isNotEmpty || (parsed.scheme != 'http' && parsed.scheme != 'https')) {
      throw PrincipalApiException('Saisissez l’adresse IPv4 du PC Principal, par exemple 192.168.1.20.');
    }
    final host = parsed.host;
    final address = InternetAddress.tryParse(host);
    if (address == null || address.type != InternetAddressType.IPv4 || address.isLoopback || address.address == '0.0.0.0') {
      throw PrincipalApiException('Recopiez l’adresse IPv4 du Principal. 127.0.0.1 désigne cet appareil, pas le PC Principal.');
    }
    final code = rawCode.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) throw PrincipalApiException('Saisissez le code professeur à 6 chiffres.');
    final uri = Uri(scheme: 'http', host: host, port: defaultPort, path: '/api/v1/pair', queryParameters: {'code': code});
    final data = _decode(await _request(() => http.get(uri)), pairing: true);
    if (data['protocolVersion'] != supportedProtocol) throw PrincipalApiException('Versions incompatibles. Installez le Principal et l’application du même lot.');
    final teacher = (data['teacher'] ?? '').toString().trim();
    if (data['ok'] != true || teacher.isEmpty) throw PrincipalApiException('Le Principal n’a pas identifié le professeur.');
    return PrincipalConfig(host: host, port: int.tryParse('${data['port']}') ?? defaultPort, teacher: teacher, code: code);
  }
  Future<SyncSnapshot> sync(PrincipalConfig c, {String deviceId = ''}) async {
    final auth = _auth(c, deviceId);
    final data = _decode(await _request(() => http.get(_uri(c, '/api/v1/sync', auth))));
    var snapshot = SyncSnapshot.fromJson(data);
    if (snapshot.protocolVersion != supportedProtocol) throw PrincipalApiException('Version de protocole incompatible.');
    final referenceResponse = await _request(() => http.get(_uri(c, '/api/v1/reference-data', auth)));
    if (referenceResponse.statusCode != 404) {
      snapshot = snapshot.mergeReferenceData(_decode(referenceResponse));
    }
    return snapshot;
  }
  Future<Map<String, dynamic>> sendEvents(PrincipalConfig c, List<TeacherEvent> events, {String deviceId = ''}) async {
    final body = jsonEncode({'protocolVersion': supportedProtocol, 'events': events.map((e) => e.toProtocolV6Json()).toList()});
    return _decode(await _request(() => http.post(_uri(c, '/api/v1/events', _auth(c, deviceId)),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'}, body: body)));
  }
  Future<List<Map<String, dynamic>>> eventStatuses(PrincipalConfig c, List<String> ids, {String deviceId = ''}) async {
    if (ids.isEmpty) return [];
    final r = await _request(() => http.get(_uri(c, '/api/v1/event-status', {..._auth(c, deviceId), 'ids': ids.join(',')})));
    if (r.statusCode == 404) return [];
    final data = _decode(r);
    final items = data['items'] ?? data['events'];
    return items is List ? items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
  }
  Future<PrincipalConfig?> _pairHost(String host, String code,
      {int port = defaultPort, Duration timeout = const Duration(milliseconds: 650)}) async {
    try {
      final uri = Uri.parse('http://$host:$port/api/v1/pair')
          .replace(queryParameters: {'code': code});
      final r = await http.get(uri, headers: {'Accept': 'application/json'}).timeout(timeout);
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) return null;
      final decoded = jsonDecode(utf8.decode(r.bodyBytes));
      if (decoded is! Map) return null;
      final data = Map<String, dynamic>.from(decoded);
      final ok = data['ok'] == true;
      final version = int.tryParse((data['protocolVersion'] ?? '0').toString()) ?? 0;
      final teacher = (data['teacher'] ?? '').toString().trim();
      final returnedPort = int.tryParse((data['port'] ?? port).toString()) ?? port;
      if (!ok || version != supportedProtocol || teacher.isEmpty) return null;
      return PrincipalConfig(host: host, port: returnedPort, teacher: teacher, code: code);
    } catch (_) {
      return null;
    }
  }



  Future<PrincipalConfig?> _discoverUdp(String code) async {
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? sub;
    Timer? timer;
    final completer = Completer<PrincipalConfig?>();
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      final targets = <String>{'255.255.255.255'};
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final parts = address.address.split('.');
          if (parts.length == 4) {
            targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
          }
        }
      }
      sub = socket.listen((event) {
        if (event != RawSocketEvent.read || completer.isCompleted) return;
        final datagram = socket?.receive();
        if (datagram == null) return;
        try {
          final decoded = jsonDecode(utf8.decode(datagram.data));
          if (decoded is! Map) return;
          final data = Map<String, dynamic>.from(decoded);
          if (data['ok'] != true) return;
          final protocol = int.tryParse((data['protocolVersion'] ?? '0').toString()) ?? 0;
          final teacher = (data['teacher'] ?? '').toString().trim();
          var port = int.tryParse((data['port'] ?? '$defaultPort').toString()) ?? defaultPort;
          if (protocol != supportedProtocol || teacher.isEmpty) return;
          if (port <= 0) port = defaultPort;
          completer.complete(PrincipalConfig(
            host: datagram.address.address,
            port: port,
            teacher: teacher,
            code: code,
          ));
        } catch (_) {}
      });
      final payload = utf8.encode('GESTCOURS_DISCOVER_V6|$code');
      for (final host in targets) {
        try {
          socket.send(payload, InternetAddress(host), 47832);
        } catch (_) {}
      }
      timer = Timer(const Duration(milliseconds: 2800), () {
        if (!completer.isCompleted) completer.complete(null);
      });
      return await completer.future;
    } catch (_) {
      return null;
    } finally {
      timer?.cancel();
      await sub?.cancel();
      socket?.close();
    }
  }

  Future<PrincipalConfig> discoverByCode(String rawCode, {PrincipalConfig? previous}) async {
    final code = rawCode.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw PrincipalApiException('Saisissez le code professeur à 6 chiffres.');
    }

    if (previous != null && previous.host.trim().isNotEmpty) {
      final direct = await _pairHost(
        previous.host.trim(),
        code,
        port: previous.port > 0 ? previous.port : defaultPort,
        timeout: const Duration(milliseconds: 900),
      );
      if (direct != null) return direct;
    }

    final udp = await _discoverUdp(code);
    if (udp != null) return udp;

    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    final hosts = <String>{};
    for (final iface in interfaces) {
      for (final address in iface.addresses) {
        final ip = address.address.trim();
        if (ip.startsWith('169.254.')) continue;
        final p = ip.split('.');
        if (p.length != 4) continue;
        final a = int.tryParse(p[0]);
        final b = int.tryParse(p[1]);
        final c = int.tryParse(p[2]);
        if (a == null || b == null || c == null) continue;
        if (!(a == 10 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31))) continue;
        for (var n = 1; n <= 254; n++) {
          hosts.add('$a.$b.$c.$n');
        }
      }
    }
    if (hosts.isEmpty) {
      throw PrincipalApiException(
        'Aucun réseau local détecté. Connectez le téléphone au même Wi-Fi que le PC Principal.',
      );
    }

    final list = hosts.toList(growable: false);
    const batchSize = 48;
    for (var start = 0; start < list.length; start += batchSize) {
      final end = (start + batchSize < list.length) ? start + batchSize : list.length;
      final results = await Future.wait(
        list.sublist(start, end).map((host) => _pairHost(host, code)),
        eagerError: false,
      );
      for (final found in results) {
        if (found != null) return found;
      }
    }

    throw PrincipalApiException(
      'GESTCOURS Principal introuvable. Vérifiez que le PC Principal est ouvert, sur le même Wi-Fi/réseau et que Windows a autorisé le réseau enseignants.',
    );
  }


}
