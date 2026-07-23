import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Fixed design tokens. The accent means "selection / focus" only — data
/// states (ok/warn/danger) never reuse it and stay constant across theme
/// colors so captioned/uncaptioned/error always read the same.
///
/// The neutral ramp (window/panel/raised/line/ink/muted) is no longer a
/// token set: it is derived from the chosen accent's hue in [AppPalette].
abstract final class AppTokens {
  // Dark
  static const darkAccent = Color(0xFF5CB8C4);
  static const darkOnAccent = Color(0xFF0E2A2E);
  static const darkOk = Color(0xFF6FBF73);
  static const darkWarn = Color(0xFFD9A23D);
  static const darkDanger = Color(0xFFD96B6B);

  // Light
  static const lightAccent = Color(0xFF2F8B98);
  static const lightOnAccent = Color(0xFFFFFFFF);
  static const lightOk = Color(0xFF3D8B46);
  static const lightWarn = Color(0xFFA86F14);
  static const lightDanger = Color(0xFFB34545);
}

/// Full neutral ramp + accent containers computed from one base color.
///
/// Strategy: keep the original blue-gray design's saturation/lightness
/// structure for every tone and swap in the accent's hue, so the whole
/// UI — window background, panels, cards, hairlines, secondary text —
/// takes on the theme color while contrast ratios stay as designed.
class AppPalette {
  const AppPalette._({
    required this.bg0,
    required this.bg1,
    required this.bg2,
    required this.line,
    required this.ink,
    required this.muted,
    required this.container,
    required this.onContainer,
  });

  /// Window background.
  final Color bg0;

  /// Side panels, bars, cards.
  final Color bg1;

  /// Raised surfaces (chips, inputs on panels).
  final Color bg2;

  /// Hairline borders.
  final Color line;

  /// Primary text.
  final Color ink;

  /// Secondary text.
  final Color muted;

  /// Accent-tinted fill for selected M3 containers (SegmentedButton,
  /// chips…) — clearly colored, but calmer than the accent itself.
  final Color container;

  /// Text/icon color on [container].
  final Color onContainer;

  factory AppPalette.derive(Color accentSeed, Brightness brightness) {
    final hue = HSLColor.fromColor(accentSeed).hue;
    Color tone(double sat, double light) =>
        HSLColor.fromAHSL(1, hue, sat, light).toColor();

    // S/L pairs transcribed from the original fixed tokens (hue ~222°),
    // so `tone` reproduces them exactly when given that hue.
    return brightness == Brightness.dark
        ? AppPalette._(
            bg0: tone(.15, .106), // was 0xFF17191F
            bg1: tone(.14, .137), // was 0xFF1E2128
            bg2: tone(.15, .175), // was 0xFF262A33
            line: tone(.14, .239), // was 0xFF343946
            ink: tone(.26, .931), // was 0xFFE9ECF2
            muted: tone(.13, .610), // was 0xFF8F97A8
            container: tone(.32, .295),
            onContainer: tone(.30, .920),
          )
        : AppPalette._(
            bg0: tone(.17, .943), // was 0xFFEEF0F3
            bg1: tone(.20, .980), // was 0xFFF9FAFB
            bg2: const Color(0xFFFFFFFF),
            line: tone(.18, .880), // was 0xFFDBDFE6
            ink: tone(.125, .157), // was 0xFF23262D
            muted: tone(.09, .459), // was 0xFF6A7280
            container: tone(.40, .870),
            onContainer: tone(.45, .180),
          );
  }
}

