import 'package:flutter/material.dart';

/// Palette de l'application. Toutes les couleurs de l'UI viennent d'ici :
/// pour changer le style, c'est le seul endroit à modifier.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.text,
    required this.muted,
    required this.accent,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.download,
    required this.upload,
    required this.onAccent,
    required this.bubble,
    required this.quote,
    required this.toneBronze,
    required this.toneSilver,
    required this.toneGold,
  });

  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color text;
  final Color muted;
  final Color accent;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;

  /// Séries de données réception / envoi (graphiques, flèches de vitesse).
  /// Paire catégorielle validée (daltonisme, contraste) sur les deux fonds ;
  /// distincte des couleurs d'état (success…), qui gardent leur sens.
  final Color download;
  final Color upload;

  /// Texte et icônes posés sur l'accent (le vert C411 est trop clair pour du
  /// blanc : texte sombre, comme les boutons du site).
  final Color onAccent;

  /// Salon : bulles des messages et réponses citées.
  final Color bubble;
  final Color quote;

  /// Couleur des pseudos selon le rang (`nameTone` : bronze, argent, or).
  final Color toneBronze;
  final Color toneSilver;
  final Color toneGold;

  Color tone(String? nameTone) => switch (nameTone) {
        'argent' || 'silver' => toneSilver,
        'or' || 'gold' => toneGold,
        'bronze' => toneBronze,
        _ => text,
      };

  // Couleurs relevées sur c411.org.
  // Vert C411 en accent, sur un fond encre bleutée → vert profond.
  static const dark = AppColors(
    bg: Color(0xFF07141A),
    surface: Color(0xFF0E1D23),
    surfaceAlt: Color(0xFF16292E),
    border: Color(0xFF213840),
    text: Color(0xFFF1F8F6),
    muted: Color(0xFF97AFAB),
    accent: Color(0xFF00D492),
    // Vert d'eau et cyan, accordés au fond encre (plus de vert vif ni de violet).
    success: Color(0xFF3AAE8A),
    warning: Color(0xFFFFB900),
    danger: Color(0xFFF85245),
    info: Color(0xFF3BB4D4),
    download: Color(0xFF3987E5),
    upload: Color(0xFFD95926),
    onAccent: Color(0xFF04100C),
    bubble: Color(0xFF013226),
    quote: Color(0xFF01402F),
    toneBronze: Color(0xFFDB9153),
    toneSilver: Color(0xFFC3D0CA),
    toneGold: Color(0xFFFFB900),
  );

  static const light = AppColors(
    bg: Color(0xFFF2F7F4),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFE3EEE8),
    border: Color(0xFFD3E2DA),
    text: Color(0xFF0B1A14),
    muted: Color(0xFF4F6A5E),
    accent: Color(0xFF00855B),
    success: Color(0xFF1E8466),
    warning: Color(0xFFB27800),
    danger: Color(0xFFD63A2E),
    info: Color(0xFF0E86A3),
    download: Color(0xFF2A78D6),
    upload: Color(0xFFEB6834),
    onAccent: Color(0xFFFFFFFF),
    bubble: Color(0xFFE6F3EC),
    quote: Color(0xFFD3EBDF),
    toneBronze: Color(0xFFA8642B),
    toneSilver: Color(0xFF5F7069),
    toneGold: Color(0xFF9A6C00),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surfaceAlt: l(surfaceAlt, other.surfaceAlt),
      border: l(border, other.border),
      text: l(text, other.text),
      muted: l(muted, other.muted),
      accent: l(accent, other.accent),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      danger: l(danger, other.danger),
      info: l(info, other.info),
      download: l(download, other.download),
      upload: l(upload, other.upload),
      onAccent: l(onAccent, other.onAccent),
      bubble: l(bubble, other.bubble),
      quote: l(quote, other.quote),
      toneBronze: l(toneBronze, other.toneBronze),
      toneSilver: l(toneSilver, other.toneSilver),
      toneGold: l(toneGold, other.toneGold),
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

