import 'package:c411_remote/api/transmission.dart';
import 'package:c411_remote/core/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatBytes', () {
    expect(formatBytes(512), '512 o');
    expect(formatBytes(1536), '1,50 Ko');
    expect(formatBytes(1495768319), '1,39 Go');
  });

  test('formatRatio gère les valeurs spéciales de Transmission', () {
    expect(formatRatio(-1), '—');
    expect(formatRatio(-2), '∞');
    expect(formatRatio(1.234), '1,23');
  });

  test('normalizeUrl ajoute le chemin RPC par défaut', () {
    expect(TransmissionClient.normalizeUrl('https://srv:9091'),
        'https://srv:9091/transmission/rpc');
    expect(TransmissionClient.normalizeUrl('srv.example.com/custom/rpc'),
        'http://srv.example.com/custom/rpc');
  });
}
