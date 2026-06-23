import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/web/cache_buster.dart';
import '../../../shared/extensions/iterable_extensions.dart';
import '../../../shared/responsive/responsive.dart';
import '../../../shared/widgets/app_page_layout.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../cobros/presentation/cobros_providers.dart';
import '../../settings/presentation/app_settings_providers.dart';
import 'shell_nav_items.dart';
import 'shell_providers.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPath = GoRouterState.of(context).matchedLocation;
    final authRepository = ref.read(authRepositoryProvider);
    final branchesAsync = ref.watch(shellBranchOptionsProvider);
    final branchNameAsync = ref.watch(shellCurrentBranchNameProvider);
    final userAsync = ref.watch(shellUserInfoProvider);
    final accessAsync = ref.watch(shellAccessProfileProvider);
    final branches = branchesAsync.valueOrNull ?? const <ShellBranchOption>[];
    final branchName = branchNameAsync.valueOrNull ?? 'Sucursal principal';
    final userInfo = userAsync.valueOrNull;
    final effectiveRoleLabel =
        accessAsync.valueOrNull?.roleLabel ?? userInfo?.roleLabel;
    final visibleNavItemsAsync = ref.watch(shellVisibleNavItemsProvider);
    final visibleNavSectionsAsync = ref.watch(shellVisibleNavSectionsProvider);
    final visibleNavItems = visibleNavItemsAsync.valueOrNull ?? navItems;
    final visibleNavSections =
        visibleNavSectionsAsync.valueOrNull ?? navSections;
    final showSidebar = context.showDesktopSidebar;

    Future<void> signOut() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cerrar sesión'),
          content: const Text(
            '¿Seguro que querés cerrar la sesión? Si tenés una venta o '
            'cotización a medias sin guardar, se perderá.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: AppTokens.destructive,
              ),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Cerrar sesión'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      try {
        await authRepository.signOut();
        // En WEB: hard reload (limpia caches + service workers) para que el
        // próximo usuario arranque con un ProviderContainer 100% limpio. Sin
        // esto, providers sin autoDispose (dashboard, appSettings, etc.) podían
        // conservar los datos del usuario anterior — es caché del cliente, no
        // RLS. En nativo es no-op: ahí limpia el listener de authStateChanges.
        await clearWebCachesAndReload();
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo cerrar sesión: $error')),
          );
        }
      }
    }

    Future<void> selectBranch(String branchId) async {
      if (branchId.isEmpty) return;
      final messenger = ScaffoldMessenger.of(context);
      final current = branches.where((item) => item.isDefault).firstOrNull;
      if (current?.branchId == branchId) return;

      try {
        final client = ref.read(supabaseClientProvider);
        await client.rpc(
          'set_current_branch',
          params: {'target_branch_id': branchId},
        );
        invalidateBranchScopedData(ref);
        messenger.showSnackBar(
          const SnackBar(content: Text('Sucursal actualizada')),
        );
      } catch (error) {
        messenger.showSnackBar(
          SnackBar(content: Text('No se pudo cambiar sucursal: $error')),
        );
      }
    }

    final roleCode = accessAsync.valueOrNull?.roleCode ?? userInfo?.roleCode;
    final isAdmin = roleCode == 'admin';

    bool pathMatches(NavItem item, String path) {
      return path == item.path || path.startsWith('${item.path}/');
    }

    final currentNavItem = visibleNavItems
            .where((item) => pathMatches(item, currentPath))
            .firstOrNull ??
        navItems
            .where((item) => pathMatches(item, currentPath))
            .firstOrNull;

    // Visibilidad: admin nunca ve "Acceso restringido". Para los demás roles
    // un path es válido si coincide con (o desciende de) un nav item visible.
    // `/devoluciones` es una sub-pantalla del POS — hereda el acceso de
    // `/ventas`.
    final isCurrentPathVisible = isAdmin ||
        currentPath == '/panel' ||
        currentPath.startsWith('/panel/') ||
        visibleNavItems.any((item) => pathMatches(item, currentPath)) ||
        (currentPath == '/devoluciones' &&
            visibleNavItems.any((item) => item.path == '/ventas')) ||
        (currentPath.startsWith('/devoluciones/') &&
            visibleNavItems.any((item) => item.path == '/ventas'));
    final layoutMode = appPageLayoutModeForPath(currentPath);

    return Scaffold(
      drawer: showSidebar
          ? null
          : _MobileMenuDrawer(
              currentPath: currentPath,
              navSections: visibleNavSections,
              onNavigate: (path) {
                context.go(path);
                Navigator.of(context).pop();
              },
              onSignOut: signOut,
            ),
      body: Row(
        children: [
          if (showSidebar)
            _DesktopSidebar(
              currentPath: currentPath,
              navSections: visibleNavSections,
              onNavigate: context.go,
              onSignOut: signOut,
            ),
          Expanded(
            child: Scaffold(
              appBar: _TopBar(
                title: currentNavItem?.label ?? 'Shop+',
                currentPath: currentPath,
                branchName: branchName,
                branchOptions: branches,
                userInfo: userInfo,
                effectiveRoleLabel: effectiveRoleLabel,
                navSections: visibleNavSections,
                onSelectBranch: selectBranch,
                onSignOut: signOut,
              ),
              // SelectionArea permite seleccionar y copiar cualquier texto
              // dentro del shell (totales, NCF, IDs, etc.). Va aquí —no en
              // MaterialApp.builder— porque necesita un Overlay ancestral
              // y el Scaffold de arriba lo provee.
              body: SelectionArea(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: AppTokens.contentGradient,
                  ),
                  child: SafeArea(
                    top: false,
                    child: Stack(
                      children: [
                        AppPageLayout(
                          mode: layoutMode,
                          child: isCurrentPathVisible
                              ? child
                              : _RoleRestrictedView(
                                  onGoHome: () => context.go('/panel'),
                                ),
                        ),
                        // Notificación post-login: chequea cuántos créditos
                        // están por vencer y muestra un SnackBar una vez por
                        // sesión. No ocupa espacio en el layout.
                        Positioned.fill(child: const _LoginCreditAlert()),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget implements PreferredSizeWidget {
  const _TopBar({
    required this.title,
    required this.currentPath,
    required this.branchName,
    required this.branchOptions,
    required this.userInfo,
    required this.effectiveRoleLabel,
    required this.navSections,
    required this.onSelectBranch,
    required this.onSignOut,
  });

  final String title;
  final String currentPath;
  final String branchName;
  final List<ShellBranchOption> branchOptions;
  final ShellUserInfo? userInfo;
  final String? effectiveRoleLabel;
  final List<NavSection> navSections;
  final Future<void> Function(String branchId) onSelectBranch;
  final Future<void> Function() onSignOut;

  @override
  Size get preferredSize => const Size.fromHeight(64); // Slightly taller for more breathing room

  @override
  Widget build(BuildContext context) {
    final isMobile = !context.showDesktopSidebar;
    
    return AppBar(
      elevation: 0,
      backgroundColor: AppTokens.sidebarBackground,
      foregroundColor: AppTokens.sidebarForeground,
      surfaceTintColor: AppTokens.sidebarBackground,
      iconTheme: const IconThemeData(color: AppTokens.sidebarForeground),
      automaticallyImplyLeading: isMobile,
      centerTitle: false,
      title: Row(
        children: [
          if (!isMobile) ...[
            const SizedBox(width: AppTokens.s8),
          ],
          const Spacer(),
          _BranchSelector(
            currentBranchName: branchName,
            options: branchOptions,
            onSelect: onSelectBranch,
          ),
          const SizedBox(width: AppTokens.s16),
          _UserProfileMenu(
            userInfo: userInfo,
            effectiveRoleLabel: effectiveRoleLabel,
            onSignOut: onSignOut,
          ),
          const SizedBox(width: AppTokens.s8),
        ],
      ),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, color: AppTokens.sidebarBorder),
      ),
    );
  }
}

class _BranchSelector extends StatelessWidget {
  const _BranchSelector({
    required this.currentBranchName,
    required this.options,
    required this.onSelect,
  });

  final String currentBranchName;
  final List<ShellBranchOption> options;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: onSelect,
      tooltip: 'Cambiar sucursal',
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (context) => options.map((b) => PopupMenuItem(
        value: b.branchId,
        child: Row(
          children: [
            Icon(b.isDefault ? Icons.check_circle : Icons.storefront, size: 18, color: b.isDefault ? AppTokens.primary : AppTokens.mutedForeground),
            const SizedBox(width: 12),
            Text(b.name, style: TextStyle(fontWeight: b.isDefault ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      )).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTokens.sidebarAccent,
          borderRadius: BorderRadius.circular(AppTokens.radius),
          border: Border.all(color: AppTokens.sidebarBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.apartment_rounded,
              size: 18,
              color: AppTokens.sidebarForeground,
            ),
            const SizedBox(width: 8),
            Text(
              currentBranchName,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTokens.sidebarForeground,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: AppTokens.sidebarForeground,
            ),
          ],
        ),
      ),
    );
  }
}

class _UserProfileMenu extends StatelessWidget {
  const _UserProfileMenu({
    required this.userInfo,
    required this.effectiveRoleLabel,
    required this.onSignOut,
  });

  final ShellUserInfo? userInfo;
  final String? effectiveRoleLabel;
  final VoidCallback onSignOut;

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final name = userInfo?.displayName ?? '';
    final roleLabel = effectiveRoleLabel ?? userInfo?.roleLabel ?? '';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              name.isEmpty ? 'Usuario' : name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTokens.sidebarForeground,
              ),
            ),
            if (roleLabel.isNotEmpty)
              Text(
                roleLabel,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTokens.sidebarMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: AppTokens.primary,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: name.isEmpty
                ? const Icon(Icons.person_rounded, color: Colors.white, size: 20)
                : Text(
                    _initials(name),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: () => _confirmRefresh(context),
          icon: const Icon(
            Icons.refresh_rounded,
            size: 20,
            color: AppTokens.sidebarMuted,
          ),
          tooltip: 'Actualizar app (borrar caché)',
        ),
        IconButton(
          onPressed: onSignOut,
          icon: const Icon(
            Icons.logout_rounded,
            size: 20,
            color: AppTokens.sidebarMuted,
          ),
          tooltip: 'Cerrar sesión',
        ),
      ],
    );
  }

  Future<void> _confirmRefresh(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Actualizar aplicación'),
        content: const Text(
          'Esto limpia el caché del navegador y recarga la página '
          'para asegurar que tienes la versión más reciente. Tu sesión '
          'se mantiene abierta.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Actualizar ahora'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await clearWebCachesAndReload();
    }
  }
}


class _DesktopSidebar extends StatefulWidget {
  const _DesktopSidebar({
    required this.currentPath,
    required this.navSections,
    required this.onNavigate,
    required this.onSignOut,
  });

  final String currentPath;
  final List<NavSection> navSections;
  final ValueChanged<String> onNavigate;
  final Future<void> Function() onSignOut;

  @override
  State<_DesktopSidebar> createState() => _DesktopSidebarState();
}

class _DesktopSidebarState extends State<_DesktopSidebar> {
  static const double _collapsedWidth = 72;
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final width = _collapsed ? _collapsedWidth : AppTokens.sidebarWidth;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      width: width,
      decoration: const BoxDecoration(gradient: AppTokens.sidebarGradient),
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            const Divider(color: AppTokens.sidebarDivider, height: 1),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(
                  horizontal: _collapsed ? AppTokens.s6 : AppTokens.s12,
                  vertical: AppTokens.s12,
                ),
                children: [
                  for (final section in widget.navSections) ...[
                    if (!_collapsed) _SidebarSectionLabel(label: section.label),
                    if (!_collapsed) const SizedBox(height: AppTokens.s6),
                    for (final item in section.items)
                      _SidebarItem(
                        icon: item.icon,
                        label: item.label,
                        selected: item.path == widget.currentPath,
                        collapsed: _collapsed,
                        onTap: () => widget.onNavigate(item.path),
                      ),
                    const SizedBox(height: AppTokens.s12),
                  ],
                ],
              ),
            ),
            const Divider(color: AppTokens.sidebarDivider, height: 1),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: _collapsed ? AppTokens.s6 : AppTokens.s12,
                vertical: AppTokens.s10,
              ),
              child: _SidebarItem(
                icon: Icons.logout,
                label: 'Salir',
                selected: false,
                collapsed: _collapsed,
                onTap: () => widget.onSignOut(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final toggleButton = IconButton(
      icon: Icon(
        _collapsed ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
        color: Colors.white,
      ),
      tooltip: _collapsed ? 'Expandir' : 'Colapsar',
      onPressed: () => setState(() => _collapsed = !_collapsed),
    );

    if (_collapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s6,
          vertical: AppTokens.s12,
        ),
        child: Center(child: toggleButton),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.s22,
        AppTokens.s12,
        AppTokens.s8,
        AppTokens.s12,
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/shopplus_logo_white.png',
            height: 30,
            fit: BoxFit.contain,
          ),
          const Spacer(),
          toggleButton,
        ],
      ),
    );
  }
}

