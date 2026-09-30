import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/extensions/iterable_extensions.dart';
import '../../../shared/responsive/responsive_layout.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../../../shared/widgets/ui_custom.dart';
import '../../permissions/data/permissions_repository.dart';
import '../../permissions/presentation/permissions_providers.dart';
import '../data/users_repository.dart';
import 'users_providers.dart';

const _roles = <String, String>{
  'admin': 'Administrador',
  'supervisor': 'Supervisor',
  'cashier': 'Cajero',
  'accountant': 'Contador',
};

// Orden y presentación de módulos en la sección de permisos efectivos.
const _moduleOrder = <String>[
  'dashboard',
  'sales',
  'clients',
  'inventory',
  'purchases',
  'cash',
  'reports',
  'employees',
  'settings',
  'ncf',
];

const _moduleLabels = <String, String>{
  'dashboard': 'Panel',
  'sales': 'Ventas',
  'clients': 'Clientes',
  'inventory': 'Inventario',
  'purchases': 'Compras',
  'cash': 'Caja',
  'reports': 'Reportes',
  'employees': 'Empleados',
  'settings': 'Configuración',
  'ncf': 'Comprobantes fiscales',
};

const _moduleIcons = <String, IconData>{
  'dashboard': Icons.dashboard_outlined,
  'sales': Icons.point_of_sale_outlined,
  'clients': Icons.people_outline,
  'inventory': Icons.inventory_2_outlined,
  'purchases': Icons.shopping_cart_outlined,
  'cash': Icons.savings_outlined,
  'reports': Icons.bar_chart_outlined,
  'employees': Icons.badge_outlined,
  'settings': Icons.settings_outlined,
  'ncf': Icons.receipt_long_outlined,
};

class UsersPage extends ConsumerStatefulWidget {
  const UsersPage({super.key});

  @override
  ConsumerState<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends ConsumerState<UsersPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(usersListProvider);
    final query = ref.watch(usersSearchProvider).trim().toLowerCase();
    final showInactive = ref.watch(usersShowInactiveProvider);
    final selectedUserId = ref.watch(selectedUserIdProvider);

