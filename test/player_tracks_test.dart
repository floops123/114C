import 'dart:async';

import 'package:c411_remote/ui/player_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

/// Lecteur factice : pistes fixes, choix enregistrés.
class _Player implements Player {
  final chosen = <Object>[];
  final _tracks = StreamController<Tracks>.broadcast();

  @override
  PlayerState get state => const PlayerState(
        tracks: Tracks(
          audio: [
            AudioTrack('auto', null, null),
            AudioTrack('no', null, null),
            AudioTrack('1', 'Français', 'fre'),
            AudioTrack('2', 'Anglais', 'eng'),
          ],
          subtitle: [
            SubtitleTrack('auto', null, null),
            SubtitleTrack('no', null, null),
            SubtitleTrack('3', 'Forcés', 'fre'),
          ],
        ),
        track: Track(audio: AudioTrack('1', 'Français', 'fre')),
      );

  @override
  PlayerStream get stream => _Stream(_tracks.stream);

  @override
  Future<void> setAudioTrack(AudioTrack track) async => chosen.add(track);

  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) async => chosen.add(track);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Stream implements PlayerStream {
  _Stream(this.tracks);
  @override
  final Stream<Tracks> tracks;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final audio in [true, false]) {
    testWidgets(
        'choix ${audio ? 'audio' : 'des sous-titres'} appliqué même si les '
        'commandes se masquent', (tester) async {
      final player = _Player();
      final shown = ValueNotifier(true);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: ValueListenableBuilder(
            valueListenable: shown,
            builder: (_, visible, _) => visible
                ? TrackMenu(player: player, audio: audio)
                : const SizedBox.shrink(),
          ),
        ),
      ));
      await tester.tap(find.byType(TrackMenu));
      await tester.pumpAndSettle();
      // Les commandes de media_kit se masquent : le bouton est retiré.
      shown.value = false;
      await tester.pump();
      await tester.tap(find.text(audio ? 'Anglais · ENG' : 'Forcés · FRE'));
      await tester.pumpAndSettle();
      expect(player.chosen.single,
          audio ? const AudioTrack('2', 'Anglais', 'eng') : const SubtitleTrack('3', 'Forcés', 'fre'));
    });
  }
}
