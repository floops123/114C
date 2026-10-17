import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Défilement fluide à la molette (version PC).
///
/// Flutter fait sauter la liste d'un coup à chaque cran de molette. Ici, chaque
/// cran est étalé sur [duration] avec une décélération : on rejoue de petits
/// événements de molette, image par image, qui suivent le chemin normal (liste
/// sous le pointeur, rangée horizontale, page une fois au bout…). Les crans
/// rapprochés s'additionnent, ce qui donne de l'élan.
class WheelSmoother {
  WheelSmoother({
    required this.dispatch,
    this.duration = const Duration(milliseconds: 200),
    this.curve = Curves.easeOutCubic,
  });

  /// Envoie un événement de molette (synthétique) au framework.
  final void Function(PointerScrollEvent event) dispatch;
  final Duration duration;
  final Curve curve;

  PointerScrollEvent? _last;
  Offset _total = Offset.zero;
  Offset _sent = Offset.zero;
  Duration? _start;

  bool get active => _last != null;

  /// Nouveau cran : la distance restante s'ajoute au nouveau, et l'animation
  /// repart de zéro à la prochaine image.
  void add(PointerScrollEvent event) {
    _total = _total - _sent + event.scrollDelta;
    _sent = Offset.zero;
    _start = null;
    _last = event;
  }

  /// Avance l'animation à l'instant [now] ; renvoie false une fois terminée.
  bool tick(Duration now) {
    final last = _last;
    if (last == null) return false;
    final start = _start ??= now;
    final t = ((now - start).inMicroseconds / duration.inMicroseconds)
        .clamp(0.0, 1.0);
    final target = _total * curve.transform(t);
    final step = target - _sent;
    _sent = target;
    if (step != Offset.zero) {
      dispatch(PointerScrollEvent(
        timeStamp: now,
        kind: last.kind,
        device: last.device,
        position: last.position,
        viewId: last.viewId,
        scrollDelta: step,
      ));
    }
    if (t >= 1) {
      _last = null;
      _total = _sent = Offset.zero;
      return false;
    }
    return true;
  }
}

/// Binding de l'application : les crans de molette de la souris passent par
/// [WheelSmoother] ; le pavé tactile (déjà progressif) n'est pas concerné.
class SmoothWheelBinding extends WidgetsFlutterBinding {
  SmoothWheelBinding._();

  static WidgetsBinding ensureInitialized() {
    if (_instance == null) SmoothWheelBinding._();
    return WidgetsBinding.instance;
  }

  static SmoothWheelBinding? _instance;

  @override
  void initInstances() {
    super.initInstances();
    _instance = this;
  }

  late final _smoother = WheelSmoother(dispatch: super.handlePointerEvent);
  bool _scheduled = false;

  @override
  void handlePointerEvent(PointerEvent event) {
    if (event is PointerScrollEvent &&
        event.kind == PointerDeviceKind.mouse &&
        event.scrollDelta != Offset.zero) {
      _smoother.add(event);
      _schedule();
      return;
    }
    super.handlePointerEvent(event);
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    scheduleFrameCallback((now) {
      _scheduled = false;
      if (_smoother.tick(now)) _schedule();
    });
  }
}