    return ModulePage(
      title: 'Usuarios',
      description: 'Roles, estado y sucursales por usuario.',
      actions: [
        OutlinedButton.icon(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
        const SizedBox(width: AppTokens.s8),
        FilledButton.icon(
          onPressed: _onCreateUser,
          icon: const Icon(Icons.person_add_outlined, size: 18),
          label: const Text('Crear usuario'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFilterBar(showInactive),
          const SizedBox(height: AppTokens.s24),
          usersAsync.when(
            data: (users) {
              final filtered = users
                  .where((user) {
                    if (!showInactive && !user.isActive) return false;
                    if (query.isEmpty) return true;
                    final haystack = [
                      user.fullName,
                      user.email ?? '',
                      _roleLabel(user.role),
                    ].join(' ').toLowerCase();
                    return haystack.contains(query);
                  })
                  .toList(growable: false);

              if (filtered.isNotEmpty &&
                  (selectedUserId == null ||
                      !filtered.any((item) => item.id == selectedUserId))) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  ref.read(selectedUserIdProvider.notifier).state =
                      filtered.first.id;
                });
              }

              final selectedUser = filtered
                  .where((item) => item.id == selectedUserId)
                  .firstOrNull;

              return Column(
                children: [
                  _UsersKpis(users: filtered),
                  const SizedBox(height: AppTokens.s24),
                  _usersTableCard(
                    filtered: filtered,
                    selectedUserId: selectedUserId,
                  ),
                  const SizedBox(height: AppTokens.s24),
                  _userBranchesCard(selectedUser: selectedUser),
                  const SizedBox(height: AppTokens.s24),
                  _UserPermissionsPanel(selectedUser: selectedUser),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => ErrorCard(
              message:
                  'No se pudieron cargar usuarios: ${friendlyErrorMessage(error)}',
              onRetry: _refresh,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(bool showInactive) {
    final isMobile = ResponsiveLayout.isMobile(context);

    final searchField = TextField(
      controller: _searchController,
      onChanged: (value) =>
          ref.read(usersSearchProvider.notifier).state = value,
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search, size: 18),
        hintText: 'Buscar por nombre, email o rol',
      ),
    );

    final filterChip = FilterChip(
      selected: showInactive,
      label: const Text('Mostrar inactivos'),
      onSelected: (value) =>
          ref.read(usersShowInactiveProvider.notifier).state = value,
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          searchField,
          const SizedBox(height: AppTokens.s12),
          filterChip,
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: searchField),
        const SizedBox(width: AppTokens.s12),
        filterChip,
      ],
    );
  }

  Widget _usersTableCard({
    required List<UserEntity> filtered,
    required String? selectedUserId,
  }) {
    return DataTableShell(
      title: 'Listado de usuarios (${filtered.length})',
      child: filtered.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(AppTokens.s20),
              child: Text(
                'No hay usuarios que coincidan con el filtro.',
                style: TextStyle(color: AppTokens.mutedForeground),
              ),
            )
          : DataTable(
              columns: const [
                DataColumn(label: Text('Nombre')),
                DataColumn(label: Text('Email')),
                DataColumn(label: Text('Rol')),
                DataColumn(label: Text('Teléfono')),
                DataColumn(label: Text('Sucursales'), numeric: true),
                DataColumn(label: Text('Estado')),
                DataColumn(label: Text('Acciones')),
              ],
              rows: filtered
                  .map(
                    (user) => DataRow(
                      selected: user.id == selectedUserId,
                      onSelectChanged: (_) =>
                          ref.read(selectedUserIdProvider.notifier).state =
                              user.id,
                      cells: [
                        DataCell(
                          Text(
                            user.fullName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        DataCell(Text(user.email ?? '-')),
                        DataCell(Text(_roleLabel(user.role))),
                        DataCell(Text(user.phone ?? '-')),
                        DataCell(Text(user.activeBranchCount.toString())),
                        DataCell(
                          StatusBadge(
                            label: user.isActive ? 'Activo' : 'Inactivo',
                            status: user.isActive ? 'active' : 'inactive',
                          ),
                        ),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Editar',
                                onPressed: () => _onEditUser(user),
                                icon: const Icon(
                                  Icons.edit_outlined,
                                  size: AppTokens.iconSizeS,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                              IconButton(
                                tooltip: user.isActive
                                    ? 'Desactivar'
                                    : 'Activar',
                                onPressed: () => _onToggleActive(user),
                                icon: Icon(
                                  user.isActive
                                      ? Icons.block_outlined
                                      : Icons.check_circle_outline,
                                  size: AppTokens.iconSizeS,
                                  color: user.isActive
                                      ? AppTokens.destructive
                                      : AppTokens.success,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                              IconButton(
                                tooltip: 'Eliminar',
                                onPressed: () => _onDeleteUser(user),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: AppTokens.iconSizeS,
                                  color: AppTokens.destructive,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(growable: false),
            ),
    );
  }

  Widget _userBranchesCard({required UserEntity? selectedUser}) {
    return DataTableShell(
      title: selectedUser == null
          ? 'Sucursales del usuario'
          : 'Sucursales de ${selectedUser.fullName}',
      scrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.s20,
              AppTokens.s12,
              AppTokens.s20,
              0,
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: selectedUser == null
                    ? null
                    : () => _onAssignBranch(selectedUser),
                icon: const Icon(Icons.add_home_work_outlined, size: 16),
                label: const Text('Asignar sucursal'),
              ),
            ),
          ),
          if (selectedUser == null)
            const Padding(
              padding: EdgeInsets.all(AppTokens.s20),
              child: Text(
                'Selecciona un usuario para gestionar sus sucursales.',
                style: TextStyle(color: AppTokens.mutedForeground),
              ),
            )
          else if (selectedUser.branches.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppTokens.s20),
              child: Text(
                'Este usuario no tiene sucursales asignadas.',
                style: TextStyle(color: AppTokens.mutedForeground),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: constraints.maxWidth.isFinite
                        ? constraints.maxWidth
                        : 0,
                  ),
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Sucursal')),
                      DataColumn(label: Text('Rol override')),
                      DataColumn(label: Text('Caja')),
                      DataColumn(label: Text('Default')),
                      DataColumn(label: Text('Estado')),
                      DataColumn(label: Text('Acciones')),
                    ],
                    rows: selectedUser.branches
                        .map(
                          (branch) => DataRow(
                            cells: [
                              DataCell(
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${branch.branchCode} - ${branch.branchName}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (branch.membershipNotes != null &&
                                        branch.membershipNotes!.isNotEmpty)
                                      Text(
                                        branch.membershipNotes!,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppTokens.mutedForeground,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              DataCell(
                                Text(_roleLabel(branch.roleOverride ?? '-')),
                              ),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Tooltip(
                                      message: 'Puede abrir caja',
                                      child: Icon(
                                        branch.canOpenCash
                                            ? Icons.lock_open_outlined
                                            : Icons.lock_outline,
                                        size: 14,
                                        color: branch.canOpenCash
                                            ? AppTokens.success
                                            : AppTokens.mutedForeground,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Tooltip(
                                      message: 'Puede cerrar caja',
                                      child: Icon(
                                        branch.canCloseCash
                                            ? Icons.lock_outlined
                                            : Icons.lock_outline,
                                        size: 14,
                                        color: branch.canCloseCash
                                            ? AppTokens.success
                                            : AppTokens.mutedForeground,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              DataCell(
                                StatusBadge(
                                  label: branch.isDefault ? 'Sí' : 'No',
                                  status: branch.isDefault
                                      ? 'active'
                                      : 'inactive',
                                ),
                              ),
                              DataCell(
                                StatusBadge(
                                  label: branch.isActive
                                      ? 'Activa'
                                      : 'Inactiva',
                                  status: branch.isActive
                                      ? 'active'
                                      : 'inactive',
                                ),
                              ),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Editar asignación',
                                      onPressed: () =>
                                          _onEditMembership(branch),
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: AppTokens.iconSizeS,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    IconButton(
                                      tooltip: 'Marcar default',
                                      onPressed: branch.isDefault
                                          ? null
                                          : () => _onSetDefaultBranch(
                                              userId: selectedUser.id,
                                              branchId: branch.branchId,
                                            ),
                                      icon: const Icon(
                                        Icons.star_outline,
                                        size: AppTokens.iconSizeS,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    IconButton(
                                      tooltip: branch.isActive
                                          ? 'Desactivar'
                                          : 'Activar',
                                      onPressed: () => _onToggleMembership(
                                        membershipId: branch.membershipId,
                                        isActive: !branch.isActive,
                                      ),
                                      icon: Icon(
                                        branch.isActive
                                            ? Icons.link_off_outlined
                                            : Icons.link_outlined,
                                        size: AppTokens.iconSizeS,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(usersListProvider);
    ref.invalidate(usersBranchOptionsProvider);
  }

  Future<void> _onCreateUser() async {
    final input = await showDialog<CreateEmployeeInput>(
      context: context,
      builder: (_) => const _CreateUserDialog(),
    );
    if (input == null || !mounted) return;

    try {
      final repository = ref.read(usersRepositoryProvider);
      await repository.createEmployee(input);
      if (!mounted) return;
      ref.invalidate(usersListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Usuario ${input.fullName} creado exitosamente'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo crear el usuario: ${friendlyErrorMessage(error)}',
          ),
        ),
      );
    }
  }

  Future<void> _onEditUser(UserEntity user) async {
    final result = await showDialog<_EditUserResult>(
      context: context,
      builder: (_) => _EditUserDialog(user: user),
    );
    if (result == null || !mounted) return;

    try {
      final repository = ref.read(usersRepositoryProvider);
      await repository.updateUser(result.input);

      // Correo y contraseña tocan auth.users → van por RPC aparte.
      final originalEmail = (user.email ?? '').trim().toLowerCase();
      final newEmail = result.email.trim().toLowerCase();
      if (newEmail.isNotEmpty && newEmail != originalEmail) {
        await repository.updateUserEmail(userId: user.id, email: newEmail);
      }
      if (result.password.isNotEmpty) {
        await repository.setUserPassword(
          userId: user.id,
          password: result.password,
        );
      }

      if (!mounted) return;
      ref.invalidate(usersListProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Usuario actualizado')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo guardar usuario: ${friendlyErrorMessage(error)}',
          ),
        ),
      );
    }
  }

  Future<void> _onDeleteUser(UserEntity user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar usuario'),
        content: Text(
          '¿Eliminar a ${user.fullName}?\n\n'
          'Se borrará su acceso al sistema de forma permanente. Esta acción no '
          'se puede deshacer. Si solo quieres bloquear el acceso temporalmente, '
          'usa "Desactivar".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTokens.destructive,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final repository = ref.read(usersRepositoryProvider);
      await repository.deleteUser(user.id);
      if (!mounted) return;
      ref.invalidate(usersListProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Usuario eliminado')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo eliminar el usuario: ${friendlyErrorMessage(error)}',
          ),
        ),
      );
    }
  }

  Future<void> _onToggleActive(UserEntity user) async {
    try {
      final repository = ref.read(usersRepositoryProvider);
      await repository.setUserActive(userId: user.id, isActive: !user.isActive);
      if (!mounted) return;
      ref.invalidate(usersListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            user.isActive ? 'Usuario desactivado' : 'Usuario activado',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo actualizar estado: ${friendlyErrorMessage(error)}',
          ),
        ),
      );
    }
  }

  Future<void> _onAssignBranch(UserEntity user) async {
    final options = await ref.read(usersBranchOptionsProvider.future);
    if (!mounted) return;
    final usedBranchIds = user.branches.map((item) => item.branchId).toSet();
    final available = options
        .where((option) => !usedBranchIds.contains(option.id))
        .toList();

    final input = await showDialog<UserBranchAssignInput>(
      context: context,
      builder: (_) => _AssignBranchDialog(user: user, options: available),
    );
    if (input == null || !mounted) return;

    try {
      final repository = ref.read(usersRepositoryProvider);
      await repository.assignBranch(input);
      if (!mounted) return;
      ref.invalidate(usersListProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sucursal asignada')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo asignar sucursal: ${friendlyErrorMessage(error)}',
          ),
        ),
      );
    }
  }

  Future<void> _onSetDefaultBranch({
    required String userId,
    required String branchId,
  }) async {
    try {
      final repository = ref.read(usersRepositoryProvider);
      await repository.setDefaultBranch(userId: userId, branchId: branchId);
      if (!mounted) return;
      ref.invalidate(usersListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sucursal por defecto actualizada')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo cambiar sucursal por defecto: ${friendlyErrorMessage(error)}',
          ),
        ),
      );
    }
  }

  Future<void> _onEditMembership(UserBranchAssignment branch) async {
    final input = await showDialog<MembershipUpdateInput>(
      context: context,
      builder: (_) => _EditMembershipDialog(branch: branch),
    );
    if (input == null || !mounted) return;

    try {
      final repository = ref.read(usersRepositoryProvider);
      await repository.updateMembership(input);
      if (!mounted) return;
      ref.invalidate(usersListProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Asignación actualizada')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo actualizar: ${friendlyErrorMessage(error)}',
          ),
        ),
      );
    }
  }

  Future<void> _onToggleMembership({
    required String membershipId,
    required bool isActive,
  }) async {
    try {
      final repository = ref.read(usersRepositoryProvider);
      await repository.setMembershipActive(
        membershipId: membershipId,
        isActive: isActive,
      );
      if (!mounted) return;
      ref.invalidate(usersListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isActive ? 'Asignación activada' : 'Asignación desactivada',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo actualizar asignación: ${friendlyErrorMessage(error)}',
          ),
        ),
      );
    }
  }
}

class _UsersKpis extends StatelessWidget {
  const _UsersKpis({required this.users});

  final List<UserEntity> users;

  @override
  Widget build(BuildContext context) {
    final total = users.length;
    final active = users.where((item) => item.isActive).length;
    final admins = users.where((item) => item.role == 'admin').length;
    final assignments = users.fold<int>(
      0,
      (sum, item) => sum + item.branches.where((b) => b.isActive).length,
    );

    final cards = [
      KPICard(
        label: 'Usuarios',
        value: total.toString(),
        icon: Icons.people_outline_rounded,
      ),
      KPICard(
        label: 'Activos',
        value: active.toString(),
        icon: Icons.check_circle_outline,
      ),
      KPICard(
        label: 'Admins',
        value: admins.toString(),
        icon: Icons.admin_panel_settings_outlined,
      ),
      KPICard(
        label: 'Asignaciones',
        value: assignments.toString(),
        icon: Icons.assignment_ind_outlined,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 800) {
          return Wrap(
            spacing: AppTokens.s12,
            runSpacing: AppTokens.s12,
            children: cards
                .map(
                  (card) => SizedBox(
                    width: (constraints.maxWidth - AppTokens.s12) / 2,
                    child: card,
                  ),
                )
                .toList(),
          );
        }
        return Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: AppTokens.s12),
            Expanded(child: cards[1]),
            const SizedBox(width: AppTokens.s12),
            Expanded(child: cards[2]),
            const SizedBox(width: AppTokens.s12),
            Expanded(child: cards[3]),
          ],
        );
      },
    );
  }
}

class _EditUserDialog extends StatefulWidget {
  const _EditUserDialog({required this.user});

