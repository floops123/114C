import 'package:c411_remote/build_defaults.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('aucun --dart-define : tout est vide', () {
    const d = BuildDefaults();
    expect(d.hasAny, isFalse);
    expect(d.toAppSettings(), isNotNull);
    expect(d.toAppSettings().rpcUrl, isEmpty);
    expect(d.toAppSettings().apiKeys, isEmpty);
    expect(d.toAppSettings().mediaFolders, isEmpty);
  });

  test('les variables connues sont exposées', () {
    // Liste non vide et au moins les plus utilisées.
    expect(BuildDefaults.allVariables, contains('C411_RPC_URL'));
    expect(BuildDefaults.allVariables, contains('C411_FTP_HOST'));
    expect(BuildDefaults.allVariables, contains('C411_C411_KEY'));
    expect(BuildDefaults.allVariables, contains('C411_ASTRATORRENT_KEY'));
  });
}