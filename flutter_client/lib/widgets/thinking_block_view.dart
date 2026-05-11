import 'package:flutter/material.dart';
import '../models/message.dart';

class ThinkingBlockView extends StatefulWidget {
  final MirrorBlock block;
  const ThinkingBlockView({super.key, required this.block});

  @override
  State<ThinkingBlockView> createState() => _ThinkingBlockViewState();
}

class _ThinkingBlockViewState extends State<ThinkingBlockView>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _animCtrl;
  late Animation<double> _heightFactor;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _heightFactor = _animCtrl.drive(CurveTween(curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final content = widget.block.visibleContent.isNotEmpty
        ? widget.block.visibleContent
        : widget.block.content;
    final isStreaming = widget.block.status == MirrorStatus.streaming;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: LinearGradient(
            colors: [
              colorScheme.primary.withOpacity(0.07),
              colorScheme.tertiary.withOpacity(0.07),
            ],
          ),
          border: Border.all(
            color: colorScheme.primary.withOpacity(0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                setState(() {
                  _expanded = !_expanded;
                  if (_expanded) {
                    _animCtrl.forward();
                  } else {
                    _animCtrl.reverse();
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 16, height: 16,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Center(
                        child: Text('🧠',
                            style: TextStyle(fontSize: 10)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('Thinking',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary.withOpacity(0.8),
                        )),
                    if (isStreaming) ...[
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 12, height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.primary.withOpacity(0.6),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: colorScheme.onSurface.withOpacity(0.4),
                    ),
                  ],
                ),
              ),
            ),
            SizeTransition(
              sizeFactor: _heightFactor,
              axisAlignment: -1.0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                child: Text(
                  content,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