  final UserEntity user;

  @override
  State<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<_EditUserDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  late final TextEditingController _phoneController;
  late final TextEditingController _employeeCodeController;
  late final TextEditingController _jobTitleController;
  late final TextEditingController _notesController;
  late String _role;
  late bool _isActive;
  DateTime? _hireDate;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.fullName);
    _emailController = TextEditingController(text: widget.user.email ?? '');
    _passwordController = TextEditingController();
    _phoneController = TextEditingController(text: widget.user.phone ?? '');
    _employeeCodeController = TextEditingController(
      text: widget.user.employeeCode ?? '',
    );
    _jobTitleController = TextEditingController(
      text: widget.user.jobTitle ?? '',
    );
    _notesController = TextEditingController(text: widget.user.notes ?? '');
    _role = widget.user.role;
    _isActive = widget.user.isActive;
    _hireDate = widget.user.hireDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _employeeCodeController.dispose();
    _jobTitleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickHireDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _hireDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _hireDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final hireDateLabel = _hireDate == null
        ? 'Sin fecha'
        : '${_hireDate!.day.toString().padLeft(2, '0')}/'
              '${_hireDate!.month.toString().padLeft(2, '0')}/'
              '${_hireDate!.year}';

    return AlertDialog(
      title: const Text('Editar usuario'),
      content: SizedBox(
        width: ResponsiveLayout.isMobile(context) ? double.maxFinite : 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader('Cuenta'),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre completo',
                  ),
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? 'Campo requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (value) {
                    final v = (value ?? '').trim();
                    if (v.isEmpty) return 'Campo requerido';
                    if (!v.contains('@')) return 'Correo no válido';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Nueva contraseña',
                    helperText: 'Déjalo vacío para no cambiarla',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (value) {
                    final v = value ?? '';
                    if (v.isNotEmpty && v.length < 6) {
                      return 'Mínimo 6 caracteres';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(labelText: 'Teléfono'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Rol'),
                  items: _roles.entries
                      .map(
                        (entry) => DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) =>
                      setState(() => _role = value ?? 'cashier'),
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                  title: const Text('Usuario activo'),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 16),
                _sectionHeader('Empleado'),
                TextFormField(
                  controller: _employeeCodeController,
                  decoration: const InputDecoration(
                    labelText: 'Código de empleado',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _jobTitleController,
                  decoration: const InputDecoration(
                    labelText: 'Cargo / Puesto',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Fecha de ingreso',
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        child: Text(hireDateLabel),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _pickHireDate,
                      child: const Text('Elegir'),
                    ),
                    if (_hireDate != null) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: () => setState(() => _hireDate = null),
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Limpiar fecha',
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notas internas',
                  ),
                  maxLines: 3,
                  minLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _onSave, child: const Text('Guardar')),
      ],
    );
  }

