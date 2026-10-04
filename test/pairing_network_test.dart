import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecole_gestion_prof_mobile/services/principal_api.dart';

void main() {
  test(
    'pairing waits for admin and distinguishes refusal without authorizing',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var state = 'pending';
      final sub = server.listen((r) async {
        expect(r.uri.queryParameters['deviceId'], 'PHONE-TEST');
        r.response.headers.contentType = ContentType.json;
        r.response.write(
          jsonEncode({
            'ok': true,
            'protocolVersion': 6,
            'teacher': 'Synthetic',
            'port': server.port,
            'principalId': 'GC-SYNTHETIC',
            'deviceAuthorized': state == 'authorized',
            'deviceStatus': state,
          }),
        );
        await r.response.close();
      });
      try {
        const api = PrincipalApi();
        final address = '127.0.0.1:${server.port}';
        await expectLater(
          api.pairAddress(address, '123456', deviceId: 'PHONE-TEST'),
          throwsA(isA<PrincipalApprovalPending>()),
        );
        state = 'refused';
        await expectLater(
          api.pairAddress(address, '123456', deviceId: 'PHONE-TEST'),
          throwsA(
            isA<PrincipalApiException>().having(
              (e) => e.message,
              'message',
              contains('refusée'),
            ),
          ),
        );
        state = 'authorized';
        expect(
          (await api.pairAddress(
            address,
            '123456',
            deviceId: 'PHONE-TEST',
          )).principalId,
          'GC-SYNTHETIC',
        );
      } finally {
        await sub.cancel();
        await server.close(force: true);
      }
    },
  );
}
