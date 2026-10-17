import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/tracker.dart';
import '../api/transmission.dart';
import '../core/preferences.dart';
import 'torrents.dart';

class ReleaseFilter {
  const ReleaseFilter({
    this.categoryId,
    this.subcategoryId,
    this.query = '',
    this.sort = ReleaseSort.date,
    this.ascending = false,
  });

  final int? categoryId;
  final int? subcategoryId;
  final String query;
  final ReleaseSort sort;
  final bool ascending;

  ReleaseFilter copyWith({
    int? Function()? categoryId,
    int? Function()? subcategoryId,
    String? query,
    ReleaseSort? sort,
    bool? ascending,
  }) =>
      ReleaseFilter(
        categoryId: categoryId != null ? categoryId() : this.categoryId,
        subcategoryId:
            subcategoryId != null ? subcategoryId() : this.subcategoryId,
        query: query ?? this.query,
        sort: sort ?? this.sort,
        ascending: ascending ?? this.ascending,
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

/// Tracker affiché dans l'onglet Sorties (mémorisé entre les lancements).
class SelectedTrackerNotifier extends Notifier<Tracker?> {
  static const prefKey = 'tracker';

  @override
  Tracker? build() {
    final trackers = ref.watch(trackersProvider);
    if (trackers.isEmpty) return null;
    final saved = Tracker.values
        .asNameMap()[ref.read(sharedPrefsProvider).getString(prefKey)];
    return trackers.containsKey(saved) ? saved : trackers.keys.first;
  }

  void select(Tracker tracker) {
    ref.read(sharedPrefsProvider).setString(prefKey, tracker.name);
    state = tracker;
  }
}

final selectedTrackerProvider =
    NotifierProvider<SelectedTrackerNotifier, Tracker?>(
        SelectedTrackerNotifier.new);

final currentTrackerApiProvider = Provider<TrackerApi?>((ref) {
  final tracker = ref.watch(selectedTrackerProvider);
  return tracker == null ? null : ref.watch(trackersProvider)[tracker];
});

final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  final api = ref.watch(currentTrackerApiProvider);
  if (api == null) return const [];
  return api.categories();
});

class ReleasesNotifier extends Notifier<ReleasesState> {
  int _generation = 0;

  @override
  ReleasesState build() {
    // Changer de tracker repart d'un filtre vide : les catégories diffèrent.
    final api = ref.watch(currentTrackerApiProvider);
    // Tri mémorisé, s'il est proposé par ce tracker.
    final prefs = ref.read(uiPrefsProvider);
    final sort = ReleaseSort.values.asNameMap()[prefs.releaseSort];
    Future.microtask(loadMore);
    return ReleasesState(
      filter: sort != null && (api?.sorts.contains(sort) ?? false)
          ? ReleaseFilter(sort: sort, ascending: prefs.releaseAscending)
          : const ReleaseFilter(),
    );
  }

  void setSort(ReleaseSort sort, bool ascending) {
    ref.read(uiPrefsProvider.notifier).setReleaseSort(sort.name, ascending);
    final api = ref.read(currentTrackerApiProvider);
    final filter = state.filter.copyWith(sort: sort, ascending: ascending);
    // Tri local : inutile de recharger, l'affichage trie les résultats chargés.
    if (api != null && !api.serverSorts.contains(sort) &&
        !api.serverSorts.contains(state.filter.sort)) {
      state = ReleasesState(
        filter: filter,
        items: state.items,
        page: state.page,
        totalPages: state.totalPages,
        total: state.total,
        loading: state.loading,
        error: state.error,
      );
    } else {
      setFilter(filter);
    }
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
    final api = ref.read(currentTrackerApiProvider);
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
        sort: f.sort,
        ascending: f.ascending,
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
    } on TrackerException catch (e) {
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

/// Récupère le .torrent sur le tracker de la sortie et l'envoie à Transmission.
Future<void> sendToTransmission(
  BuildContext context,
  WidgetRef ref,
  Release release, {
  AddOptions options = const AddOptions(),
}) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  final api = ref.read(trackersProvider)[release.tracker];
  final transmission = ref.read(transmissionProvider);
  if (api == null || transmission == null) {
    say('Configure ${release.tracker.label} et Transmission dans les réglages');
    return;
  }
  try {
    final link = release.downloadUrl;
    final added = link != null && link.startsWith('magnet:')
        ? await transmission.addTorrent(filename: link, options: options)
        : await transmission.addTorrent(
            metainfo: await api.downloadTorrent(release), options: options);
    say(added
        ? 'Ajouté à Transmission : ${release.name}'
        : 'Déjà présent dans Transmission');
    await ref.read(torrentsProvider.notifier).refresh(full: true);
  } on TrackerException catch (e) {
    say(e.message);
  } on TransmissionException catch (e) {
    say(e.message);
  }
}