  void _onSave() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      _EditUserResult(
        input: UserInput(
          id: widget.user.id,
          fullName: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
          role: _role,
          isActive: _isActive,
          employeeCode: _employeeCodeController.text.trim(),
          jobTitle: _jobTitleController.text.trim(),
          hireDate: _hireDate,
          notes: _notesController.text.trim(),
        ),
        email: _emailController.text.trim(),
        password: _passwordController.text,
      ),
    );
  }
}

/// Resultado del diálogo de editar usuario: los campos de perfil (UserInput)
/// más el correo y la contraseña nueva (que van por RPC aparte si cambian).
class _EditUserResult {
  const _EditUserResult({
    required this.input,
    required this.email,
    required this.password,
  });

  final UserInput input;
  final String email;
  final String password;
}

Widget _sectionHeader(String label) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      label,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        color: AppTokens.mutedForeground,
        fontSize: 12,
        letterSpacing: 0.5,
      ),
    ),
  );
}

class _UserPermissionsPanel extends ConsumerStatefulWidget {
  const _UserPermissionsPanel({required this.selectedUser});

  final UserEntity? selectedUser;

  @override
  ConsumerState<_UserPermissionsPanel> createState() =>
      _UserPermissionsPanelState();
}

class _UserPermissionsPanelState extends ConsumerState<_UserPermissionsPanel> {
  String? _selectedBranchId;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _expandedModules = {};

