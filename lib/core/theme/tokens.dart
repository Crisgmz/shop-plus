import 'package:flutter/material.dart';

/// Centralized design tokens for Shop+.
///
/// Follows the SHOP_PLUS_RD_DISENO_COMPLETO.txt specifications.
abstract final class AppTokens {
  // ── Brand & Semantic Colors (Light Mode) ──────────────────────────────────
  static const primary = Color(0xFF0D6EFD); // HSL 217 91% 50%
  static const primaryForeground = Color(0xFFFFFFFF);
  
  static const background = Color(0xFFF8F9FA); // HSL 210 20% 98%
  static const foreground = Color(0xFF1D2631); // HSL 215 25% 15%
  
  static const card = Color(0xFFFFFFFF);
  static const cardForeground = Color(0xFF1D2631);
  
  static const secondary = Color(0xFFF1F3F5); // HSL 214 32% 95%
  static const secondaryForeground = Color(0xFF455468); // HSL 215 25% 27%
  
  static const muted = Color(0xFFF1F3F5);
  static const mutedForeground = Color(0xFF66798E); // HSL 215 16% 47%
  
  static const accent = Color(0xFFE9ECEF); // HSL 214 32% 91%
  static const accentForeground = Color(0xFF1D2631);
  
  static const destructive = Color(0xFFF03E3E); // HSL 0 84% 60%
  static const destructiveForeground = Color(0xFFFFFFFF);
  
  static const success = Color(0xFF21C463); // HSL 142 71% 45%
  static const successForeground = Color(0xFFFFFFFF);
  
  static const warning = Color(0xFFF59E0B); // HSL 38 92% 50%
  static const warningForeground = Color(0xFFFFFFFF);
  
  static const info = Color(0xFF1098AD); // HSL 199 89% 48%
  static const infoForeground = Color(0xFFFFFFFF);
  
  static const border = Color(0xFFE9ECEF); // HSL 214 32% 91%
  static const input = Color(0xFFE9ECEF);
  static const ring = Color(0xFF0D6EFD);

  // ── Sidebar (Always Dark) ─────────────────────────────────────────────────
  static const sidebarBackground = Color(0xFF052F6B); // HSL 217 91% 22%
  static const sidebarForeground = Color(0xFFE9ECEF); // HSL 214 32% 91%
  static const sidebarPrimary = Color(0xFFFFFFFF);
  static const sidebarPrimaryForeground = Color(0xFF052F6B);
  static const sidebarAccent = Color(0xFF074092); // HSL 217 91% 30%
  static const sidebarAccentForeground = Color(0xFFFFFFFF);
  static const sidebarBorder = Color(0xFF0B4DA8); // HSL 217 80% 30%
  static const sidebarRing = Color(0xFF3B82F6); // HSL 217 91% 60%
  static const sidebarMuted = Color(0xFF4B77BE); // HSL 217 60% 40%

  // ── Legacy Compatibility (Redundant but kept if used elsewhere) ───────────
  static const brandBlue = primary;
  static const brandBlueDark = sidebarBackground;
  static const brandBlueLight = Color(0xFF4C94FF);
  static const textPrimary = foreground;
  static const textSecondary = secondaryForeground;
  static const textMuted = mutedForeground;
  static const textDark = Color(0xFF1D2631);
  static const scaffold = background;
  static const cardBorder = border;
  static const divider = border;
  static const inputFill = secondary;
  static const error = destructive;
  static const sidebarOverlay = Color(0x0DFFFFFF);
  static const sidebarDivider = sidebarBorder;
  static const sidebarItemSelected = sidebarAccent;
  
  static const double avatarSize = 40;
  static const double breakpointSidebar = breakpointLarge;
  static const double breakpointUserInfo = breakpointLarge;
  static const double breakpointSearch = breakpointMedium;
  static const double contentMaxWidth = 1200;
  static const double contentWideMaxWidth = 1600;

  // ── Spacing scale (4-pt grid) ─────────────────────────────────────────────
  static const double s2 = 2;
  static const double s4 = 4;
  static const double s6 = 6;
  static const double s8 = 8;
  static const double s10 = 10;
  static const double s12 = 12;
  static const double s14 = 14;
  static const double s16 = 16;
  static const double s18 = 18;
  static const double s20 = 20;
  static const double s22 = 22;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s40 = 40;
  static const double s48 = 48;

  // ── Border radii ──────────────────────────────────────────────────────────
  static const double radius = 10; // 0.625rem = 10px
  static const double radiusS = 6;
  static const double radiusM = 10;
  static const double radiusL = 14;
  static const double radiusXL = 20;
  static const double radiusRound = 999;

  // ── Responsive breakpoints ────────────────────────────────────────────────
  static const double breakpointCompact = 640;
  static const double breakpointMedium = 768;
  static const double breakpointExpanded = 1024;
  static const double breakpointLarge = 1280;

  // ── Component sizes ───────────────────────────────────────────────────────
  static const double sidebarWidth = 260;
  static const double topBarHeight = 56; // h-14 = 3.5rem = 56px
  static const double iconSizeS = 14;    // h-3.5
  static const double iconSizeM = 16;    // h-4 (default sidebar)
  static const double iconSizeL = 20;    // h-5 (topbar/kpi)
  
  // ── Gradients ─────────────────────────────────────────────────────────────
  static const contentGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [background, background],
  );

  static const sidebarGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [sidebarBackground, sidebarBackground],
  );
}

