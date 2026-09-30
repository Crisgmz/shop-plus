import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/errors/friendly_error.dart';
import '../../../shared/extensions/iterable_extensions.dart';
import '../../../shared/responsive/responsive_layout.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../../../shared/widgets/ui_custom.dart';
import '../data/branches_repository.dart';
import 'branches_providers.dart';

const _appRoles = <String, String>{
  'admin': 'Administrador',
  'supervisor': 'Supervisor',
  'cashier': 'Cajero',
  'accountant': 'Contador',
};

class BranchesPage extends ConsumerStatefulWidget {
  const BranchesPage({super.key});

  @override
  ConsumerState<BranchesPage> createState() => _BranchesPageState();
}

class _BranchesPageState extends ConsumerState<BranchesPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final branchesAsync = ref.watch(branchesListProvider);
    final membersAsync = ref.watch(branchMembersProvider);
    final query = ref.watch(branchesSearchProvider).trim().toLowerCase();
    final showInactive = ref.watch(branchesShowInactiveProvider);
    final selectedBranchId = ref.watch(selectedBranchIdProvider);

    return ModulePage(
      title: 'Sucursales',
      description: 'Gestión de sucursales y asignación de usuarios.',
      actions: [
        OutlinedButton.icon(
          onPressed: _refreshAll,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
        const SizedBox(width: AppTokens.s8),
        FilledButton.icon(
          onPressed: _onCreateBranch,
          icon: const Icon(Icons.add_business_outlined, size: 18),
          label: const Text('Nueva sucursal'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFilterBar(showInactive),
          const SizedBox(height: AppTokens.s24),
          branchesAsync.when(
            data: (branches) {
              final filtered = branches
                  .where((branch) {
                    if (!showInactive && !branch.isActive) return false;
                    if (query.isEmpty) return true;
                    final haystack = [
                      branch.code,
                      branch.name,
                      branch.address ?? '',
                      branch.phone ?? '',
                    ].join(' ').toLowerCase();
                    return haystack.contains(query);
                  })
                  .toList(growable: false);

              if (filtered.isNotEmpty &&
                  (selectedBranchId == null ||
                      !filtered.any((branch) => branch.id == selectedBranchId))) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  ref.read(selectedBranchIdProvider.notifier).state =
                      filtered.first.id;
                });
              }

              final selectedBranch = filtered
                  .where((branch) => branch.id == selectedBranchId)
                  .firstOrNull;

              return Column(
                children: [
                  _BranchKpis(branches: filtered),
                  const SizedBox(height: AppTokens.s24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final branchTable = _branchesTableCard(
                        filtered: filtered,
                        selectedBranchId: selectedBranchId,
                      );
                      final membersPanel = _membersCard(
                        selectedBranch: selectedBranch,
                        membersAsync: membersAsync,
                      );
                      if (constraints.maxWidth < 800) {
                        return Column(
                          children: [
                            branchTable,
                            const SizedBox(height: AppTokens.s12),
                            membersPanel,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 6, child: branchTable),
                          const SizedBox(width: AppTokens.s12),
                          Expanded(flex: 5, child: membersPanel),
                        ],
                      );
                    },
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => ErrorCard(
              message: 'No se pudieron cargar sucursales: ${friendlyErrorMessage(error)}',
              onRetry: _refreshAll,
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
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search, size: 18),
        hintText: 'Buscar por código, nombre, dirección o teléfono',
      ),
      onChanged: (value) =>
          ref.read(branchesSearchProvider.notifier).state = value,
    );

    final filterChip = FilterChip(
      selected: showInactive,
      label: const Text('Mostrar inactivas'),
      onSelected: (value) =>
          ref.read(branchesShowInactiveProvider.notifier).state = value,
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [searchField, const SizedBox(height: AppTokens.s12), filterChip],
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

  Widget _branchesTableCard({
    required List<BranchEntity> filtered,
    required String? selectedBranchId,
  }) {
    return DataTableShell(
      title: 'Listado de sucursales (${filtered.length})',
      child: filtered.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(AppTokens.s20),
              child: Text(
                'No hay sucursales que coincidan con el filtro.',
                style: TextStyle(color: AppTokens.mutedForeground),
              ),
            )
          : DataTable(
              columns: const [
                DataColumn(label: Text('Código')),
                DataColumn(label: Text('Nombre')),
                DataColumn(label: Text('Teléfono')),
                DataColumn(label: Text('Usuarios'), numeric: true),
                DataColumn(label: Text('Principal')),
                DataColumn(label: Text('Estado')),
                DataColumn(label: Text('Acciones')),
              ],
              rows: filtered
                  .map(
                    (branch) => DataRow(
                      selected: branch.id == selectedBranchId,
                      onSelectChanged: (_) =>
                          ref.read(selectedBranchIdProvider.notifier).state =
                              branch.id,
                      cells: [
                        DataCell(Text(
                          branch.code,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        )),
                        DataCell(Text(branch.name)),
                        DataCell(Text(branch.phone ?? '-')),
                        DataCell(Text(branch.memberCount.toString())),
                        DataCell(StatusBadge(
                          label: branch.isMain ? 'Sí' : 'No',
                          status: branch.isMain ? 'active' : 'inactive',
                        )),
                        DataCell(StatusBadge(
                          label: branch.isActive ? 'Activa' : 'Inactiva',
                          status: branch.isActive ? 'active' : 'inactive',
                        )),
                        DataCell(Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Editar',
                              onPressed: () => _onEditBranch(branch),
                              icon: const Icon(Icons.edit_outlined, size: AppTokens.iconSizeS),
                              visualDensity: VisualDensity.compact,
                            ),
                            IconButton(
                              tooltip: branch.isActive ? 'Desactivar' : 'Activar',
                              onPressed: () => _onToggleActive(branch),
                              icon: Icon(
                                branch.isActive ? Icons.block_outlined : Icons.check_circle_outline,
                                size: AppTokens.iconSizeS,
                                color: branch.isActive ? AppTokens.destructive : AppTokens.success,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                            IconButton(
                              tooltip: 'Marcar como principal',
                              onPressed: branch.isMain ? null : () => _onSetMain(branch),
                              icon: const Icon(Icons.star_outline, size: AppTokens.iconSizeS),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        )),
                      ],
                    ),
                  )
                  .toList(growable: false),
            ),
    );
  }

  Widget _membersCard({
    required BranchEntity? selectedBranch,
    required AsyncValue<List<BranchMember>> membersAsync,
  }) {
    return DataTableShell(
      title: selectedBranch == null
          ? 'Usuarios de sucursal'
          : 'Usuarios (${selectedBranch.code})',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppTokens.s20, AppTokens.s12, AppTokens.s20, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: selectedBranch == null
                    ? null
                    : () => _onAssignUser(selectedBranch),
                icon: const Icon(Icons.person_add_alt_1, size: 16),
                label: const Text('Asignar'),
              ),
            ),
          ),
          if (selectedBranch == null)
            const Padding(
              padding: EdgeInsets.all(AppTokens.s20),
              child: Text(
                'Selecciona una sucursal para ver sus usuarios.',
                style: TextStyle(color: AppTokens.mutedForeground),
              ),
            )
          else
            membersAsync.when(
              data: (members) {
                if (members.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(AppTokens.s20),
                    child: Text(
                      'No hay usuarios asignados a esta sucursal.',
                      style: TextStyle(color: AppTokens.mutedForeground),
                    ),
                  );
                }

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Usuario')),
                      DataColumn(label: Text('Rol Perfil')),
                      DataColumn(label: Text('Rol Sucursal')),
                      DataColumn(label: Text('Default')),
                      DataColumn(label: Text('Estado')),
                      DataColumn(label: Text('Acciones')),
                    ],
                    rows: members
                        .map(
                          (member) => DataRow(
                            cells: [
                              DataCell(
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(member.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    Text(
                                      member.email ?? '-',
                                      style: const TextStyle(fontSize: 12, color: AppTokens.mutedForeground),
                                    ),
                                  ],
                                ),
                              ),
                              DataCell(Text(_roleLabel(member.profileRole))),
                              DataCell(Text(_roleLabel(member.roleOverride ?? '-'))),
                              DataCell(StatusBadge(
                                label: member.isDefault ? 'Sí' : 'No',
                                status: member.isDefault ? 'active' : 'inactive',
                              )),
                              DataCell(StatusBadge(
                                label: member.isActive ? 'Activo' : 'Inactivo',
                                status: member.isActive ? 'active' : 'inactive',
                              )),
                              DataCell(Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Marcar como default',
                                    onPressed: member.isDefault
                                        ? null
                                        : () => _onSetUserDefault(
                                            userId: member.userId,
                                            branchId: selectedBranch.id,
                                          ),
                                    icon: const Icon(Icons.star_outline, size: AppTokens.iconSizeS),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  IconButton(
                                    tooltip: member.isActive
                                        ? 'Desactivar asignación'
                                        : 'Activar asignación',
                                    onPressed: () => _onToggleMembership(
                                      membershipId: member.membershipId,
                                      isActive: !member.isActive,
                                    ),
                                    icon: Icon(
                                      member.isActive ? Icons.person_off_outlined : Icons.person_outline,
                                      size: AppTokens.iconSizeS,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              )),
                            ],
                          ),
                        )
                        .toList(growable: false),
                  ),
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.all(AppTokens.s12),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.all(AppTokens.s20),
                child: Text('No se pudieron cargar usuarios: ${friendlyErrorMessage(error)}'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _refreshAll() async {
    ref.invalidate(branchesListProvider);
    ref.invalidate(branchMembersProvider);
    ref.invalidate(branchUsersProvider);
  }

  Future<void> _onCreateBranch() async {
    final input = await showDialog<BranchInput>(
      context: context,
      builder: (_) => const _BranchDialog(),
    );
    if (input == null || !mounted) return;

    await _saveBranch(input, success: 'Sucursal creada');
  }

  Future<void> _onEditBranch(BranchEntity branch) async {
    final input = await showDialog<BranchInput>(
      context: context,
      builder: (_) => _BranchDialog(branch: branch),
    );
    if (input == null || !mounted) return;

    await _saveBranch(input, success: 'Sucursal actualizada');
  }

  Future<void> _saveBranch(BranchInput input, {required String success}) async {
    try {
      final repository = ref.read(branchesRepositoryProvider);
      final id = await repository.saveBranch(input);
      if (!mounted) return;
      ref.read(selectedBranchIdProvider.notifier).state = id;
      ref.invalidate(branchesListProvider);
      ref.invalidate(branchMembersProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar sucursal: ${friendlyErrorMessage(error)}')),
      );
    }
  }

  Future<void> _onToggleActive(BranchEntity branch) async {
    try {
      final repository = ref.read(branchesRepositoryProvider);
      await repository.setBranchActive(
        branchId: branch.id,
        isActive: !branch.isActive,
      );
      if (!mounted) return;
      ref.invalidate(branchesListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            branch.isActive ? 'Sucursal desactivada' : 'Sucursal activada',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar estado: ${friendlyErrorMessage(error)}')),
      );
    }
  }

  Future<void> _onSetMain(BranchEntity branch) async {
    try {
      final repository = ref.read(branchesRepositoryProvider);
      await repository.setMainBranch(branch.id);
      if (!mounted) return;
      ref.invalidate(branchesListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${branch.name} ahora es la sucursal principal'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo marcar como principal: ${friendlyErrorMessage(error)}')),
      );
    }
  }

  Future<void> _onAssignUser(BranchEntity branch) async {
    final usersAsync = await ref.read(branchUsersProvider.future);
    final members = await ref.read(branchMembersProvider.future);
    if (!mounted) return;
    final assignedIds = members.map((item) => item.userId).toSet();

    final input = await showDialog<BranchAssignUserInput>(
      context: context,
      builder: (_) => _AssignUserDialog(
        branch: branch,
        users: usersAsync
            .where((item) => !assignedIds.contains(item.id))
            .toList(),
      ),
    );

    if (input == null || !mounted) return;

    try {
      final repository = ref.read(branchesRepositoryProvider);
      await repository.assignUserToBranch(input);
      if (!mounted) return;
      ref.invalidate(branchesListProvider);
      ref.invalidate(branchMembersProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Usuario asignado')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo asignar usuario: ${friendlyErrorMessage(error)}')),
      );
    }
  }

  Future<void> _onSetUserDefault({
    required String userId,
    required String branchId,
  }) async {
    try {
      final repository = ref.read(branchesRepositoryProvider);
      await repository.setDefaultBranchForUser(
        userId: userId,
        branchId: branchId,
      );
      if (!mounted) return;
      ref.invalidate(branchMembersProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sucursal por defecto actualizada')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo cambiar sucursal por defecto: ${friendlyErrorMessage(error)}'),
        ),
      );
    }
  }

  Future<void> _onToggleMembership({
    required String membershipId,
    required bool isActive,
  }) async {
    try {
      final repository = ref.read(branchesRepositoryProvider);
      await repository.setBranchMemberActive(
        membershipId: membershipId,
        isActive: isActive,
      );
      if (!mounted) return;
      ref.invalidate(branchesListProvider);
      ref.invalidate(branchMembersProvider);
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
        SnackBar(content: Text('No se pudo actualizar asignación: ${friendlyErrorMessage(error)}')),
      );
    }
  }
}