  /// Códigos de permiso cuya escritura está en vuelo. El switch
  /// correspondiente muestra un spinner pequeño hasta que el RPC
  /// confirma el cambio (o falla).
  final Set<String> _savingCodes = {};

  /// Si está reseteando todos los overrides del usuario+sucursal,
  /// bloqueamos el panel completo.
  bool _resettingAll = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_UserPermissionsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedUser?.id != widget.selectedUser?.id) {
      _selectedBranchId = null;
      _searchQuery = '';
      _searchController.clear();
      _expandedModules.clear();
      _savingCodes.clear();
      _resettingAll = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.selectedUser;

    final activeBranches =
        user?.branches.where((b) => b.isActive).toList(growable: false) ??
        const [];

    if (_selectedBranchId == null && activeBranches.isNotEmpty) {
      _selectedBranchId = activeBranches.first.branchId;
    }

    final permissionsAsync = (user != null && _selectedBranchId != null)
        ? ref.watch(
            effectivePermissionsProvider((
              userId: user.id,
              branchId: _selectedBranchId!,
            )),
          )
        : null;

    return DataTableShell(
      title: user == null
          ? 'Permisos efectivos'
          : 'Permisos efectivos — ${user.fullName}',
      // El contenido (buscador + cards de módulos) usa CrossAxisAlignment.stretch
      // adentro, que no se lleva con un SingleChildScrollView horizontal. No es
      // una tabla de columnas anchas, así que desactivamos el scroll lateral.
      scrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (user == null)
            const Padding(
              padding: EdgeInsets.all(AppTokens.s20),
              child: Text(
                'Selecciona un usuario para ver sus permisos.',
                style: TextStyle(color: AppTokens.mutedForeground),
              ),
            )
          else if (activeBranches.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppTokens.s20),
              child: Text(
                'El usuario no tiene sucursales activas asignadas.',
                style: TextStyle(color: AppTokens.mutedForeground),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.s20,
                AppTokens.s12,
                AppTokens.s20,
                AppTokens.s12,
              ),
              child: Row(
                children: [
                  const Text(
                    'Sucursal:',
                    style: TextStyle(color: AppTokens.mutedForeground),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _selectedBranchId,
                    isDense: true,
                    items: activeBranches
                        .map(
                          (b) => DropdownMenuItem<String>(
                            value: b.branchId,
                            child: Text('${b.branchCode} - ${b.branchName}'),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: _resettingAll
                        ? null
                        : (value) => setState(() => _selectedBranchId = value),
                  ),
                  const Spacer(),
                  if (permissionsAsync?.valueOrNull != null)
                    _OverrideCountChip(perms: permissionsAsync!.valueOrNull!),
                  const SizedBox(width: AppTokens.s8),
                  OutlinedButton.icon(
                    onPressed: _resettingAll
                        ? null
                        : () => _confirmResetAll(user),
                    icon: _resettingAll
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.restart_alt_rounded, size: 18),
                    label: const Text('Restablecer al rol'),
                  ),
                ],
              ),
            ),
            if (permissionsAsync != null)
              permissionsAsync.when(
                data: (perms) => _buildPermissionsTable(perms, user),
                loading: () => const Padding(
                  padding: EdgeInsets.all(AppTokens.s20),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.all(AppTokens.s20),
                  child: Text(
                    'No se pudieron cargar permisos: ${friendlyErrorMessage(error)}',
                    style: const TextStyle(color: AppTokens.destructive),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildPermissionsTable(
    List<EffectivePermission> perms,
    UserEntity user,
  ) {
    if (perms.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(AppTokens.s20),
        child: Text(
          'No hay permisos definidos para esta sucursal.',
          style: TextStyle(color: AppTokens.mutedForeground),
        ),
      );
    }

    final q = _searchQuery.trim().toLowerCase();
    final filtered = q.isEmpty
        ? perms
        : perms
              .where(
                (p) =>
                    p.permissionName.toLowerCase().contains(q) ||
                    p.permissionCode.toLowerCase().contains(q) ||
                    (p.module ?? '').toLowerCase().contains(q),
              )
              .toList(growable: false);

    final grouped = <String, List<EffectivePermission>>{};
    for (final p in filtered) {
      grouped.putIfAbsent(p.module ?? 'General', () => []).add(p);
    }
    final orderedKeys = grouped.keys.toList()
      ..sort((a, b) {
        final ai = _moduleOrder.indexOf(a);
        final bi = _moduleOrder.indexOf(b);
        if (ai == -1 && bi == -1) return a.compareTo(b);
        if (ai == -1) return 1;
        if (bi == -1) return -1;
        return ai.compareTo(bi);
      });

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.s20,
        0,
        AppTokens.s20,
        AppTokens.s16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Buscador + acciones masivas
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Buscar permiso, módulo o código…',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTokens.border),
                    ),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Limpiar',
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          ),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              const SizedBox(width: AppTokens.s8),
              Tooltip(
                message: 'Expandir todos',
                child: OutlinedButton.icon(
                  onPressed: () => setState(() {
                    _expandedModules
                      ..clear()
                      ..addAll(grouped.keys);
                  }),
                  icon: const Icon(Icons.unfold_more, size: 16),
                  label: const Text('Expandir'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 40),
                  ),
                ),
              ),
              const SizedBox(width: AppTokens.s8),
              Tooltip(
                message: 'Colapsar todos',
                child: OutlinedButton.icon(
                  onPressed: () => setState(_expandedModules.clear),
                  icon: const Icon(Icons.unfold_less, size: 16),
                  label: const Text('Colapsar'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 40),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.s12),

          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppTokens.s24),
              child: Center(
                child: Text(
                  'Ningún permiso coincide con la búsqueda.',
                  style: TextStyle(color: AppTokens.mutedForeground),
                ),
              ),
            )
          else
            ...orderedKeys.map((module) {
              final items = grouped[module]!;
              final grantedCount = items.where((p) => p.effectiveGrant).length;
              final isExpanded =
                  _expandedModules.contains(module) || _searchQuery.isNotEmpty;
              return _ModulePermissionsCard(
                module: module,
                granted: grantedCount,
                total: items.length,
                isExpanded: isExpanded,
                onToggle: () => setState(() {
                  if (_expandedModules.contains(module)) {
                    _expandedModules.remove(module);
                  } else {
                    _expandedModules.add(module);
                  }
                }),
                children: [for (final p in items) _permissionRowTile(p, user)],
              );
            }),
        ],
      ),
    );
  }

  Widget _permissionRowTile(EffectivePermission p, UserEntity user) {
    final effective = p.effectiveGrant;
    final statusColor = effective ? AppTokens.success : AppTokens.destructive;
    final statusLabel = effective ? 'Permitido' : 'Denegado';
    final statusIcon = effective ? Icons.check_circle : Icons.cancel_outlined;

    String sourceLabel;
    if (p.hasOverride) {
      sourceLabel = p.userOverride!
          ? 'Override: permitido'
          : 'Override: denegado';
    } else {
      sourceLabel = p.roleGrant ? 'Heredado del rol' : 'Sin permiso del rol';
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s16,
        vertical: AppTokens.s10,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTokens.border)),
      ),
      child: Row(
        children: [
          // Status pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, size: 14, color: statusColor),
                const SizedBox(width: 4),
                Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTokens.s12),
          // Permission name + source
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.permissionName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${p.permissionCode}  ·  $sourceLabel',
                  style: const TextStyle(
                    color: AppTokens.mutedForeground,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // Actions
          if (p.hasOverride)
            IconButton(
              tooltip: 'Quitar override (volver al rol)',
              onPressed:
                  _savingCodes.contains(p.permissionCode) || _resettingAll
                  ? null
                  : () => _removeOverride(p, user),
              icon: const Icon(Icons.undo, size: 16),
              visualDensity: VisualDensity.compact,
              color: AppTokens.mutedForeground,
            ),
          if (_savingCodes.contains(p.permissionCode))
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          Switch(
            value: effective,
            onChanged: _savingCodes.contains(p.permissionCode) || _resettingAll
                ? null
                : (v) => _setOverride(p, user, granted: v),
            activeThumbColor: AppTokens.success,
          ),
        ],
      ),
    );
  }

  Future<void> _setOverride(
    EffectivePermission p,
    UserEntity user, {
    required bool granted,
  }) async {
    setState(() => _savingCodes.add(p.permissionCode));
    try {
      final repo = ref.read(permissionsRepositoryProvider);
      await repo.setUserPermissionOverride(
        userId: user.id,
        branchId: _selectedBranchId!,
        permissionCode: p.permissionCode,
        granted: granted,
      );
      ref.invalidate(
        effectivePermissionsProvider((
          userId: user.id,
          branchId: _selectedBranchId!,
        )),
      );
      if (!mounted) return;
      AppSnackBar.success(
        context,
        granted
            ? '"${p.permissionName}" permitido'
            : '"${p.permissionName}" denegado',
      );
    } catch (error) {
      if (!mounted) return;
      AppSnackBar.error(context, 'No se pudo guardar el permiso', error);
    } finally {
      if (mounted) {
        setState(() => _savingCodes.remove(p.permissionCode));
      }
    }
  }

  Future<void> _removeOverride(EffectivePermission p, UserEntity user) async {
    setState(() => _savingCodes.add(p.permissionCode));
    try {
      final repo = ref.read(permissionsRepositoryProvider);
      await repo.removeUserPermissionOverride(
        userId: user.id,
        branchId: _selectedBranchId!,
        permissionCode: p.permissionCode,
      );
      ref.invalidate(
        effectivePermissionsProvider((
          userId: user.id,
          branchId: _selectedBranchId!,
        )),
      );
      if (!mounted) return;
      AppSnackBar.success(
        context,
        '"${p.permissionName}" vuelve al permiso del rol',
      );
    } catch (error) {
      if (!mounted) return;
      AppSnackBar.error(context, 'No se pudo quitar el override', error);
    } finally {
      if (mounted) {
        setState(() => _savingCodes.remove(p.permissionCode));
      }
    }
  }

  Future<void> _confirmResetAll(UserEntity user) async {
    final branchId = _selectedBranchId;
    if (branchId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restablecer permisos'),
        content: Text(
          'Esto elimina todas las excepciones personalizadas de '
          '${user.fullName} en esta sucursal. Sus permisos volverán '
          'a derivarse 100% del rol "${_roles[user.role] ?? user.role}".\n\n'
          '¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: const Text('Restablecer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _resettingAll = true);
    try {
      final repo = ref.read(permissionsRepositoryProvider);
      final count = await repo.clearAllOverridesForUserBranch(
        userId: user.id,
        branchId: branchId,
      );
      ref.invalidate(
        effectivePermissionsProvider((userId: user.id, branchId: branchId)),
      );
      if (!mounted) return;
      AppSnackBar.success(
        context,
        count == 0
            ? 'No había excepciones que restablecer.'
            : 'Se restablecieron $count permiso(s) al rol base.',
      );
    } catch (error) {
      if (!mounted) return;
      AppSnackBar.error(context, 'No se pudo restablecer', error);
    } finally {
      if (mounted) setState(() => _resettingAll = false);
    }
  }
}

