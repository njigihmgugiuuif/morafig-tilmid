import 'package:flutter/material.dart';

/// Visual identity of «مرافق التلميذ» (D-1 · DS1 الهوية).
///
/// One palette per brightness, registered on the ThemeData as an extension
/// so every widget reads its colours through `context.mq` and the light and
/// dark themes are two values of the same thing, not two designs.
///
/// Colour meaning (DS1): teal = calm and focus; amber = «الآن», the moment of
/// decision, used sparingly; coral = lateness, never blame; indigo = memory;
/// green = success. Subjects get one of six tones, always paired with text
/// or an icon, never colour alone.
@immutable
class MqSubjectTone {
  const MqSubjectTone(this.color, this.soft);
  final Color color;
  final Color soft;
}

@immutable
class MqPalette extends ThemeExtension<MqPalette> {
  const MqPalette({
    required this.isDark,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.line,
    required this.brand,
    required this.brandDeep,
    required this.brandSoft,
    required this.onBrand,
    required this.accent,
    required this.accentSoft,
    required this.accentInk,
    required this.ok,
    required this.okSoft,
    required this.overdue,
    required this.overdueSoft,
    required this.info,
    required this.infoSoft,
    required this.subjects,
    required this.cardShadow,
  });

  final bool isDark;
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color line;
  final Color brand;
  final Color brandDeep;
  final Color brandSoft;
  final Color onBrand;
  final Color accent;
  final Color accentSoft;
  final Color accentInk;
  final Color ok;
  final Color okSoft;
  final Color overdue;
  final Color overdueSoft;
  final Color info;
  final Color infoSoft;
  final List<MqSubjectTone> subjects;
  final List<BoxShadow> cardShadow;

  static const MqPalette light = MqPalette(
    isDark: false,
    bg: Color(0xFFF4F6F9),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFEBF0F5),
    ink: Color(0xFF0C1A2B),
    ink2: Color(0xFF41526A),
    ink3: Color(0xFF5C6C80),
    line: Color(0xFFDEE5ED),
    brand: Color(0xFF0A6B6B),
    brandDeep: Color(0xFF064B4D),
    brandSoft: Color(0xFFDAF0EE),
    onBrand: Color(0xFFFFFFFF),
    accent: Color(0xFFF5A524),
    accentSoft: Color(0xFFFFF0D2),
    accentInk: Color(0xFF7A4A00),
    ok: Color(0xFF16764C),
    okSoft: Color(0xFFDCF2E7),
    overdue: Color(0xFFB8420F),
    overdueSoft: Color(0xFFFDE6DA),
    info: Color(0xFF3F3BC4),
    infoSoft: Color(0xFFE7E7FB),
    subjects: [
      MqSubjectTone(Color(0xFF1D4ED8), Color(0xFFE4EDFD)),
      MqSubjectTone(Color(0xFF6D28D9), Color(0xFFEEE6FB)),
      MqSubjectTone(Color(0xFF15803D), Color(0xFFDFF3E5)),
      MqSubjectTone(Color(0xFFB45309), Color(0xFFFCEBD3)),
      MqSubjectTone(Color(0xFFBE185D), Color(0xFFFBE3EE)),
      MqSubjectTone(Color(0xFF0E7490), Color(0xFFDCF1F6)),
    ],
    cardShadow: [
      BoxShadow(
          color: Color(0x0F0C1A2B), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(
          color: Color(0x0F0C1A2B), blurRadius: 18, offset: Offset(0, 6)),
    ],
  );

  static const MqPalette dark = MqPalette(
    isDark: true,
    bg: Color(0xFF09121F),
    surface: Color(0xFF111D2E),
    surface2: Color(0xFF182740),
    ink: Color(0xFFEAF1F8),
    ink2: Color(0xFFB0BED0),
    ink3: Color(0xFF8FA0B5),
    line: Color(0xFF22344B),
    brand: Color(0xFF45CFC6),
    brandDeep: Color(0xFF0E3B3D),
    brandSoft: Color(0xFF133E40),
    onBrand: Color(0xFF06302F),
    accent: Color(0xFFF7B84A),
    accentSoft: Color(0xFF3A2C10),
    accentInk: Color(0xFFF7C873),
    ok: Color(0xFF4FD39A),
    okSoft: Color(0xFF133A2B),
    overdue: Color(0xFFFF9A6B),
    overdueSoft: Color(0xFF3C2016),
    info: Color(0xFFA4A1FF),
    infoSoft: Color(0xFF25244F),
    subjects: [
      MqSubjectTone(Color(0xFF8FB0FF), Color(0xFF172A57)),
      MqSubjectTone(Color(0xFFBFA2FF), Color(0xFF2A2050)),
      MqSubjectTone(Color(0xFF6FDC93), Color(0xFF14341F)),
      MqSubjectTone(Color(0xFFF5B96B), Color(0xFF3A2810)),
      MqSubjectTone(Color(0xFFFF9CC4), Color(0xFF40142B)),
      MqSubjectTone(Color(0xFF6FD6EE), Color(0xFF10333D)),
    ],
    cardShadow: [],
  );