class _BranchKpis extends StatelessWidget {
  const _BranchKpis({required this.branches});

  final List<BranchEntity> branches;

  @override
  Widget build(BuildContext context) {
    final total = branches.length;
    final active = branches.where((item) => item.isActive).length;
    final main = branches.where((item) => item.isMain).length;
    final users = branches.fold<int>(0, (sum, item) => sum + item.memberCount);

    final cards = [
      KPICard(label: 'Sucursales', value: total.toString(), icon: Icons.business_outlined),
      KPICard(label: 'Activas', value: active.toString(), icon: Icons.check_circle_outline),
      KPICard(label: 'Principal', value: main.toString(), icon: Icons.star_outline),
      KPICard(label: 'Asignaciones', value: users.toString(), icon: Icons.people_outline_rounded),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 800) {
          return Wrap(
            spacing: AppTokens.s12,
            runSpacing: AppTokens.s12,
            children: cards
                .map((card) => SizedBox(
                      width: (constraints.maxWidth - AppTokens.s12) / 2,
                      child: card,
                    ))
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

class _BranchDialog extends StatefulWidget {
  const _BranchDialog({this.branch});

  final BranchEntity? branch;

  @override
  State<_BranchDialog> createState() => _BranchDialogState();
}

class _BranchDialogState extends State<_BranchDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeController;
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _phoneController;
  late bool _isActive;
  late bool _isMain;

  @override
  void initState() {
    super.initState();
    final branch = widget.branch;
    _codeController = TextEditingController(text: branch?.code ?? '');
    _nameController = TextEditingController(text: branch?.name ?? '');
    _addressController = TextEditingController(text: branch?.address ?? '');
    _phoneController = TextEditingController(text: branch?.phone ?? '');
    _isActive = branch?.isActive ?? true;
    _isMain = branch?.isMain ?? false;
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dialogMobile = ResponsiveLayout.isMobile(context);

    return AlertDialog(
      title: Text(widget.branch == null ? 'Nueva sucursal' : 'Editar sucursal'),
      content: SizedBox(
        width: dialogMobile ? double.maxFinite : 540,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dialogMobile)
                ...[
                  TextFormField(
                    controller: _codeController,
                    decoration: const InputDecoration(labelText: 'Código'),
                    textCapitalization: TextCapitalization.characters,
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return 'Campo requerido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return 'Campo requerido';
                      }
                      return null;
                    },
                  ),
                ]
              else
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _codeController,
                        decoration: const InputDecoration(labelText: 'Código'),
                        textCapitalization: TextCapitalization.characters,
                        validator: (value) {
                          if ((value ?? '').trim().isEmpty) {
                            return 'Campo requerido';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(labelText: 'Nombre'),
                        validator: (value) {
                          if ((value ?? '').trim().isEmpty) {
                            return 'Campo requerido';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(labelText: 'Dirección'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Teléfono'),
              ),
              const SizedBox(height: 10),
              SwitchListTile.adaptive(
                value: _isMain,
                onChanged: (value) => setState(() => _isMain = value),
                title: const Text('Sucursal principal'),
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile.adaptive(
                value: _isActive,
                onChanged: (value) => setState(() => _isActive = value),
                title: const Text('Sucursal activa'),
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
        FilledButton(onPressed: _onSave, child: const Text('Guardar')),
      ],
    );
  }

  void _onSave() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      BranchInput(
        id: widget.branch?.id,
        code: _codeController.text.trim(),
        name: _nameController.text.trim(),
        address: _addressController.text.trim(),
        phone: _phoneController.text.trim(),
        isActive: _isActive,
        isMain: _isMain,
      ),
    );
  }
}

class _AssignUserDialog extends StatefulWidget {
  const _AssignUserDialog({required this.branch, required this.users});

  final BranchEntity branch;
  final List<BranchUserOption> users;

  @override
  State<_AssignUserDialog> createState() => _AssignUserDialogState();
}

class _AssignUserDialogState extends State<_AssignUserDialog> {
  final _formKey = GlobalKey<FormState>();
  String? _userId;
  String _roleOverride = '';
  bool _makeDefault = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Asignar usuario (${widget.branch.code})'),
      content: SizedBox(
        width: ResponsiveLayout.isMobile(context) ? double.maxFinite : 520,
        child: widget.users.isEmpty
            ? const Text('No hay usuarios disponibles para asignar.')
            : Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _userId,
                      decoration: const InputDecoration(labelText: 'Usuario'),
                      items: widget.users
                          .map(
                            (user) => DropdownMenuItem<String>(
                              value: user.id,
                              child: Text(
                                '${user.fullName} (${user.email ?? '-'})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) => setState(() => _userId = value),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Selecciona un usuario';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _roleOverride,
                      decoration: const InputDecoration(
                        labelText: 'Rol en sucursal (opcional)',
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
                      value: _makeDefault,
                      onChanged: (value) =>
                          setState(() => _makeDefault = value),
                      title: const Text('Definir como sucursal por defecto'),
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
          onPressed: widget.users.isEmpty ? null : _onAssign,
          child: const Text('Asignar'),
        ),
      ],
    );
  }

  void _onAssign() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      BranchAssignUserInput(
        branchId: widget.branch.id,
        userId: _userId!,
        roleOverride: _roleOverride,
        makeDefaultForUser: _makeDefault,
      ),
    );
  }
}

String _roleLabel(String value) => _appRoles[value] ?? value;