class _OverrideCountChip extends StatelessWidget {
  const _OverrideCountChip({required this.perms});

  final List<EffectivePermission> perms;

  @override
  Widget build(BuildContext context) {
    final overrideCount = perms.where((p) => p.hasOverride).length;
    if (overrideCount == 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppTokens.muted,
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text(
          'Sin excepciones',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppTokens.mutedForeground,
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTokens.info.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTokens.info.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$overrideCount excepción${overrideCount == 1 ? '' : 'es'} sobre el rol',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppTokens.info,
        ),
      ),
    );
  }
}

class _AssignBranchDialog extends StatefulWidget {
  const _AssignBranchDialog({required this.user, required this.options});

  final UserEntity user;
  final List<BranchOption> options;

  @override
  State<_AssignBranchDialog> createState() => _AssignBranchDialogState();
}

class _AssignBranchDialogState extends State<_AssignBranchDialog> {
  final _formKey = GlobalKey<FormState>();
  String? _branchId;
  String _roleOverride = '';
  bool _defaultBranch = false;
  bool _canOpenCash = false;
  bool _canCloseCash = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Asignar sucursal (${widget.user.fullName})'),
      content: SizedBox(
        width: ResponsiveLayout.isMobile(context) ? double.maxFinite : 520,
        child: widget.options.isEmpty
            ? const Text('No hay sucursales disponibles para este usuario.')
            : Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _branchId,
                      decoration: const InputDecoration(labelText: 'Sucursal'),
                      items: widget.options
                          .map(
                            (branch) => DropdownMenuItem<String>(
                              value: branch.id,
                              child: Text('${branch.code} - ${branch.name}'),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) => setState(() => _branchId = value),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Selecciona sucursal';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _roleOverride,
                      decoration: const InputDecoration(
                        labelText: 'Rol override (opcional)',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: '',
                          child: Text('Sin override'),
                        ),
                        DropdownMenuItem(
                          value: 'admin',
                          child: Text('Administrador'),
                        ),
                        DropdownMenuItem(
                          value: 'supervisor',
                          child: Text('Supervisor'),
                        ),
                        DropdownMenuItem(
                          value: 'cashier',
                          child: Text('Cajero'),
                        ),
                        DropdownMenuItem(
                          value: 'accountant',
                          child: Text('Contador'),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _roleOverride = value ?? ''),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      value: _canOpenCash,
                      onChanged: (v) => setState(() => _canOpenCash = v),
                      title: const Text('Puede abrir caja'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile.adaptive(
                      value: _canCloseCash,
                      onChanged: (v) => setState(() => _canCloseCash = v),
                      title: const Text('Puede cerrar caja'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile.adaptive(
                      value: _defaultBranch,
                      onChanged: (value) =>
                          setState(() => _defaultBranch = value),
                      title: const Text('Marcar como sucursal por defecto'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: widget.options.isEmpty ? null : _onAssign,
          child: const Text('Asignar'),
        ),
      ],
    );
  }

  void _onAssign() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      UserBranchAssignInput(
        userId: widget.user.id,
        branchId: _branchId!,
        roleOverride: _roleOverride,
        makeDefault: _defaultBranch,
        canOpenCash: _canOpenCash,
        canCloseCash: _canCloseCash,
      ),
    );
  }
}

class _EditMembershipDialog extends StatefulWidget {
  const _EditMembershipDialog({required this.branch});