class _MobileMenuDrawer extends StatelessWidget {
  const _MobileMenuDrawer({
    required this.currentPath,
    required this.navSections,
    required this.onNavigate,
    required this.onSignOut,
  });

  final String currentPath;
  final List<NavSection> navSections;
  final ValueChanged<String> onNavigate;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: MediaQuery.sizeOf(context).width.clamp(280.0, 320.0).toDouble(),
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppTokens.sidebarGradient),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.s16,
                  AppTokens.s12,
                  AppTokens.s12,
                  AppTokens.s12,
                ),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/shopplus_logo_white.png',
                      height: 28,
                      fit: BoxFit.contain,
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Cerrar menú',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: AppTokens.sidebarDivider, height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppTokens.s8,
                    AppTokens.s12,
                    AppTokens.s8,
                    AppTokens.s12,
                  ),
                  children: [
                    for (final section in navSections) ...[
                      _SidebarSectionLabel(label: section.label),
                      const SizedBox(height: AppTokens.s6),
                      for (final item in section.items)
                        _SidebarItem(
                          icon: item.icon,
                          label: item.label,
                          selected: item.path == currentPath,
                          onTap: () => onNavigate(item.path),
                        ),
                      const SizedBox(height: AppTokens.s12),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.s8,
                  0,
                  AppTokens.s8,
                  AppTokens.s12,
                ),
                child: _SidebarItem(
                  icon: Icons.logout,
                  label: 'Salir',
                  selected: false,
                  onTap: () => onSignOut(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarSectionLabel extends StatelessWidget {
  const _SidebarSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.s14,
        AppTokens.s10,
        AppTokens.s14,
        AppTokens.s4,
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Color(0xCFFFFFFF),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Estado de notificación de créditos por sesión. `true` después de que el
/// SnackBar se haya mostrado al menos una vez en la sesión actual; se
/// resetea al cerrar sesión (cuando los providers `autoDispose` se reciclan).
final _loginAlertShownProvider = StateProvider<bool>((ref) => false);

/// Widget invisible que, al montarse por primera vez en la sesión, consulta
/// los créditos próximos a vencer y muestra un SnackBar discreto.
class _LoginCreditAlert extends ConsumerStatefulWidget {
  const _LoginCreditAlert();

  @override
  ConsumerState<_LoginCreditAlert> createState() => _LoginCreditAlertState();
}

class _LoginCreditAlertState extends ConsumerState<_LoginCreditAlert> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    if (!mounted) return;
    if (ref.read(_loginAlertShownProvider)) return;

    final settings = ref.read(appSettingsProvider).valueOrNull;
    if (settings == null) {
      // Settings aún no cargados — reintentar tras un breve delay.
      Future.delayed(const Duration(milliseconds: 600), _check);
      return;
    }
    final warnDays = settings.creditWarnDays;
    if (warnDays <= 0) return;

    try {
      final count = await ref
          .read(cobrosRepositoryProvider)
          .countCreditsNearDue(warnDays: warnDays);
      if (!mounted || count == 0) return;
      ref.read(_loginAlertShownProvider.notifier).state = true;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          backgroundColor: AppTokens.warning,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          width: 380,
          action: SnackBarAction(
            label: 'Ver',
            textColor: Colors.white,
            onPressed: () => context.go('/cobros'),
          ),
          content: Text(
            count == 1
                ? 'Tienes 1 cliente con crédito próximo a vencer.'
                : 'Tienes $count clientes con créditos próximos a vencer.',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    } catch (_) {
      // Silencioso: la notificación no es crítica.
    }
  }

  @override
  Widget build(BuildContext context) {
    // No ocupa espacio — IgnorePointer evita robarle clicks al contenido.
    return const IgnorePointer(child: SizedBox.shrink());
  }
}

class _RoleRestrictedView extends StatelessWidget {
  const _RoleRestrictedView({required this.onGoHome});

  final VoidCallback onGoHome;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.s24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCE8EC),
                      borderRadius: BorderRadius.circular(AppTokens.radiusL),
                    ),
                    child: const Icon(
                      Icons.lock_outline_rounded,
                      color: AppTokens.error,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: AppTokens.s16),
                  Text(
                    'Acceso restringido para este rol',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppTokens.s8),
                  Text(
                    'La navegación ya oculta este módulo según el rol activo. Usa el panel para continuar con acciones permitidas.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppTokens.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppTokens.s16),
                  FilledButton.icon(
                    onPressed: onGoHome,
                    icon: const Icon(Icons.grid_view_rounded),
                    label: const Text('Volver al panel'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.collapsed = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final content = Material(
      color: selected ? AppTokens.sidebarItemSelected : Colors.transparent,
      borderRadius: BorderRadius.circular(AppTokens.radiusL),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusL),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: collapsed ? AppTokens.s8 : AppTokens.s14,
            vertical: AppTokens.s12,
          ),
          child: collapsed
              ? Center(
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: AppTokens.iconSizeM,
                  ),
                )
              : Row(
                  children: [
                    Icon(icon, color: Colors.white, size: AppTokens.iconSizeM),
                    const SizedBox(width: AppTokens.s12),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s4),
      child: collapsed
          ? Tooltip(
              message: label,
              waitDuration: const Duration(milliseconds: 300),
              child: content,
            )
          : content,
    );
  }
}
