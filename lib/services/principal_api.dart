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
  static const int defaultPrincipalPort = 47831;
  final Duration timeout;

  const PrincipalApi({this.timeout = const Duration(seconds: 8)});

  Uri _uri(PrincipalConfig c, String path, [Map<String, String>? query]) =>
      Uri.parse('${c.baseUrl}$path').replace(queryParameters: query);

  Future<bool> ping(PrincipalConfig c) async {
    try {
      final r = await http.get(_uri(c, '/api/v1/ping')).timeout(timeout);
      if (r.statusCode < 200 || r.statusCode >= 300) return false;
      if (r.bodyBytes.isEmpty) return true;
      final decoded = jsonDecode(utf8.decode(r.bodyBytes));
      if (decoded is Map) {
        final ok = decoded['ok'];
        final version = int.tryParse((decoded['protocolVersion'] ?? '0').toString()) ?? 0;
        return ok == true && (version == 0 || version == supportedProtocol);
      }
      return true;
    } on SocketException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _probeHost(String host, int port) async {
    try {
      final uri = Uri.parse('http://$host:$port/api/v1/ping');
      final r = await http.get(uri).timeout(const Duration(milliseconds: 450));
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) return null;
      final decoded = jsonDecode(utf8.decode(r.bodyBytes));
      if (decoded is! Map) return null;
      final ok = decoded['ok'] == true;
      final version = int.tryParse((decoded['protocolVersion'] ?? '0').toString()) ?? 0;
      if (ok && version == supportedProtocol) return host;
    } catch (_) {}
    return null;
  }

  Future<PrincipalConfig?> _pairHost(String host, String code,
      {int port = defaultPrincipalPort, Duration timeout = const Duration(milliseconds: 650)}) async {
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


  Future<String?> discoverPrincipal({int port = defaultPrincipalPort}) async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );

    final prefixes = <String>{};
    final ownAddresses = <String>{};
    for (final iface in interfaces) {
      for (final address in iface.addresses) {
        final ip = address.address.trim();
        ownAddresses.add(ip);
        final p = ip.split('.');
        if (p.length != 4) continue;
        final a = int.tryParse(p[0]) ?? -1;
        final b = int.tryParse(p[1]) ?? -1;
        final isPrivate = a == 10 ||
            (a == 192 && b == 168) ||
            (a == 172 && b >= 16 && b <= 31);
        if (!isPrivate) continue;
        prefixes.add('${p[0]}.${p[1]}.${p[2]}');
      }
    }
    if (prefixes.isEmpty) return null;

    final ordered = <String>[];
    const priority = [1, 2, 10, 20, 30, 50, 100, 150, 200, 254];
    for (final prefix in prefixes) {
      for (final n in priority) {
        final host = '$prefix.$n';
        if (!ownAddresses.contains(host)) ordered.add(host);
      }
      for (var n = 1; n <= 254; n++) {
        if (priority.contains(n)) continue;
        final host = '$prefix.$n';
        if (!ownAddresses.contains(host)) ordered.add(host);
      }
    }

    const batchSize = 24;
    for (var start = 0; start < ordered.length; start += batchSize) {
      final end = (start + batchSize < ordered.length) ? start + batchSize : ordered.length;
      final batch = ordered.sublist(start, end);
      final results = await Future.wait(batch.map((host) => _probeHost(host, port)));
      for (final host in results) {
        if (host != null) return host;
      }
    }
    return null;
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
        port: previous.port > 0 ? previous.port : defaultPrincipalPort,
        timeout: const Duration(milliseconds: 900),
      );
      if (direct != null) return direct;
    }

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


  Future<Map<String, dynamic>?> _referenceData(PrincipalConfig c) async {
    try {
      final r = await http.get(
        _uri(c, '/api/v1/reference-data', {'teacher': c.teacher, 'code': c.code}),
        headers: {'Accept': 'application/json', 'User-Agent': 'GESTCOURS-Prof-Mobile/0.5.3'},
      ).timeout(timeout);
      if (r.statusCode < 200 || r.statusCode >= 300 || r.bodyBytes.isEmpty) return null;
      final decoded = jsonDecode(utf8.decode(r.bodyBytes));
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Future<SyncSnapshot> sync(PrincipalConfig c) async {
    final r = await http.get(
      _uri(c, '/api/v1/sync', {'teacher': c.teacher, 'code': c.code}),
      headers: {'Accept': 'application/json', 'User-Agent': 'GESTCOURS-Prof-Mobile/0.5.3'},
    ).timeout(timeout);

    if (r.statusCode == 403) {
      throw PrincipalApiException('PC Principal trouvé, mais le professeur ou le code est refusé.');
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw PrincipalApiException('Synchronisation refusée (${r.statusCode}).');
    }
    final decoded = jsonDecode(utf8.decode(r.bodyBytes));
    if (decoded is! Map) throw PrincipalApiException('Réponse de synchronisation invalide.');
    var snapshot = SyncSnapshot.fromJson(Map<String, dynamic>.from(decoded));
    if (snapshot.protocolVersion != 0 && snapshot.protocolVersion != supportedProtocol) {
      throw PrincipalApiException(
        'Version de protocole incompatible : Principal ${snapshot.protocolVersion}, mobile $supportedProtocol.',
      );
    }
    final references = await _referenceData(c);
    if (references != null && references.isNotEmpty) snapshot = snapshot.mergeReferenceData(references);
    return snapshot;
  }

  Future<Map<String, dynamic>> sendEvents(PrincipalConfig c, List<TeacherEvent> events) async {
    if (events.isEmpty) return {'received': 0, 'acknowledgedIds': <String>[]};
    final body = {
      'protocolVersion': supportedProtocol,
      'teacher': c.teacher,
      'events': events.map((e) => e.toProtocolV6Json()).toList(),
    };
    final r = await http.post(
      _uri(c, '/api/v1/events', {'teacher': c.teacher, 'code': c.code}),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode(body),
    ).timeout(timeout);
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw PrincipalApiException(
        'Transmission refusée (${r.statusCode}) : ${utf8.decode(r.bodyBytes).trim()}',
      );
    }
    if (r.bodyBytes.isEmpty) return {'received': events.length};
    final decoded = jsonDecode(utf8.decode(r.bodyBytes));
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {'received': events.length};
  }
}
