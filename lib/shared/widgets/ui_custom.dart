import 'package:flutter/material.dart';
import '../../core/theme/tokens.dart';

/// Custom UI components for Shop+ based on the design documentation.
/// Replicates the "Componentes Reutilizables" section of the Design Doc.

class KPICard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final String? trend;
  final bool isPositive;
  final Color? backgroundColor;
  final VoidCallback? onTap;

  const KPICard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.trend,
    this.isPositive = true,
    this.backgroundColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isColored = backgroundColor != null;
    final textColor = isColored ? Colors.white : AppTokens.foreground;
    final subColor =
        isColored ? Colors.white.withValues(alpha: 0.85) : AppTokens.mutedForeground;
    final iconBg = isColored
        ? Colors.black.withValues(alpha: 0.15)
        : AppTokens.primary.withValues(alpha: 0.1);
    final iconColor = isColored ? Colors.white : AppTokens.primary;

    return Material(
      color: backgroundColor ?? AppTokens.card,
      borderRadius: BorderRadius.circular(AppTokens.radius),
      elevation: isColored ? 4 : 0,
      shadowColor: (backgroundColor ?? AppTokens.primary).withValues(alpha: 0.2),
      child: InkWell(
        onTap: onTap == null ? null : () => Future.microtask(onTap!),
        borderRadius: BorderRadius.circular(AppTokens.radius),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radius),
            border: isColored ? null : Border.all(color: AppTokens.border.withValues(alpha: 0.8)),
            boxShadow: isColored ? null : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(AppTokens.s20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: subColor,
                        letterSpacing: 0.2,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(AppTokens.s8),
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(AppTokens.radiusS),
                    ),
                    child: Icon(icon, size: 18, color: iconColor),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.s8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                  color: textColor,
                ),
              ),
              if (trend != null) ...[
                const SizedBox(height: AppTokens.s10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isColored ? Colors.black.withValues(alpha: 0.1) : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    trend!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isColored
                          ? Colors.white.withValues(alpha: 0.9)
                          : (isPositive ? AppTokens.success : AppTokens.destructive),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  final String label;
  final String status;

  const StatusBadge({
    super.key,
    required this.label,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    Color bg = AppTokens.muted;
    Color fg = AppTokens.mutedForeground;
    Color border = AppTokens.border;

    switch (status.toLowerCase()) {
      case 'active':
      case 'paid':
      case 'open':
      case 'approved':
        bg = AppTokens.success.withValues(alpha: 0.15);
        fg = AppTokens.success;
        border = AppTokens.success.withValues(alpha: 0.2);
        break;
      case 'inactive':
      case 'closed':
      case 'expired':
        bg = AppTokens.muted;
        fg = AppTokens.mutedForeground;
        border = AppTokens.border;
        break;
      case 'pending':
      case 'under_review':
        bg = AppTokens.warning.withValues(alpha: 0.15);
        fg = AppTokens.warning;
        border = AppTokens.warning.withValues(alpha: 0.2);
        break;
      case 'cancelled':
      case 'rejected':
      case 'low':
        bg = AppTokens.destructive.withValues(alpha: 0.15);
        fg = AppTokens.destructive;
        border = AppTokens.destructive.withValues(alpha: 0.2);
        break;
      case 'credit':
      case 'shared':
        bg = AppTokens.info.withValues(alpha: 0.15);
        fg = AppTokens.info;
        border = AppTokens.info.withValues(alpha: 0.2);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTokens.radiusS),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? description;
  final List<Widget>? actions;

  const SectionHeader({
    super.key,
    required this.title,
    this.description,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    description!,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTokens.mutedForeground,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actions != null) ...[
            const SizedBox(width: AppTokens.s16),
            Row(children: actions!),
          ],
        ],
      ),
    );
  }
}

/// Shell wrapper for DataTable that provides consistent styling:
/// - Card-like container with border and rounded corners
/// - Horizontal scroll for overflow
/// - Optional title header
/// - Proper heading row background via theme
class DataTableShell extends StatelessWidget {
  final Widget child;
  final String? title;
  /// Set to false when using FlexTable — it fills width on its own and
  /// must not be wrapped in a horizontal SingleChildScrollView.
  final bool scrollable;

  const DataTableShell({
    super.key,
    required this.child,
    this.title,
    this.scrollable = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTokens.card,
        borderRadius: BorderRadius.circular(AppTokens.radius),
        border: Border.all(color: AppTokens.border.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.all(AppTokens.s20),
              child: Text(
                title!,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTokens.foreground,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            const Divider(height: 1, color: AppTokens.border),
          ],
          ClipRRect(
            borderRadius: title != null
                ? const BorderRadius.vertical(
                    bottom: Radius.circular(AppTokens.radius),
                  )
                : BorderRadius.circular(AppTokens.radius),
            child: scrollable
                ? Theme(
                    data: Theme.of(context).copyWith(
                      dividerColor: Colors.transparent,
                      dataTableTheme: DataTableThemeData(
                        headingRowColor: WidgetStateProperty.all(AppTokens.muted.withValues(alpha: 0.5)),
                        headingTextStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppTokens.foreground,
                          fontSize: 13,
                        ),
                        dataTextStyle: const TextStyle(
                          fontSize: 13,
                          color: AppTokens.foreground,
                        ),
                      ),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: constraints.maxWidth.isFinite ? constraints.maxWidth : 0,
                            ),
                            child: child,
                          ),
                        );
                      },
                    ),
                  )
                : child,
          ),
        ],
      ),
    );
  }
}

class FlexTableColumn {
  const FlexTableColumn({
    required this.label,
    this.flex = 1,
    this.numeric = false,
  });

  final String label;
  final int flex;
  final bool numeric;
}

class FlexTable extends StatelessWidget {
  const FlexTable({
    super.key,
    required this.columns,
    required this.rows,
  });

  final List<FlexTableColumn> columns;
  final List<List<Widget>> rows;

  static const _headerBg = Color(0xFFF8FAFC);
  static const _divider = Color(0xFFE2E8F0);
  static const _headerColor = Color(0xFF475569);

  @override
  Widget build(BuildContext context) {
    final colWidths = <int, TableColumnWidth>{
      for (int i = 0; i < columns.length; i++)
        i: FlexColumnWidth(columns[i].flex.toDouble()),
    };

    return Table(
      columnWidths: colWidths,
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: const BoxDecoration(color: _headerBg),
          children: columns
              .map((c) => _cell(
                    Text(
                      c.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: _headerColor,
                      ),
                      textAlign: c.numeric ? TextAlign.right : TextAlign.left,
                    ),
                    isHeader: true,
                    numeric: c.numeric,
                  ))
              .toList(),
        ),
        for (int r = 0; r < rows.length; r++)
          TableRow(
            decoration: BoxDecoration(
              color: r.isOdd ? const Color(0xFFFAFAFA) : Colors.white,
              border: const Border(top: BorderSide(color: _divider)),
            ),
            children: rows[r]
                .asMap()
                .entries
                .map((e) => _cell(
                      DefaultTextStyle.merge(
                        style: const TextStyle(fontSize: 13),
                        textAlign: columns[e.key].numeric ? TextAlign.right : TextAlign.left,
                        child: e.value,
                      ),
                      numeric: columns[e.key].numeric,
                    ))
                .toList(),
          ),
      ],
    );
  }

  Widget _cell(Widget child, {bool isHeader = false, bool numeric = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: isHeader ? 12 : 14,
      ),
      child: Align(
        alignment: numeric ? Alignment.centerRight : Alignment.centerLeft,
        child: child,
      ),
    );
  }
}
