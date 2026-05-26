import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' as math;
import 'package:matrix_gesture_detector/matrix_gesture_detector.dart';
import 'package:vector_math/vector_math_64.dart' as vector_math;

import '../../domain/models/overlay_item.dart';
import '../providers/manual_editor_provider.dart';

// Provides guideline visibility state to the parent screen
final guidelineProvider = StateProvider<Map<String, bool>>((ref) => {'v': false, 'h': false});

class EditableOverlayItemWidget extends ConsumerStatefulWidget {
  final OverlayItem item;
  final Size canvasSize;
  final Duration currentPlaybackTime;
  final bool isSelected;
  final VoidCallback onEditTap;

  const EditableOverlayItemWidget({
    Key? key,
    required this.item,
    required this.canvasSize,
    required this.currentPlaybackTime,
    this.isSelected = false,
    required this.onEditTap,
  }) : super(key: key);

  @override
  ConsumerState<EditableOverlayItemWidget> createState() => _EditableOverlayItemWidgetState();
}

class _EditableOverlayItemWidgetState extends ConsumerState<EditableOverlayItemWidget> {
  final GlobalKey _key = GlobalKey();
  
  bool _isSnappingV = false;
  bool _isSnappingH = false;

  double _baseScale = 1.0;
  double _baseRotation = 0.0;
  Offset _basePosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _baseScale = widget.item.scale;
    _baseRotation = widget.item.rotation;
    _basePosition = widget.item.position;
  }

  void _onScaleStart(ScaleStartDetails details) {
    _baseScale = widget.item.scale;
    _baseRotation = widget.item.rotation;
    _basePosition = widget.item.position;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    double newScale = _baseScale * details.scale;
    double newRotation = _baseRotation + details.rotation;
    Offset newPosition = _basePosition + details.focalPointDelta;
    
    // We update _basePosition continuously for drag deltas to work smoothly
    _basePosition = newPosition;

    final centerX = widget.canvasSize.width / 2;
    final centerY = widget.canvasSize.height / 2;
    
    bool snapV = false;
    bool snapH = false;

    // Use widget's approximate center based on its rendered position
    // Since Positioned left/top are the top-left corner, we estimate center by adding 50
    double dx = newPosition.dx;
    double dy = newPosition.dy;

    if ((dx + 50 - centerX).abs() < 15) {
      dx = centerX - 50;
      snapV = true;
    }
    if ((dy + 50 - centerY).abs() < 15) {
      dy = centerY - 50;
      snapH = true;
    }

    if (snapV && !_isSnappingV) HapticFeedback.lightImpact();
    if (snapH && !_isSnappingH) HapticFeedback.lightImpact();

    _isSnappingV = snapV;
    _isSnappingH = snapH;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(guidelineProvider.notifier).state = {'v': snapV, 'h': snapH};
    });

    final updatedItem = widget.item.copyWith(
      position: Offset(dx, dy),
      scale: newScale,
      rotation: newRotation,
    );

    ref.read(manualEditorProvider.notifier).updateOverlay(updatedItem);
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _isSnappingV = false;
    _isSnappingH = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(guidelineProvider.notifier).state = {'v': false, 'h': false};
    });
  }

  @override
  Widget build(BuildContext context) {
    final isVisible = widget.currentPlaybackTime >= widget.item.startTime && 
                      widget.currentPlaybackTime <= widget.item.endTime;

    if (!isVisible) return const SizedBox.shrink();

    return Positioned(
      left: widget.item.position.dx,
      top: widget.item.position.dy,
      child: GestureDetector(
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        onTap: widget.onEditTap,
        child: Transform.rotate(
          angle: widget.item.rotation,
          child: Transform.scale(
            scale: widget.item.scale,
            child: Container(
              decoration: widget.isSelected 
                  ? BoxDecoration(
                      border: Border.all(
                        color: widget.item.type == OverlayType.emoji ? Colors.pinkAccent : Colors.blueAccent, 
                        width: 2
                      ),
                      borderRadius: BorderRadius.circular(8),
                    )
                  : null,
              child: _buildStyledContent(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStyledContent() {
    if (widget.item.type != OverlayType.text) {
      return Container(
        key: _key,
        padding: const EdgeInsets.all(8),
        child: Text(widget.item.value, style: const TextStyle(fontSize: 48)),
      );
    }

    // 2. Instagram-Style Trending Text Customizer
    Widget textWidget = Text(
      widget.item.value,
      textAlign: widget.item.textAlign,
      style: TextStyle(
        color: Colors.white,
        fontSize: 28,
        fontWeight: FontWeight.bold,
        shadows: widget.item.textStyleMode == TextStyleMode.neon
            ? [const Shadow(color: Colors.pinkAccent, blurRadius: 15, offset: Offset(0, 0))]
            : [const Shadow(offset: Offset(1, 1), blurRadius: 2, color: Colors.black87)],
      ),
    );

    // Apply curve if active
    if (widget.item.curveFactor > 0.0) {
      // Basic mock implementation of curved text using rotation per character
      // For a production app, use flutter_arc_text. Here we do a manual arc layout.
      textWidget = _buildCurvedText(widget.item.value, widget.item.curveFactor);
    }

    BoxDecoration? decoration;
    if (widget.item.textStyleMode == TextStyleMode.solid) {
      decoration = BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
      );
    } else if (widget.item.textStyleMode == TextStyleMode.glassmorphic) {
      decoration = BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10),
        ],
      );
    }

    return Container(
      key: _key,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: decoration,
      child: textWidget,
    );
  }

  Widget _buildCurvedText(String text, double curveFactor) {
    // Simple custom arc logic
    final chars = text.split('');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: chars.asMap().entries.map((entry) {
        final index = entry.key;
        final char = entry.value;
        final middle = chars.length / 2;
        final offset = index - middle;
        // Curve equation
        final dy = math.pow(offset, 2) * curveFactor * 5;
        final angle = offset * curveFactor * 0.1;
        
        return Transform.translate(
          offset: Offset(0, dy.toDouble()),
          child: Transform.rotate(
            angle: angle,
            child: Text(
              char,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                shadows: [Shadow(offset: Offset(1, 1), blurRadius: 2, color: Colors.black87)],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