  /// The tone of a subject. Deterministic (same name -> same tone on every
  /// run and platform) and carrying no meaning: it only tells subjects apart.
  MqSubjectTone toneFor(String subjectName) {
    var sum = 0;
    for (final unit in subjectName.trim().codeUnits) {
      sum = (sum * 31 + unit) & 0x7fffffff;
    }
    return subjects[sum % subjects.length];
  }

  @override
  MqPalette copyWith() => this;

  @override
  MqPalette lerp(ThemeExtension<MqPalette>? other, double t) {
    if (other is! MqPalette) return this;
    return t < 0.5 ? this : other;
  }
}

extension MqContext on BuildContext {
  /// The palette of the active theme.
  MqPalette get mq =>
      Theme.of(this).extension<MqPalette>() ?? MqPalette.light;
}

/// Spacing, radii and sizes (DS1: grid 4px, screen margin 16, button 48,
/// card radius 20, sheet 28, touch target 44).
class MqSpace {
  MqSpace._();
  static const double screen = 16;
  static const double gap = 12;
  static const double radiusButton = 14;
  static const double radiusCard = 20;
  static const double radiusHero = 24;
  static const double radiusSheet = 28;
  static const double touch = 44;
  static const double navHeight = 76;
}

/// Motion: short, purposeful. Every duration passes through [MqMotion.of] so
/// a device that asks for reduced motion gets none.
class MqMotion {
  MqMotion._();
  static const Duration quick = Duration(milliseconds: 140);
  static const Duration base = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 520);
  static const Curve enter = Curves.easeOutCubic;
  static const Curve spring = Curves.easeOutBack;

  /// [d], or zero when the platform asks for reduced motion.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.of(context).disableAnimations ? Duration.zero : d;
}

/// Typography. Display / numbers use the display family, text the text
/// family (DS1: Readex Pro and IBM Plex Sans Arabic). Neither is bundled yet
/// — adding the font files needs a pubspec change, which is an open decision
/// — so until then the platform's Arabic font renders; the sizes, weights and
/// hierarchy below are what carry the look.
class MqType {
  MqType._();

  static const String displayFamily = 'Readex Pro';
  static const String textFamily = 'IBM Plex Sans Arabic';
  static const List<String> fallback = ['Noto Sans Arabic', 'sans-serif'];

  static const TextStyle display = TextStyle(
    fontFamily: displayFamily,
    fontFamilyFallback: fallback,
    fontSize: 34,
    height: 1.25,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle h1 = TextStyle(
    fontFamily: displayFamily,
    fontFamilyFallback: fallback,
    fontSize: 26,
    height: 1.35,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle h2 = TextStyle(
    fontFamily: displayFamily,
    fontFamilyFallback: fallback,
    fontSize: 18,
    height: 1.4,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle h3 = TextStyle(
    fontFamily: displayFamily,
    fontFamilyFallback: fallback,
    fontSize: 15,
    height: 1.5,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle body = TextStyle(
    fontFamily: textFamily,
    fontFamilyFallback: fallback,
    fontSize: 15,
    height: 1.6,
  );
  static const TextStyle small = TextStyle(
    fontFamily: textFamily,
    fontFamilyFallback: fallback,
    fontSize: 13,
    height: 1.55,
  );
  static const TextStyle caption = TextStyle(
    fontFamily: textFamily,
    fontFamilyFallback: fallback,
    fontSize: 12,
    height: 1.5,
  );
  static const TextStyle label = TextStyle(
    fontFamily: textFamily,
    fontFamilyFallback: fallback,
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );

  /// Figures: tabular, so a changing number does not jitter.
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];
}
