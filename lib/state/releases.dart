import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/c411.dart';
import '../api/transmission.dart';
import 'torrents.dart';

class ReleaseFilter {
  const ReleaseFilter({
    this.categoryId,
    this.subcategoryId,
    this.query = '',
    this.sortBy,
  });

  final int? categoryId;
  final int? subcategoryId;
  final String query;

  /// null = plus récents, `seeders` = plus partagés.
  final String? sortBy;

  ReleaseFilter copyWith({
    int? Function()? categoryId,
    int? Function()? subcategoryId,
    String? query,
    String? Function()? sortBy,
  }) =>
      ReleaseFilter(
        categoryId: categoryId != null ? categoryId() : this.categoryId,
        subcategoryId:
            subcategoryId != null ? subcategoryId() : this.subcategoryId,
        query: query ?? this.query,
        sortBy: sortBy != null ? sortBy() : this.sortBy,
      );
}

class ReleasesState {
  const ReleasesState({
    this.filter = const ReleaseFilter(),
    this.items = const [],
    this.page = 0,
    this.totalPages = 1,
    this.total = 0,
    this.loading = false,
    this.error,
  });

  final ReleaseFilter filter;
  final List<Release> items;
  final int page;
  final int totalPages;
  final int total;
  final bool loading;
  final String? error;

  bool get hasMore => page < totalPages;
}

class ReleasesNotifier extends Notifier<ReleasesState> {
  int _generation = 0;

  @override
  ReleasesState build() {
    ref.watch(c411Provider);
    Future.microtask(loadMore);
    return const ReleasesState();
  }

  void setFilter(ReleaseFilter filter) {
    _generation++;
    state = ReleasesState(filter: filter);
    loadMore();
  }

  Future<void> reload() async {
    _generation++;
    state = ReleasesState(filter: state.filter);
    await loadMore();
  }

  Future<void> loadMore() async {
    final api = ref.read(c411Provider);
    if (api == null || state.loading || !state.hasMore) return;
    final generation = _generation;
    final s = state;
    state = ReleasesState(
      filter: s.filter,
      items: s.items,
      page: s.page,
      totalPages: s.totalPages,
      total: s.total,
      loading: true,
    );
    try {
      final f = s.filter;
      final result = await api.releases(
        page: s.page + 1,
        categoryId: f.categoryId,
        subcategoryId: f.subcategoryId,
        query: f.query,
        sortBy: f.sortBy,
      );
      if (!ref.mounted || generation != _generation) return;
      // Un nouvel upload entre deux pages décale la pagination : on dédoublonne.
      final known = {for (final r in s.items) r.id};
      state = ReleasesState(
        filter: f,
        items: [...s.items, ...result.items.where((r) => known.add(r.id))],
        page: result.page,
        totalPages: result.totalPages,
        total: result.total,
      );
    } on C411Exception catch (e) {
      if (!ref.mounted || generation != _generation) return;
      state = ReleasesState(
        filter: s.filter,
        items: s.items,
        page: s.page,
        totalPages: s.totalPages,
        total: s.total,
        error: e.message,
      );
    }
  }
}

final releasesProvider =
    NotifierProvider<ReleasesNotifier, ReleasesState>(ReleasesNotifier.new);

/// Télécharge le .torrent sur C411 et l'envoie à Transmission.
Future<void> sendToTransmission(
    BuildContext context, WidgetRef ref, Release release) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  final api = ref.read(c411Provider);
  final transmission = ref.read(transmissionProvider);
  if (api == null || transmission == null) {
    say('Configure C411 et Transmission dans les réglages');
    return;
  }
  say('Envoi de ${release.name}…');
  try {
    final bytes = await api.downloadTorrent(release.infoHash);
    final added = await transmission.addTorrent(metainfo: bytes);
    say(added
        ? 'Ajouté à Transmission : ${release.name}'
        : 'Déjà présent dans Transmission');
    await ref.read(torrentsProvider.notifier).refresh(full: true);
  } on C411Exception catch (e) {
    say(e.message);
  } on TransmissionException catch (e) {
    say(e.message);
  }
}
