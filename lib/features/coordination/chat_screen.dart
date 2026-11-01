import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/report_sheet.dart';
import '../../core/widgets/states.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';

/// Request-scoped private chat (spec §18). Messages come from the backend
/// stream (the canonical source); sends are optimistic and reconcile when the
/// backend confirms. A real build reconnects the WebSocket and re-fetches on
/// disconnect — the seam is the `chatProvider` stream.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.requestId});
  final String requestId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    _controller.clear();
    setState(() => _sending = true);
    try {
      await ref.read(backendProvider).sendMessage(widget.requestId, text);
      _scrollToBottom();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider);
    final async = ref.watch(chatProvider(widget.requestId));
    final req = ref.watch(requestProvider(widget.requestId)).valueOrNull;

    final isDonor = me != null && req != null && req.requesterId != me.id;
    final partnerName = isDonor
        ? req.requesterName
        : (req?.acceptedDonors.firstOrNull?.name ?? 'Coordination');
    final partnerPhoto = isDonor
        ? req.requesterPhoto
        : req?.acceptedDonors.firstOrNull?.photoUrl;
    final partnerInitials = Fmt.initials(partnerName);
    final partnerId = isDonor
        ? req.requesterId
        : req?.acceptedDonors.firstOrNull?.id;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        actions: [
          IconButton(
            tooltip: 'Report',
            icon: const Icon(Icons.flag_outlined),
            onPressed: () => showReportSheet(
              context,
              title: 'Report this chat',
              prompt:
                  'Tell us what happened. Our team reviews every report and '
                  'can switch off accounts that misuse Rakt Pravah.',
              requestId: widget.requestId,
              userId: partnerId,
            ),
          ),
        ],
        title: Row(
          children: [
            Avatar(
              initials: partnerInitials,
              photo: partnerPhoto,
              photoUrl: partnerPhoto,
              size: 36,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    partnerName,
                    style: context.text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Direct chat',
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorStateView(
                message: 'Couldn\'t load messages.',
                onRetry: () => ref.invalidate(chatProvider(widget.requestId)),
              ),
              data: (messages) {
                if (messages.isEmpty) {
                  return const EmptyState(
                    icon: Icons.forum_outlined,
                    title: 'Start the conversation',
                    message:
                        'Say hello and share any details needed to coordinate '
                        'the donation.',
                  );
                }
                _scrollToBottom();
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final m = messages[i];
                    final mine = m.senderId == me?.id;
                    return _Bubble(
                      message: m,
                      mine: mine,
                      avatarPhoto: mine ? me?.photo : partnerPhoto,
                      avatarInitials:
                          mine ? (me?.initials ?? 'Me') : partnerInitials,
                    );
                  },
                );
              },
            ),
          ),
          _Composer(controller: _controller, sending: _sending, onSend: _send),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    this.avatarPhoto,
    required this.avatarInitials,
  });

  final ChatMessage message;
  final bool mine;
  final String? avatarPhoto;
  final String avatarInitials;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg = mine ? c.brand : c.surface;
    final fg = mine ? c.onBrand : c.textPrimary;
    final avatar = Avatar(
      initials: avatarInitials,
      photo: avatarPhoto,
      photoUrl: avatarPhoto,
      size: 28,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine) ...[
            avatar,
            const SizedBox(width: AppSpacing.xs),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(AppRadius.lg),
                  topRight: const Radius.circular(AppRadius.lg),
                  bottomLeft: Radius.circular(mine ? AppRadius.lg : 4),
                  bottomRight: Radius.circular(mine ? 4 : AppRadius.lg),
                ),
                border: mine ? null : Border.all(color: c.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.text,
                    style: context.text.bodyLarge?.copyWith(color: fg),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        Fmt.clock(message.sentAt),
                        style: AppTypography.mono(
                          size: 10,
                          color: mine
                              ? c.onBrand.withValues(alpha: 0.75)
                              : c.textTertiary,
                        ),
                      ),
                      if (message.pending) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.schedule_rounded,
                          size: 11,
                          color: mine
                              ? c.onBrand.withValues(alpha: 0.75)
                              : c.textTertiary,
                        ),
                      ] else if (message.failed) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.error_outline_rounded,
                          size: 11,
                          color: c.warning,
                        ),
                      ] else if (mine) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.done_rounded,
                          size: 12,
                          color: c.onBrand.withValues(alpha: 0.75),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: InputDecoration(
                    hintText: 'Message…',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm + 2,
                    ),
                    fillColor: c.surfaceMuted,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Material(
                color: c.brand,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: sending ? null : onSend,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Icon(
                      Icons.arrow_upward_rounded,
                      color: c.onBrand,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