const _radius = 10.0;

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  final radius = BorderRadius.circular(_radius);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.onAccent,
    primaryContainer: c.accent.withValues(alpha: 0.15),
    onPrimaryContainer: c.accent,
    secondary: c.accent,
    onSecondary: c.onAccent,
    tertiary: c.info,
    onTertiary: Colors.white,
    error: c.danger,
    onError: Colors.white,
    errorContainer: c.danger.withValues(alpha: 0.12),
    onErrorContainer: c.danger,
    surface: c.bg,
    onSurface: c.text,
    onSurfaceVariant: c.muted,
    surfaceContainerLowest: c.bg,
    surfaceContainerLow: c.surface,
    surfaceContainer: c.surface,
    surfaceContainerHigh: c.surfaceAlt,
    surfaceContainerHighest: c.surfaceAlt,
    outline: c.border,
    outlineVariant: c.border,
    surfaceTint: Colors.transparent,
    shadow: Colors.black,
  );

  // Police intégrée à l'application (voir pubspec.yaml).
  const font = 'Inter';
  final text = ThemeData(brightness: brightness).textTheme
      .apply(fontFamily: font, bodyColor: c.text, displayColor: c.text)
      .copyWith(
        titleLarge: TextStyle(
          fontFamily: font,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: c.text,
        ),
        titleMedium: TextStyle(
          fontFamily: font,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: c.text,
        ),
        titleSmall: TextStyle(
          fontFamily: font,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: c.text,
        ),
        bodySmall: TextStyle(fontFamily: font, fontSize: 12, color: c.muted),
        labelSmall: TextStyle(
          fontFamily: font,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: c.muted,
        ),
      );

  WidgetStateProperty<Color?> selected(Color on, Color off) =>
      WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? on : off,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    extensions: [c],
    fontFamily: font,
    textTheme: text,
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    // Pas d'onde au clic : un simple voile au survol / appui.
    splashFactory: NoSplash.splashFactory,
    highlightColor: c.text.withValues(alpha: 0.05),
    hoverColor: c.text.withValues(alpha: 0.04),
    focusColor: c.accent.withValues(alpha: 0.12),
    // Mêmes tailles que sur ordinateur : Android agrandit sinon les zones
    // tactiles à 48 px (cases, interrupteurs, puces, boutons).
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      foregroundColor: c.text,
      // Icônes de la barre du haut plus grandes que celles des listes.
      actionsIconTheme: IconThemeData(size: 26, color: c.muted),
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
    ),
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceAlt,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: c.accent, width: 1.2),
      ),
      hintStyle: TextStyle(color: c.muted),
      labelStyle: TextStyle(color: c.muted),
      helperStyle: TextStyle(color: c.muted, fontSize: 11),
      prefixIconColor: c.muted,
      suffixIconColor: c.muted,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontFamily: font, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.text,
        side: BorderSide(color: c.border),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontFamily: font, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accent,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: c.muted,
        iconSize: 20,
        minimumSize: const Size(36, 36),
        padding: const EdgeInsets.all(6),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.surfaceAlt,
      selectedColor: c.accent,
      disabledColor: c.surfaceAlt,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      showCheckmark: false,
      // Les puces résolvent la *couleur* du libellé selon l'état (pas le
      // TextStyle entier) : la couleur doit donc être une WidgetStateColor.
      labelStyle: TextStyle(
        fontFamily: font,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: WidgetStateColor.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.onAccent : c.text,
        ),
      ),
      // Picto (avatar) à 8 px du bord et 4 px du libellé.
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      elevation: 0,
      height: 56,
      indicatorColor: Colors.transparent,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          size: 22,
          color: s.contains(WidgetState.selected) ? c.accent : c.muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: s.contains(WidgetState.selected) ? c.accent : c.muted,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: c.surface,
      indicatorColor: c.accent.withValues(alpha: 0.14),
      indicatorShape: RoundedRectangleBorder(borderRadius: radius),
      selectedIconTheme: IconThemeData(color: c.accent),
      unselectedIconTheme: IconThemeData(color: c.muted),
      selectedLabelTextStyle: TextStyle(
        color: c.accent,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: TextStyle(color: c.muted, fontSize: 12),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.accent,
      linearTrackColor: c.surfaceAlt,
      circularTrackColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surface,
      elevation: 8,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: c.border),
      ),
      textStyle: TextStyle(color: c.text, fontSize: 14),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.border),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.surfaceAlt,
      contentTextStyle: TextStyle(color: c.text),
      actionTextColor: c.accent,
      elevation: 0,
      width: 480,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: c.border),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: c.text,
      unselectedLabelColor: c.muted,
      labelStyle: const TextStyle(fontWeight: FontWeight.w600),
      indicatorColor: c.accent,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: c.border,
      tabAlignment: TabAlignment.start,
      overlayColor: WidgetStateProperty.all(Colors.transparent),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: selected(c.accent, c.border),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      thumbIcon: WidgetStateProperty.all(const Icon(null)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    checkboxTheme: CheckboxThemeData(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      fillColor: selected(c.accent, Colors.transparent),
      side: BorderSide(color: c.muted, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: selected(c.accent, c.surfaceAlt),
        foregroundColor: selected(c.onAccent, c.text),
        side: WidgetStateProperty.all(BorderSide.none),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: radius),
        ),
        overlayColor: WidgetStateProperty.all(Colors.transparent),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: c.muted,
      dense: true,
      visualDensity: VisualDensity.compact,
      minVerticalPadding: 4,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.text,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: TextStyle(color: c.bg, fontSize: 12),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.all(6),
      radius: const Radius.circular(3),
      thumbColor: WidgetStateProperty.all(c.muted.withValues(alpha: 0.4)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
    ),
  );
}

/// Panneau opaque à bord fin et coins arrondis (tuiles, blocs, barre de
/// navigation). Pas de transparence ni de flou : rien de coûteux à peindre.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.radius = 16});
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Une couche Material (et non une simple boîte peinte) : les lignes
    // cliquables (ListTile) y dessinent leur survol et leur appui.
    return Material(
      color: c.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: c.border),
      ),
      child: child,
    );
  }
}
