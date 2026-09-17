import 'package:flutter/material.dart';

import '../../data/models/models.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import '../theme/semantics.dart';
import '../utils/formatters.dart';

/// The request lifecycle as a vertical timeline — the signature tracking
/// element. Completed steps are solid, the current step pulses while active,
/// and future steps are muted. Terminal non-happy states (cancelled / expired /
/// removed) are surfaced as a distinct final node.
class StatusTimeline extends StatelessWidget {
  const StatusTimeline({super.key, required this.request});

  final BloodRequest request;

  @override
  Widget build(BuildContext context) {
    final current = request.status;

    // Determine which lifecycle steps to show. If terminal-and-not-fulfilled,
    // we show progress up to where it stopped, then the terminal node.
    final steps = <RequestStatus>[...RequestStatus.lifecycle];
    final isUnhappyTerminal =
        current == RequestStatus.cancelled ||
        current == RequestStatus.expired ||
        current == RequestStatus.removedByAdmin;

    final reachedIndex = _reachedIndex(current);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < steps.length; i++)
          _TimelineNode(
            status: steps[i],
            state: _stateFor(i, reachedIndex, isUnhappyTerminal),
            isLast: i == steps.length - 1 && !isUnhappyTerminal,
            event: _eventFor(steps[i]),
          ),
        if (isUnhappyTerminal)
          _TimelineNode(
            status: current,
            state: _NodeState.terminal,
            isLast: true,
            event: _eventFor(current),
          ),
      ],
    );
  }

  StatusEvent? _eventFor(RequestStatus s) {
    for (final e in request.timeline.reversed) {
      if (e.status == s) return e;
    }
    return null;
  }

  int _reachedIndex(RequestStatus current) {
    switch (current) {
      case RequestStatus.created:
        return 0;
      case RequestStatus.searching:
        return 1;
      case RequestStatus.donorAccepted:
        return 2;
      case RequestStatus.coordinating:
        return 3;
      case RequestStatus.fulfilled:
        return 4;
      case RequestStatus.cancelled:
      case RequestStatus.expired:
      case RequestStatus.removedByAdmin:
        // Progress made before stopping — at least created.
        var reached = 0;
        for (final e in request.timeline) {
          final idx = RequestStatus.lifecycle.indexOf(e.status);
          if (idx > reached) reached = idx;
        }
        return reached;
    }
  }

  _NodeState _stateFor(int i, int reached, bool unhappy) {
    if (i < reached) return _NodeState.done;
    if (i == reached) return unhappy ? _NodeState.done : _NodeState.current;
    return _NodeState.upcoming;
  }
}

enum _NodeState { done, current, upcoming, terminal }

class _TimelineNode extends StatelessWidget {
  const _TimelineNode({
    required this.status,
    required this.state,
    required this.isLast,
    this.event,
  });

  final RequestStatus status;
  final _NodeState state;
  final bool isLast;
  final StatusEvent? event;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = statusStyle(context, status);

    final Color dotColor;
    final Color lineColor;
    final Color labelColor;
    switch (state) {
      case _NodeState.done:
        dotColor = c.success;
        lineColor = c.success.withValues(alpha: 0.4);
        labelColor = c.textPrimary;
        break;
      case _NodeState.current:
        dotColor = style.color;
        lineColor = c.border;
        labelColor = c.textPrimary;
        break;
      case _NodeState.upcoming:
        dotColor = c.border;
        lineColor = c.border;
        labelColor = c.textTertiary;
        break;
      case _NodeState.terminal:
        dotColor = style.color;
        lineColor = c.border;
        labelColor = c.textPrimary;
        break;
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              _Dot(color: dotColor, pulsing: state == _NodeState.current),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: lineColor,
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        status.label,
                        style: context.text.titleSmall?.copyWith(
                          color: labelColor,
                          fontWeight: state == _NodeState.current
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      if (event != null)
                        Text(
                          Fmt.clock(event!.at),
                          style: AppTypography.mono(
                            size: 11,
                            color: c.textTertiary,
                          ),
                        ),
                    ],
                  ),
                  if (event?.note != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      event!.note!,
                      style: context.text.bodySmall?.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                  ] else if (state == _NodeState.upcoming) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Pending',
                      style: context.text.bodySmall?.copyWith(
                        color: c.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  const _Dot({required this.color, required this.pulsing});
  final Color color;
  final bool pulsing;

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulsing) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant _Dot old) {
    super.didUpdateWidget(old);
    if (widget.pulsing && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.pulsing && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 22,
      width: 22,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.pulsing)
            AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                final t = _ctrl.value;
                return Container(
                  height: 10 + t * 12,
                  width: 10 + t * 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: (1 - t) * 0.35),
                  ),
                );
              },
            ),
          Container(
            height: 12,
            width: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
              border: Border.all(color: c.surface, width: 2),
            ),
          ),
        ],
      ),
    );
  }
}
