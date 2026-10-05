import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// Reusable searchable dropdown field that opens a fast filter dialog/sheet.
class SearchableLocationPicker<T> extends StatelessWidget {
  const SearchableLocationPicker({
    super.key,
    required this.title,
    required this.hintText,
    required this.items,
    required this.itemTitle,
    this.itemSubtitle,
    this.itemTrailing,
    this.selectedItem,
    this.selectedValueText,
    required this.onSelected,
    this.enabled = true,
    this.disabledHint,
    this.searchHint = 'Search...',
    this.prefixIcon = Icons.location_on_outlined,
    this.allowCustom = false,
    this.onCustomSelected,
    this.fieldKey,
  });

  final String title;
  final String hintText;
  final List<T> items;
  final String Function(T) itemTitle;
  final String Function(T)? itemSubtitle;
  final Widget Function(T)? itemTrailing;
  final T? selectedItem;
  final String? selectedValueText;
  final ValueChanged<T> onSelected;
  final bool enabled;
  final String? disabledHint;
  final String searchHint;
  final IconData prefixIcon;
  final bool allowCustom;
  final ValueChanged<String>? onCustomSelected;
  final Key? fieldKey;

  Future<void> _openPicker(BuildContext context) async {
    if (!enabled) return;

    final result = await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SearchPickerSheet<T>(
        title: title,
        searchHint: searchHint,
        items: items,
        itemTitle: itemTitle,
        itemSubtitle: itemSubtitle,
        itemTrailing: itemTrailing,
        selectedItem: selectedItem,
        allowCustom: allowCustom,
        onCustomSelected: onCustomSelected,
      ),
    );

    if (result != null) {
      onSelected(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayText = selectedValueText ??
        (selectedItem != null ? itemTitle(selectedItem as T) : '');
    final hasValue = displayText.trim().isNotEmpty;

    return InkWell(
      key: fieldKey,
      onTap: enabled ? () => _openPicker(context) : null,
      borderRadius: BorderRadius.circular(AppRadius.input),
      child: InputDecorator(
        isEmpty: !hasValue,
        decoration: InputDecoration(
          prefixIcon: Icon(
            prefixIcon,
            color: enabled
                ? (hasValue ? context.colors.brand : context.colors.textSecondary)
                : context.colors.textTertiary,
          ),
          suffixIcon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: enabled ? context.colors.textSecondary : context.colors.textTertiary,
          ),
          hintText: enabled ? hintText : (disabledHint ?? hintText),
          enabled: enabled,
          filled: true,
          fillColor: enabled
              ? context.colors.surface
              : context.colors.surface.withValues(alpha: 0.5),
        ),
        child: Text(
          hasValue ? displayText : '',
          style: context.text.bodyMedium?.copyWith(
            color: enabled ? context.colors.textPrimary : context.colors.textTertiary,
            fontWeight: hasValue ? FontWeight.w500 : FontWeight.normal,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class SearchPickerSheet<T> extends StatefulWidget {
  const SearchPickerSheet({
    super.key,
    required this.title,
    required this.searchHint,
    required this.items,
    required this.itemTitle,
    this.itemSubtitle,
    this.itemTrailing,
    this.selectedItem,
    this.allowCustom = false,
    this.onCustomSelected,
  });

  final String title;
  final String searchHint;
  final List<T> items;
  final String Function(T) itemTitle;
  final String Function(T)? itemSubtitle;
  final Widget Function(T)? itemTrailing;
  final T? selectedItem;
  final bool allowCustom;
  final ValueChanged<String>? onCustomSelected;

  @override
  State<SearchPickerSheet<T>> createState() => _SearchPickerSheetState<T>();
}

class _SearchPickerSheetState<T> extends State<SearchPickerSheet<T>> {
  final _searchController = TextEditingController();
  List<T> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.items;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = widget.items;
      } else {
        _filtered = widget.items.where((item) {
          final title = widget.itemTitle(item).toLowerCase();
          final subtitle = widget.itemSubtitle?.call(item).toLowerCase() ?? '';
          return title.contains(q) || subtitle.contains(q);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isDesktop = media.size.width > 600;

    return Container(
      constraints: BoxConstraints(
        maxHeight: media.size.height * (isDesktop ? 0.75 : 0.85),
      ),
      margin: isDesktop
          ? EdgeInsets.symmetric(
              horizontal: media.size.width * 0.2,
              vertical: media.size.height * 0.1,
            )
          : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.vertical(
          top: const Radius.circular(AppRadius.modal),
          bottom: isDesktop
              ? const Radius.circular(AppRadius.modal)
              : Radius.zero,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppSpacing.sm),
          // Handle pill
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.colors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: context.text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: TextField(
              key: const ValueKey('location-search-input'),
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: widget.searchHint,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _onSearch('');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
              ),
              onChanged: _onSearch,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_off_outlined,
                            size: 48,
                            color: context.colors.textTertiary,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'No matches found for "${_searchController.text}"',
                            style: context.text.bodyMedium?.copyWith(
                              color: context.colors.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (widget.allowCustom &&
                              _searchController.text.trim().isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.lg),
                            OutlinedButton.icon(
                              key: const ValueKey('use-custom-location-button'),
                              icon: const Icon(Icons.add_location_alt_outlined),
                              label: Text('Use "${_searchController.text.trim()}"'),
                              onPressed: () {
                                final custom = _searchController.text.trim();
                                Navigator.of(context).pop();
                                widget.onCustomSelected?.call(custom);
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _filtered.length + (widget.allowCustom ? 1 : 0),
                    separatorBuilder: (context, index) =>
                        Divider(height: 1, color: context.colors.border),
                    itemBuilder: (context, index) {
                      if (index == _filtered.length && widget.allowCustom) {
                        return ListTile(
                          key: const ValueKey('location-other-option'),
                          leading: CircleAvatar(
                            backgroundColor:
                                context.colors.brand.withValues(alpha: 0.1),
                            child: Icon(
                              Icons.add_location_outlined,
                              color: context.colors.brand,
                              size: 20,
                            ),
                          ),
                          title: const Text('Other location / district center'),
                          subtitle: const Text(
                            'Enter custom town or select nearest administrative center',
                          ),
                          onTap: () {
                            Navigator.of(context).pop();
                            widget.onCustomSelected?.call('');
                          },
                        );
                      }

                      final item = _filtered[index];
                      final title = widget.itemTitle(item);
                      final subtitle = widget.itemSubtitle?.call(item);
                      final trailing = widget.itemTrailing?.call(item);
                      final isSelected = widget.selectedItem == item;

                      return ListTile(
                        key: ValueKey('picker-item-$title'),
                        title: Text(
                          title,
                          style: context.text.bodyMedium?.copyWith(
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                            color: isSelected
                                ? context.colors.brand
                                : context.colors.textPrimary,
                          ),
                        ),
                        subtitle: subtitle != null
                            ? Text(
                                subtitle,
                                style: context.text.bodySmall?.copyWith(
                                  color: context.colors.textSecondary,
                                ),
                              )
                            : null,
                        trailing: trailing ??
                            (isSelected
                                ? Icon(
                                    Icons.check_circle_rounded,
                                    color: context.colors.brand,
                                    size: 20,
                                  )
                                : null),
                        onTap: () => Navigator.of(context).pop(item),
                      );
                    },
                  ),
          ),
          SizedBox(height: media.padding.bottom + AppSpacing.sm),
        ],
      ),
    );
  }
}
