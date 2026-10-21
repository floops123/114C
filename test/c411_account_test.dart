import 'dart:convert';
import 'dart:io';

import 'package:c411_remote/api/c411_profile.dart';
import 'package:c411_remote/ui/c411_account.dart';
import 'package:c411_remote/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>;

void main() {
  testWidgets('réanimations : bilan, et alerte si plus dans Transmission',
      (tester) async {
    final list = C411Revival.parseList(_fixture('c411_revivals'));
    Future<void> show(Set<String>? hashes) => tester.pumpWidget(MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: Scaffold(
              body: SingleChildScrollView(
                  child: RevivalsCard(revivals: list, inTransmission: hashes))),
        ));
    await show({'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'});
    expect(find.textContaining('Zen versés sur 1 réanimation payée'), findsOneWidget);
    expect(find.textContaining('24 h partagées sur 72 h'), findsOneWidget);
    expect(find.text('PAYÉE · 3 ZEN'), findsOneWidget);
    expect(find.textContaining('Plus dans Transmission'), findsNothing);

    await show(const {});
    expect(find.textContaining('Plus dans Transmission'), findsOneWidget);
  });

  testWidgets('classement : sa place et le haut du tableau', (tester) async {
    final board = C411Leaderboard.parse(
        _fixture('c411_leaderboard')..['entries'] = [
          for (final e in _fixture('c411_leaderboard')['entries'] as List)
            {...(e as Map), 'avatarUrl': null},
        ]);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(body: SingleChildScrollView(child: LeaderboardCard(board: board, me: 'Premier'))),
    ));
    expect(find.textContaining('121\u202f567ᵉ'), findsOneWidget);
    expect(find.textContaining('95 XP par jour'), findsOneWidget);
    expect(find.text('Tanker · Bronze IV'), findsOneWidget);
    expect(find.text('Niv. 75'), findsOneWidget);
  });

  testWidgets('profil : marge de téléchargement comme le site', (tester) async {
    const gio = 1 << 30;
    final account = C411Account(
      username: 'moi',
      uploaded: (1007.76 * gio).round(),
      downloaded: (982.8 * gio).round(),
      uploadCredit: 180 * gio,
      minRatio: 0.8,
    );
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(body: SingleChildScrollView(child: C411ProfileCard(account: account))),
    ));
    expect(find.text('Marge de téléchargement : '), findsOneWidget);
    expect(find.text('277 Go'), findsOneWidget);
    expect(find.textContaining('dont 180 Go de crédit'), findsOneWidget);
    expect(find.textContaining('ratio 1,03'), findsOneWidget);
  });
}