  final UserBranchAssignment branch;

  @override
  State<_EditMembershipDialog> createState() => _EditMembershipDialogState();
}

class _EditMembershipDialogState extends State<_EditMembershipDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _roleOverride;
  late bool _canOpenCash;
  late bool _canCloseCash;
  late final TextEditingController _pinController;
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _roleOverride = widget.branch.roleOverride ?? '';
    _canOpenCash = widget.branch.canOpenCash;
    _canCloseCash = widget.branch.canCloseCash;
    _pinController = TextEditingController(
      text: widget.branch.posPinOverride ?? '',
    );
    _notesController = TextEditingController(
      text: widget.branch.membershipNotes ?? '',
    );
  }

  @override
  void dispose() {
    _pinController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final branchLabel =
        '${widget.branch.branchCode} - ${widget.branch.branchName}';

    return AlertDialog(
      title: Text('Editar asignación\n$branchLabel'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _roleOverride,
                decoration: const InputDecoration(
                  labelText: 'Rol override (opcional)',
                ),
                items: const [
                  DropdownMenuItem(value: '', child: Text('Sin override')),
                  DropdownMenuItem(
                    value: 'admin',
                    child: Text('Administrador'),
                  ),
                  DropdownMenuItem(
                    value: 'supervisor',
                    child: Text('Supervisor'),
                  ),
                  DropdownMenuItem(value: 'cashier', child: Text('Cajero')),
                  DropdownMenuItem(
                    value: 'accountant',
                    child: Text('Contador'),
                  ),
                ],
                onChanged: (v) => setState(() => _roleOverride = v ?? ''),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                value: _canOpenCash,
                onChanged: (v) => setState(() => _canOpenCash = v),
                title: const Text('Puede abrir caja'),
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile.adaptive(
                value: _canCloseCash,
                onChanged: (v) => setState(() => _canCloseCash = v),
                title: const Text('Puede cerrar caja'),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _pinController,
                decoration: const InputDecoration(
                  labelText: 'PIN de caja (override)',
                  hintText: '4–6 dígitos, opcional',
                ),
                keyboardType: TextInputType.number,
                maxLength: 6,
                obscureText: true,
                validator: (v) {
                  if (v == null || v.isEmpty) return null;
                  if (v.length < 4) return 'Mínimo 4 dígitos';
                  if (!RegExp(r'^\d+$').hasMatch(v)) return 'Solo dígitos';
                  return null;
                },
              ),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notas de asignación',
                ),
                maxLines: 2,
                minLines: 1,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _onSave, child: const Text('Guardar')),
      ],
    );
  }

  void _onSave() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      MembershipUpdateInput(
        membershipId: widget.branch.membershipId,
        roleOverride: _roleOverride,
        canOpenCash: _canOpenCash,
        canCloseCash: _canCloseCash,
        posPinOverride: _pinController.text.trim(),
        notes: _notesController.text.trim(),
      ),
    );
  }
}