/// User-selectable accent (the theme "color"). Each choice carries the
/// bright variant used as `primary` in dark mode, the deeper variant for
/// light mode, and the matching `onAccent` ink for each — mirroring the
/// original teal token set. [swatch] is the mid-tone shown in the settings
/// picker so it reads on both light and dark cards.
///
/// Persist with [id] (a stable string); never store the enum index.
enum AppAccentChoice {
  teal(
    id: 'teal',
    swatch: Color(0xFF3AA5B0),
    darkAccent: AppTokens.darkAccent,
    darkOnAccent: AppTokens.darkOnAccent,
    lightAccent: AppTokens.lightAccent,
    lightOnAccent: AppTokens.lightOnAccent,
  ),
  blue(
    id: 'blue',
    swatch: Color(0xFF3E82C4),
    darkAccent: Color(0xFF5B9BD5),
    darkOnAccent: Color(0xFF0E1F30),
    lightAccent: Color(0xFF3070B0),
    lightOnAccent: Color(0xFFFFFFFF),
  ),
  indigo(
    id: 'indigo',
    swatch: Color(0xFF6E79D6),
    darkAccent: Color(0xFF8C9EEA),
    darkOnAccent: Color(0xFF141634),
    lightAccent: Color(0xFF4F5BC4),
    lightOnAccent: Color(0xFFFFFFFF),
  ),
  violet(
    id: 'violet',
    swatch: Color(0xFF9A5FCB),
    darkAccent: Color(0xFFB589E0),
    darkOnAccent: Color(0xFF261238),
    lightAccent: Color(0xFF8A4FC0),
    lightOnAccent: Color(0xFFFFFFFF),
  ),
  rose(
    id: 'rose',
    swatch: Color(0xFFCE5D80),
    darkAccent: Color(0xFFE07A9A),
    darkOnAccent: Color(0xFF34121E),
    lightAccent: Color(0xFFC04E72),
    lightOnAccent: Color(0xFFFFFFFF),
  ),
  green(
    id: 'green',
    swatch: Color(0xFF4CA378),
    darkAccent: Color(0xFF5FB98A),
    darkOnAccent: Color(0xFF0E2A1E),
    lightAccent: Color(0xFF3C8F63),
    lightOnAccent: Color(0xFFFFFFFF),
  );

  const AppAccentChoice({
    required this.id,
    required this.swatch,
    required this.darkAccent,
    required this.darkOnAccent,
    required this.lightAccent,
    required this.lightOnAccent,
  });

  final String id;
  final Color swatch;
  final Color darkAccent;
  final Color darkOnAccent;
  final Color lightAccent;
  final Color lightOnAccent;

  Color accentFor(Brightness b) =>
      b == Brightness.dark ? darkAccent : lightAccent;

  Color onAccentFor(Brightness b) =>
      b == Brightness.dark ? darkOnAccent : lightOnAccent;

  static AppAccentChoice fromId(String? id) => values.firstWhere(
        (c) => c.id == id,
        orElse: () => AppAccentChoice.teal,
      );
}

