import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

  static const dark = AppColors(
    bg: Color(0xFF0B0E14),
    surface: Color(0xFF131823),
    surfaceAlt: Color(0xFF1B2130),
    border: Color(0xFF252C3B),
    text: Color(0xFFE7EAF0),
    muted: Color(0xFF8B94A7),
    accent: Color(0xFF4C8DFF),
    success: Color(0xFF22C55E),
    warning: Color(0xFFF59E0B),
    danger: Color(0xFFEF4444),
    info: Color(0xFFA78BFA),
  );

  static const light = AppColors(
    bg: Color(0xFFF5F6F8),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFECEEF2),
    border: Color(0xFFE1E4EA),
    text: Color(0xFF12151C),
    muted: Color(0xFF5E6676),
    accent: Color(0xFF2563EB),
    success: Color(0xFF16A34A),
    warning: Color(0xFFD97706),
    danger: Color(0xFFDC2626),
    info: Color(0xFF7C3AED),
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
    onPrimary: Colors.white,
    primaryContainer: c.accent.withValues(alpha: 0.15),
    onPrimaryContainer: c.accent,
    secondary: c.accent,
    onSecondary: Colors.white,
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

  // On ne prend que la famille : l'API TextTheme de google_fonts 9 repose sur
  // le paquet material_ui, incompatible avec le TextTheme de Flutter.
  final font = GoogleFonts.inter().fontFamily;
  final text = ThemeData(brightness: brightness)
      .textTheme
      .apply(fontFamily: font, bodyColor: c.text, displayColor: c.text)
      .copyWith(
        titleLarge: GoogleFonts.inter(
            fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: c.text),
        titleMedium: GoogleFonts.inter(
            fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: c.text),
        titleSmall: GoogleFonts.inter(
            fontSize: 14, fontWeight: FontWeight.w600, color: c.text),
        bodySmall: GoogleFonts.inter(fontSize: 12, color: c.muted),
        labelSmall: GoogleFonts.inter(
            fontSize: 11, fontWeight: FontWeight.w600, color: c.muted),
      );

  WidgetStateProperty<Color?> selected(Color on, Color off) =>
      WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? on : off);

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
    visualDensity: VisualDensity.compact,
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      foregroundColor: c.text,
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
          side: BorderSide(color: c.border)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceAlt,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      enabledBorder:
          OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: radius, borderSide: BorderSide(color: c.accent, width: 1.2)),
      hintStyle: TextStyle(color: c.muted),
      labelStyle: TextStyle(color: c.muted),
      helperStyle: TextStyle(color: c.muted, fontSize: 11),
      prefixIconColor: c.muted,
      suffixIconColor: c.muted,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.text,
        side: BorderSide(color: c.border),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
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
      labelStyle: WidgetStateTextStyle.resolveWith((s) => TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: s.contains(WidgetState.selected) ? Colors.white : c.text,
          )),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      elevation: 0,
      height: 62,
      indicatorColor: Colors.transparent,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? c.accent : c.muted)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: s.contains(WidgetState.selected) ? c.accent : c.muted,
          )),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: c.surface,
      indicatorColor: c.accent.withValues(alpha: 0.14),
      indicatorShape: RoundedRectangleBorder(borderRadius: radius),
      selectedIconTheme: IconThemeData(color: c.accent),
      unselectedIconTheme: IconThemeData(color: c.muted),
      selectedLabelTextStyle: TextStyle(
          color: c.accent, fontSize: 12, fontWeight: FontWeight.w600),
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
          borderRadius: radius, side: BorderSide(color: c.border)),
      textStyle: TextStyle(color: c.text, fontSize: 14),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: c.border)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.surfaceAlt,
      contentTextStyle: TextStyle(color: c.text),
      actionTextColor: c.accent,
      elevation: 0,
      width: 480,
      shape: RoundedRectangleBorder(
          borderRadius: radius, side: BorderSide(color: c.border)),
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
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: selected(c.accent, Colors.transparent),
      side: BorderSide(color: c.muted, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: selected(c.accent, c.surfaceAlt),
        foregroundColor: selected(Colors.white, c.text),
        side: WidgetStateProperty.all(BorderSide.none),
        shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: radius)),
        overlayColor: WidgetStateProperty.all(Colors.transparent),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: c.muted,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
          color: c.text, borderRadius: BorderRadius.circular(6)),
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    ),
  );
}
