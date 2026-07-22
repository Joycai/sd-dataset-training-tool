import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Design tokens for the redesign. Two paired palettes; the accent (teal)
/// means "selection / focus" only — data states use the semantic colors in
/// [AppSemanticColors] and never reuse the accent.
abstract final class AppTokens {
  // Dark
  static const darkBg0 = Color(0xFF17191F); // window
  static const darkBg1 = Color(0xFF1E2128); // panels
  static const darkBg2 = Color(0xFF262A33); // raised
  static const darkLine = Color(0xFF343946);
  static const darkInk = Color(0xFFE9ECF2);
  static const darkMuted = Color(0xFF8F97A8);
  static const darkAccent = Color(0xFF5CB8C4);
  static const darkOnAccent = Color(0xFF0E2A2E);
  static const darkOk = Color(0xFF6FBF73);
  static const darkWarn = Color(0xFFD9A23D);
  static const darkDanger = Color(0xFFD96B6B);

  // Light
  static const lightBg0 = Color(0xFFEEF0F3);
  static const lightBg1 = Color(0xFFF9FAFB);
  static const lightBg2 = Color(0xFFFFFFFF);
  static const lightLine = Color(0xFFDBDFE6);
  static const lightInk = Color(0xFF23262D);
  static const lightMuted = Color(0xFF6A7280);
  static const lightAccent = Color(0xFF2F8B98);
  static const lightOnAccent = Color(0xFFFFFFFF);
  static const lightOk = Color(0xFF3D8B46);
  static const lightWarn = Color(0xFFA86F14);
  static const lightDanger = Color(0xFFB34545);
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

  static const dark = AppSemanticColors(
    ok: AppTokens.darkOk,
    warn: AppTokens.darkWarn,
    panel: AppTokens.darkBg1,
    raised: AppTokens.darkBg2,
    line: AppTokens.darkLine,
    muted: AppTokens.darkMuted,
  );

  static const light = AppSemanticColors(
    ok: AppTokens.lightOk,
    warn: AppTokens.lightWarn,
    panel: AppTokens.lightBg1,
    raised: AppTokens.lightBg2,
    line: AppTokens.lightLine,
    muted: AppTokens.lightMuted,
  );

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
ThemeData buildAppTheme(Brightness brightness, {String? fontFamily}) {
  final isDark = brightness == Brightness.dark;
  final semantic = isDark ? AppSemanticColors.dark : AppSemanticColors.light;

  final scheme = isDark
      ? const ColorScheme.dark(
          primary: AppTokens.darkAccent,
          onPrimary: AppTokens.darkOnAccent,
          secondary: AppTokens.darkAccent,
          onSecondary: AppTokens.darkOnAccent,
          surface: AppTokens.darkBg0,
          onSurface: AppTokens.darkInk,
          onSurfaceVariant: AppTokens.darkMuted,
          surfaceContainerLow: AppTokens.darkBg1,
          surfaceContainerHigh: AppTokens.darkBg2,
          outline: AppTokens.darkLine,
          outlineVariant: AppTokens.darkLine,
          error: AppTokens.darkDanger,
          onError: Color(0xFF2A0E0E),
        )
      : const ColorScheme.light(
          primary: AppTokens.lightAccent,
          onPrimary: AppTokens.lightOnAccent,
          secondary: AppTokens.lightAccent,
          onSecondary: AppTokens.lightOnAccent,
          surface: AppTokens.lightBg0,
          onSurface: AppTokens.lightInk,
          onSurfaceVariant: AppTokens.lightMuted,
          surfaceContainerLow: AppTokens.lightBg1,
          surfaceContainerHigh: AppTokens.lightBg2,
          outline: AppTokens.lightLine,
          outlineVariant: AppTokens.lightLine,
          error: AppTokens.lightDanger,
          onError: Color(0xFFFFFFFF),
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