class _CreateUserDialog extends StatefulWidget {
  const _CreateUserDialog();

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();
  String _role = 'cashier';
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Crear usuario'),
      content: SizedBox(
        width: ResponsiveLayout.isMobile(context) ? double.maxFinite : 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader('Cuenta'),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre completo',
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Campo requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                    hintText: 'usuario@empresa.com',
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if ((v ?? '').trim().isEmpty) return 'Campo requerido';
                    if (!RegExp(
                      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                    ).hasMatch(v!.trim())) {
                      return 'Correo inválido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono (opcional)',
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Rol'),
                  items: _roles.entries
                      .map(
                        (e) => DropdownMenuItem<String>(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (v) => setState(() => _role = v ?? 'cashier'),
                ),
                const SizedBox(height: 20),
                _sectionHeader('Contraseña'),
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    hintText: 'Mínimo 8 caracteres',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  obscureText: _obscurePassword,
                  validator: (v) {
                    if ((v ?? '').isEmpty) return 'Campo requerido';
                    if (v!.length < 8) return 'Mínimo 8 caracteres';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirmController,
                  decoration: InputDecoration(
                    labelText: 'Confirmar contraseña',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  obscureText: _obscureConfirm,
                  validator: (v) {
                    if ((v ?? '').isEmpty) return 'Campo requerido';
                    if (v != _passwordController.text) {
                      return 'Las contraseñas no coinciden';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                _sectionHeader('Empleado (opcional)'),
                TextFormField(
                  controller: _codeController,
                  decoration: const InputDecoration(
                    labelText: 'Código de empleado',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Cargo / Puesto',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notas internas',
                  ),
                  maxLines: 3,
                  minLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _onSave, child: const Text('Crear usuario')),
      ],
    );
  }

  void _onSave() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      CreateEmployeeInput(
        fullName: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        role: _role,
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        employeeCode: _codeController.text.trim().isEmpty
            ? null
            : _codeController.text.trim(),
        jobTitle: _titleController.text.trim().isEmpty
            ? null
            : _titleController.text.trim(),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      ),
    );
  }
}

String _roleLabel(String value) => _roles[value] ?? value;

/// Card colapsable que agrupa los permisos de un módulo. Muestra ícono,
/// nombre del módulo, contador "X / Y permitidos" y un chevron rotatorio.
/// Cuando se expande, revela las filas de permisos con un divisor superior.
class _ModulePermissionsCard extends StatelessWidget {
  const _ModulePermissionsCard({
    required this.module,
    required this.granted,
    required this.total,
    required this.isExpanded,
    required this.onToggle,
    required this.children,
  });

  final String module;
  final int granted;
  final int total;
  final bool isExpanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final label =
        _moduleLabels[module] ?? _capitalize(module.replaceAll('_', ' '));
    final icon = _moduleIcons[module] ?? Icons.tune_outlined;
    final allGranted = granted == total && total > 0;
    final noneGranted = granted == 0 && total > 0;
    final badgeColor = allGranted
        ? AppTokens.success
        : noneGranted
        ? AppTokens.destructive
        : AppTokens.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.s10),
      decoration: BoxDecoration(
        color: AppTokens.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(10),
              bottom: isExpanded ? Radius.zero : const Radius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.s16,
                vertical: AppTokens.s12,
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 18, color: badgeColor),
                  ),
                  const SizedBox(width: AppTokens.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$total ${total == 1 ? "permiso" : "permisos"}',
                          style: const TextStyle(
                            color: AppTokens.mutedForeground,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$granted / $total permitidos',
                      style: TextStyle(
                        color: badgeColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTokens.s8),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(
                      Icons.expand_more,
                      size: 22,
                      color: AppTokens.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...children,
        ],
      ),
    );
  }

  static String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }
}