/// Data-state colors that must stay distinct from the accent.
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.ok,
    required this.warn,
    required this.panel,
    required this.raised,
    required this.line,
    required this.muted,
  });

  /// Captioned / tag applied.
  final Color ok;

  /// Uncaptioned / new tag.
  final Color warn;

  /// bg1: side panels, bars, cards.
  final Color panel;

  /// bg2: raised surfaces (chips, inputs on panels).
  final Color raised;

  /// Hairline borders.
  final Color line;

  /// Secondary text.
  final Color muted;

  @override
  AppSemanticColors copyWith({
    Color? ok,
    Color? warn,
    Color? panel,
    Color? raised,
    Color? line,
    Color? muted,
  }) {
    return AppSemanticColors(
      ok: ok ?? this.ok,
      warn: warn ?? this.warn,
      panel: panel ?? this.panel,
      raised: raised ?? this.raised,
      line: line ?? this.line,
      muted: muted ?? this.muted,
    );
  }

  @override
  AppSemanticColors lerp(AppSemanticColors? other, double t) {
    if (other == null) return this;
    return AppSemanticColors(
      ok: Color.lerp(ok, other.ok, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
      line: Color.lerp(line, other.line, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
    );
  }
}

extension AppSemanticColorsX on BuildContext {
  AppSemanticColors get semantic =>
      Theme.of(this).extension<AppSemanticColors>()!;
}

/// Monospace style for paths, counters and resolutions: aligned digits scan
/// faster than proportional ones.
TextStyle monoStyle(
  BuildContext context, {
  double size = 12,
  Color? color,
  FontWeight? weight,
}) {
  return TextStyle(
    fontFamily: 'Cascadia Mono',
    fontFamilyFallback: const [
      'Consolas',
      'SF Mono',
      'Menlo',
      'Roboto Mono',
      'monospace',
    ],
    fontFeatures: const [FontFeature.tabularFigures()],
    fontSize: size,
    color: color,
    fontWeight: weight,
  );
}

/// 各平台的中文回退链：默认字体缺字时落到系统中文字体（win 雅黑 /
/// mac 苹方 / linux Noto），"系统字体" 选项的表现也由此决定。
List<String> _cjkFallback() {
  if (kIsWeb) return const ['Noto Sans SC', 'sans-serif'];
  if (Platform.isMacOS) {
    return const ['PingFang SC', 'Heiti SC', 'Noto Sans SC'];
  }
  if (Platform.isLinux) {
    return const ['Noto Sans CJK SC', 'Noto Sans SC', 'WenQuanYi Micro Hei'];
  }
  return const ['Microsoft YaHei UI', 'Microsoft YaHei', 'Noto Sans SC'];
}

/// [fontFamily] 为 null 时用系统默认字体；否则用 FontLoader 注册的家族名。
/// [accent] 是主题基色：不仅决定强调色（选中/焦点），整套中性色阶也由
/// [AppPalette] 从它的色相派生,界面各处随之改变色调。
ThemeData buildAppTheme(
  Brightness brightness, {
  String? fontFamily,
  AppAccentChoice accent = AppAccentChoice.teal,
}) {
  final isDark = brightness == Brightness.dark;
  final accentColor = accent.accentFor(brightness);
  final onAccent = accent.onAccentFor(brightness);
  final palette = AppPalette.derive(accentColor, brightness);

  final semantic = AppSemanticColors(
    ok: isDark ? AppTokens.darkOk : AppTokens.lightOk,
    warn: isDark ? AppTokens.darkWarn : AppTokens.lightWarn,
    panel: palette.bg1,
    raised: palette.bg2,
    line: palette.line,
    muted: palette.muted,
  );

  // Container slots matter as much as primary: M3 widgets paint selected
  // states with them (SegmentedButton/FilterChip → secondaryContainer,
  // FAB → primaryContainer…). Leaving them at framework defaults is why a
  // theme-color change used to be barely visible.
  final scheme =
      (isDark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
    primary: accentColor,
    onPrimary: onAccent,
    secondary: accentColor,
    onSecondary: onAccent,
    tertiary: accentColor,
    onTertiary: onAccent,
    primaryContainer: palette.container,
    onPrimaryContainer: palette.onContainer,
    secondaryContainer: palette.container,
    onSecondaryContainer: palette.onContainer,
    tertiaryContainer: palette.container,
    onTertiaryContainer: palette.onContainer,
    surface: palette.bg0,
    onSurface: palette.ink,
    onSurfaceVariant: palette.muted,
    surfaceContainerLow: palette.bg1,
    surfaceContainerHigh: palette.bg2,
    surfaceTint: accentColor,
    outline: palette.line,
    outlineVariant: palette.line,
    error: isDark ? AppTokens.darkDanger : AppTokens.lightDanger,
    onError: isDark ? const Color(0xFF2A0E0E) : const Color(0xFFFFFFFF),
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    visualDensity: VisualDensity.compact,
    splashFactory: InkSparkle.splashFactory,
    fontFamily: fontFamily,
    fontFamilyFallback: _cjkFallback(),
  );

  return base.copyWith(
    extensions: [semantic],
    // DropdownButton 的弹出菜单以 canvasColor 为底；默认是 surface(bg0)，
    // 与 raised 卡片(bg2)不一致，暗色下会显得发黑。
    canvasColor: semantic.raised,
    dividerTheme: DividerThemeData(
      color: semantic.line,
      thickness: 1,
      space: 1,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      textStyle: TextStyle(fontSize: 12, color: scheme.surface),
      decoration: BoxDecoration(
        color: scheme.onSurface,
        borderRadius: BorderRadius.circular(6),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: scheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      hintStyle: TextStyle(color: semantic.muted, fontSize: 13),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide(color: semantic.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide(color: semantic.line),
      ),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 3,
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      activeTrackColor: scheme.primary,
      inactiveTrackColor: semantic.line,
      thumbColor: scheme.primary,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.all(6),
      radius: const Radius.circular(3),
    ),
  );
}
