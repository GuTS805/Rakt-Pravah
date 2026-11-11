import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/backend_error.dart';
import '../../data/providers.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// Asks what went wrong and files it for the operators, who see it under
/// Reports in the console. [requestId] and [userId] say what the report is
/// about when it comes from a chat or a request.
Future<void> showReportSheet(
  BuildContext context, {
  String title = 'Report a problem',
  String prompt =
      'Tell us what went wrong: misuse, a safety concern, or a bug. '
      'Our team reviews every report.',
  String? requestId,
  String? userId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _ReportSheet(
      title: title,
      prompt: prompt,
      requestId: requestId,
      userId: userId,
    ),
  );
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({
    required this.title,
    required this.prompt,
    this.requestId,
    this.userId,
  });

  final String title;
  final String prompt;
  final String? requestId;
  final String? userId;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  final _detail = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final detail = _detail.text.trim();
    if (detail.isEmpty) {
      setState(() => _error = 'Describe the problem first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(backendProvider)
          .fileReport(
            detail: detail,
            requestId: widget.requestId,
            userId: widget.userId,
          );
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Report sent. Thank you.')),
      );
    } on BackendUnavailable catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Couldn\'t send the report. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.xxl + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: context.text.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          Text(widget.prompt, style: context.text.bodyMedium),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _detail,
            maxLines: 4,
            maxLength: 1000,
            // Once they start typing, "describe the problem first" is stale.
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: const InputDecoration(
              hintText: 'Describe the problem…',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              style: context.text.bodySmall?.copyWith(color: c.danger),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: c.brand,
                minimumSize: const Size.fromHeight(48),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Submit report'),
            ),
          ),
        ],
      ),
    );
  }
}
