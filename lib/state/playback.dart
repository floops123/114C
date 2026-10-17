import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/preferences.dart';

/// Positions de lecture par élément Jellyfin, pour reprendre où on s'était
/// arrêté. Une vidéo vue presque jusqu'au bout est oubliée.
abstract class PlaybackStore {
  Map<String, Duration> load();
  void save(Map<String, Duration> positions);
}

class PrefsPlaybackStore implements PlaybackStore {
  PrefsPlaybackStore(this._prefs);
  final SharedPreferencesWithCache _prefs;
  static const key = 'playback';

  @override
  Map<String, Duration> load() {
    try {
      final raw = _prefs.getString(key);
      if (raw == null) return {};
      return {
        for (final MapEntry(:key, :value)
            in (jsonDecode(raw) as Map<String, dynamic>).entries)
          key: Duration(seconds: (value as num).toInt()),
      };
    } on Object {
      return {};
    }
  }

  @override
  void save(Map<String, Duration> positions) => _prefs.setString(
      key,
      jsonEncode({
        for (final MapEntry(:key, :value) in positions.entries)
          key: value.inSeconds,
      }));
}

class MemoryPlaybackStore implements PlaybackStore {
  var _positions = <String, Duration>{};
  @override
  Map<String, Duration> load() => {..._positions};
  @override
  void save(Map<String, Duration> positions) => _positions = {...positions};
}

final playbackStoreProvider = Provider<PlaybackStore>((ref) {
  try {
    return PrefsPlaybackStore(ref.watch(sharedPrefsProvider));
  } on Object {
    return MemoryPlaybackStore(); // Préférences non initialisées (tests).
  }
});

/// Position à mémoriser : rien avant 30 s ni dans les 5 derniers pourcents
/// (vidéo terminée).
Duration? resumePoint(Duration position, Duration duration) {
  if (position < const Duration(seconds: 30)) return null;
  if (duration > Duration.zero && position.inSeconds >= duration.inSeconds * 0.95) {
    return null;
  }
  return position;
}
