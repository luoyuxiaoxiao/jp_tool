/// Dependency focus view — hover a token to highlight its dependency links.
library;

import 'dart:math' as math;
import 'dart:ui' show Tangent;

import 'package:flutter/material.dart';

import '../models/analysis_result.dart';

class DependencyFocusView extends StatefulWidget {
  final List<Token> tokens;
  final String style;

  const DependencyFocusView({
    super.key,
    required this.tokens,
    this.style = 'classic',
  });

  @override
  State<DependencyFocusView> createState() => _DependencyFocusViewState();
}

class _DependencyFocusViewState extends State<DependencyFocusView> {
  int? _hoveredIndex;
  final GlobalKey _chipsAreaKey = GlobalKey();
  final Map<int, GlobalKey> _chipKeys = <int, GlobalKey>{};
  Map<int, Rect> _chipRects = <int, Rect>{};
  bool _rectSyncScheduled = false;

  bool get _isVivid => widget.style.trim().toLowerCase() == 'vivid';

  @override
  void didUpdateWidget(covariant DependencyFocusView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tokens.length != widget.tokens.length) {
      _chipKeys.removeWhere((index, _) => index >= widget.tokens.length);
      if (_hoveredIndex != null && _hoveredIndex! >= widget.tokens.length) {
        _hoveredIndex = null;
      }
      if (_isVivid) {
        _scheduleRectSync();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tokens.isEmpty) {
      return const SizedBox.shrink();
    }

    if (_isVivid) {
      _scheduleRectSync();
    }

    const focusTitle = 'GiNZA 依存聚焦（悬停查看修饰关系）';

    final content = MouseRegion(
      onExit: (_) {
        if (_hoveredIndex != null) {
          setState(() => _hoveredIndex = null);
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _isVivid ? null : Colors.white10,
          gradient: _isVivid
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0x2432E8FF),
                    Color(0x11262D3A),
                  ],
                )
              : null,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white24),
          boxShadow: [
            if (_isVivid && _hoveredIndex != null)
              const BoxShadow(
                color: Color(0x3320D8FF),
                blurRadius: 16,
                spreadRadius: 1,
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_tree_outlined,
                    size: 16, color: Colors.cyanAccent),
                const SizedBox(width: 6),
                Text(
                  focusTitle,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Stack(
              key: _chipsAreaKey,
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: (_isVivid &&
                                _hoveredIndex != null &&
                                _chipRects.isNotEmpty)
                            ? _DependencyLinkPainter(
                                tokens: widget.tokens,
                                hoveredIndex: _hoveredIndex!,
                                chipRects: _chipRects,
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 8,
                  children:
                      List.generate(widget.tokens.length, _buildTokenChip),
                ),
              ],
            ),
            if (_hoveredIndex != null) ...[
              const SizedBox(height: 10),
              _buildDependencyDetails(_hoveredIndex!),
            ],
          ],
        ),
      ),
    );

    return content;
  }

  Widget _buildTokenChip(int index) {
    final token = widget.tokens[index];
    final related = _isRelated(index);
    final selected = _hoveredIndex == index;
    final meaning = token.meaningZh.trim();
    final chipKey = _chipKeys.putIfAbsent(index, GlobalKey.new);

    final borderColor = selected
        ? Colors.cyanAccent
        : (token.isPunctuation ? Colors.white24 : Colors.white38);

    final textColor = token.isPunctuation
        ? Colors.grey
        : (selected ? Colors.cyanAccent : Colors.white);

    final chip = KeyedSubtree(
      key: chipKey,
      child: Padding(
        // Slightly expands hover hit area to reduce boundary jitter.
        padding: const EdgeInsets.all(1),
        child: Opacity(
          opacity: related ? 1.0 : 0.24,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color:
                  selected ? Colors.cyanAccent.withAlpha(28) : Colors.black26,
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                if (_isVivid && selected)
                  const BoxShadow(
                    color: Color(0x4420D8FF),
                    blurRadius: 10,
                    spreadRadius: 0.5,
                  ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  token.surface,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 16,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                SizedBox(
                  height: 13,
                  child: Text(
                    meaning.isEmpty ? '\u200B' : meaning,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected && meaning.isNotEmpty
                          ? const Color(0xFFFFD54F)
                          : Colors.transparent,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return MouseRegion(
      onEnter: (_) {
        if (_hoveredIndex != index) {
          setState(() => _hoveredIndex = index);
          if (_isVivid) {
            _scheduleRectSync();
          }
        }
      },
      child: chip,
    );
  }

  Widget _buildDependencyDetails(int hovered) {
    final token = widget.tokens[hovered];
    final headIdx = _safeIndex(token.headIndex);
    final children = <int>[];

    for (var i = 0; i < widget.tokens.length; i++) {
      if (i == hovered) continue;
      if (_safeIndex(widget.tokens[i].headIndex) == hovered) {
        children.add(i);
      }
    }

    final lines = <Widget>[
      if (headIdx != null && headIdx != hovered)
        _arrowLine(
          from: token.surface,
          to: widget.tokens[headIdx].surface,
          label: token.dep.trim().isNotEmpty ? token.dep.trim() : '修饰',
          color: Colors.cyanAccent,
        ),
      if (children.isNotEmpty)
        ...children.map(
          (idx) => _arrowLine(
            from: widget.tokens[idx].surface,
            to: token.surface,
            label: widget.tokens[idx].dep.trim().isNotEmpty
                ? widget.tokens[idx].dep.trim()
                : '修饰',
            color: Colors.orangeAccent,
          ),
        ),
      if ((headIdx == null || headIdx == hovered) && children.isEmpty)
        const Text(
          '该词当前没有可展示的依存连线。',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
    ];

    if (!_isVivid) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines,
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      child: Container(
        key: ValueKey<int>(hovered),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.black.withAlpha(38),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: lines,
        ),
      ),
    );
  }

  Widget _arrowLine({
    required String from,
    required String to,
    required String label,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(Icons.arrow_right_alt, size: 16, color: color),
          Text(
            '$from  ->  $to',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '($label)',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _scheduleRectSync() {
    if (!_isVivid || _rectSyncScheduled) {
      return;
    }
    _rectSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _rectSyncScheduled = false;
        return;
      }
      _rectSyncScheduled = false;
      _syncChipRects();
    });
  }

  void _syncChipRects() {
    if (!mounted || !_isVivid) {
      return;
    }

    final areaContext = _chipsAreaKey.currentContext;
    if (areaContext == null) {
      return;
    }

    final areaBox = areaContext.findRenderObject();
    if (areaBox is! RenderBox || !areaBox.attached) {
      return;
    }

    final next = <int, Rect>{};
    for (var i = 0; i < widget.tokens.length; i++) {
      final key = _chipKeys[i];
      final chipContext = key?.currentContext;
      if (chipContext == null) {
        continue;
      }

      final box = chipContext.findRenderObject();
      if (box is! RenderBox || !box.attached) {
        continue;
      }

      final topLeft = box.localToGlobal(Offset.zero, ancestor: areaBox);
      next[i] = topLeft & box.size;
    }

    if (!_sameRectMap(_chipRects, next)) {
      setState(() => _chipRects = next);
    }
  }

  bool _sameRectMap(Map<int, Rect> a, Map<int, Rect> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;

    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null) return false;
      if (!_close(entry.value, other)) return false;
    }
    return true;
  }

  bool _close(Rect x, Rect y) {
    const eps = 0.5;
    return (x.left - y.left).abs() <= eps &&
        (x.top - y.top).abs() <= eps &&
        (x.width - y.width).abs() <= eps &&
        (x.height - y.height).abs() <= eps;
  }

  bool _isRelated(int index) {
    final hovered = _hoveredIndex;
    if (hovered == null) return true;
    if (index == hovered) return true;

    final hoveredHead = _safeIndex(widget.tokens[hovered].headIndex);
    if (hoveredHead == index) return true;

    final tokenHead = _safeIndex(widget.tokens[index].headIndex);
    if (tokenHead == hovered) return true;

    return false;
  }

  int? _safeIndex(int idx) {
    if (idx < 0 || idx >= widget.tokens.length) return null;
    return idx;
  }
}

class _DependencyLinkPainter extends CustomPainter {
  final List<Token> tokens;
  final int hoveredIndex;
  final Map<int, Rect> chipRects;

  _DependencyLinkPainter({
    required this.tokens,
    required this.hoveredIndex,
    required this.chipRects,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final hoveredRect = chipRects[hoveredIndex];
    if (hoveredRect == null) {
      return;
    }

    final edges = <_DepEdge>[];
    final hovered = tokens[hoveredIndex];
    final head = hovered.headIndex;

    if (head >= 0 && head < tokens.length && head != hoveredIndex) {
      edges.add(
        _DepEdge(from: hoveredIndex, to: head, color: Colors.cyanAccent),
      );
    }

    for (var i = 0; i < tokens.length; i++) {
      if (i == hoveredIndex) continue;
      if (tokens[i].headIndex == hoveredIndex) {
        edges.add(
          _DepEdge(from: i, to: hoveredIndex, color: Colors.orangeAccent),
        );
      }
    }

    for (final edge in edges) {
      final fromRect = chipRects[edge.from];
      final toRect = chipRects[edge.to];
      if (fromRect == null || toRect == null) {
        continue;
      }

      final from = _anchor(fromRect, toRect);
      final to = _anchor(toRect, fromRect);

      final dx = (to.dx - from.dx).abs();
      final bend = math.max(18.0, math.min(56.0, dx * 0.22));
      final sign = from.dy <= to.dy ? -1.0 : 1.0;
      final c1 = Offset(
        from.dx + (to.dx - from.dx) * 0.30,
        from.dy + bend * sign,
      );
      final c2 = Offset(
        from.dx + (to.dx - from.dx) * 0.70,
        to.dy + bend * sign,
      );

      final path = Path()
        ..moveTo(from.dx, from.dy)
        ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, to.dx, to.dy);

      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 5.4
        ..color = edge.color.withAlpha(58)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawPath(path, glow);

      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2.2
        ..shader = LinearGradient(
          colors: [
            edge.color.withAlpha(70),
            edge.color,
            Colors.white.withAlpha(190),
          ],
          stops: const [0, 0.78, 1],
        ).createShader(Rect.fromPoints(from, to));
      canvas.drawPath(path, line);

      final metricList = path.computeMetrics().toList();
      if (metricList.isEmpty) {
        continue;
      }

      final metric = metricList.first;
      final endTangent = metric.getTangentForOffset(metric.length - 1);
      if (endTangent != null) {
        _drawArrowHead(canvas, endTangent, edge.color);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DependencyLinkPainter oldDelegate) {
    return oldDelegate.hoveredIndex != hoveredIndex ||
        !identical(oldDelegate.chipRects, chipRects) ||
        !identical(oldDelegate.tokens, tokens);
  }

  Offset _anchor(Rect from, Rect to) {
    if (to.center.dx >= from.center.dx) {
      return Offset(from.right, from.center.dy);
    }
    return Offset(from.left, from.center.dy);
  }

  void _drawArrowHead(Canvas canvas, Tangent tangent, Color color) {
    final dir = tangent.vector;
    final len = dir.distance;
    if (len < 0.001) return;

    final unit = Offset(dir.dx / len, dir.dy / len);
    final normal = Offset(-unit.dy, unit.dx);
    const headLen = 7.5;
    const wing = 3.8;

    final tip = tangent.position;
    final base = tip - unit * headLen;
    final left = base + normal * wing;
    final right = base - normal * wing;

    final arrow = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();

    canvas.drawPath(
      arrow,
      Paint()
        ..style = PaintingStyle.fill
        ..color = color.withAlpha(235),
    );
  }
}

class _DepEdge {
  final int from;
  final int to;
  final Color color;

  const _DepEdge({
    required this.from,
    required this.to,
    required this.color,
  });
}
