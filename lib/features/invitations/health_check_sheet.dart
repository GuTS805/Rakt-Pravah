import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/buttons.dart';
import '../../data/models/models.dart';

/// Asks the donor the health questions right before they accept, since a
/// donor's situation can change between registering and a request arriving.
/// Resolves to true only when every question is answered "No" and the donor
/// confirms. The answers themselves are never stored or sent anywhere.
Future<bool> showHealthCheck(BuildContext context, {Gender? gender}) async {
  final passed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) =>
        _HealthCheckSheet(questions: HealthQuestion.forGender(gender)),
  );
  return passed ?? false;
}

class _HealthCheckSheet extends StatefulWidget {
  const _HealthCheckSheet({required this.questions});
  final List<HealthQuestion> questions;

  @override
  State<_HealthCheckSheet> createState() => _HealthCheckSheetState();
}

class _HealthCheckSheetState extends State<_HealthCheckSheet> {
  final _answers = <HealthQuestion, bool>{};

  bool get _allAnswered => _answers.length == widget.questions.length;
  bool get _anyYes => _answers.values.any((yes) => yes);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Before you accept', style: context.text.titleLarge),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Answer honestly so you don\'t travel to the hospital only '
                  'to be turned away. The blood bank checks again before you '
                  'donate. Your answers aren\'t saved.',
                  style: context.text.bodyMedium,
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              itemCount: widget.questions.length,
              separatorBuilder: (_, _) =>
                  Divider(height: AppSpacing.xl, color: c.border),
              itemBuilder: (context, i) {
                final q = widget.questions[i];
                return _QuestionRow(
                  question: q,
                  answer: _answers[q],
                  onAnswer: (yes) => setState(() => _answers[q] = yes),
                );
              },
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(top: BorderSide(color: c.border)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: _anyYes
                    ? SecondaryButton(
                        label: 'I can\'t donate this time',
                        onPressed: () => Navigator.pop(context, false),
                      )
                    : PrimaryButton(
                        label: 'Accept & help',
                        icon: Icons.favorite_rounded,
                        onPressed: _allAnswered
                            ? () => Navigator.pop(context, true)
                            : null,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionRow extends StatelessWidget {
  const _QuestionRow({
    required this.question,
    required this.answer,
    required this.onAnswer,
  });

  final HealthQuestion question;
  final bool? answer;
  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(question.question, style: context.text.bodyLarge),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            _AnswerChip(
              label: 'No',
              selected: answer == false,
              onTap: () => onAnswer(false),
            ),
            const SizedBox(width: AppSpacing.sm),
            _AnswerChip(
              label: 'Yes',
              selected: answer == true,
              onTap: () => onAnswer(true),
            ),
          ],
        ),
        if (answer == true) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: c.warningSubtle,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              question.deferral,
              style: context.text.bodySmall?.copyWith(color: c.textPrimary),
            ),
          ),
        ],
      ],
    );
  }
}

class _AnswerChip extends StatelessWidget {
  const _AnswerChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 72,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.brandSubtle : c.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected ? c.brand : c.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Text(
            label,
            style: context.text.labelLarge?.copyWith(
              color: selected ? c.brand : c.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
