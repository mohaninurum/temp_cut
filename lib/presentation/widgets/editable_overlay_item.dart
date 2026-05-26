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
  final VoidCallback onEditTap;

  const EditableOverlayItemWidget({
    Key? key,
    required this.item,
    required this.canvasSize,
    required this.currentPlaybackTime,
    required this.onEditTap,
  }) : super(key: key);

  @override
  ConsumerState<EditableOverlayItemWidget> createState() => _EditableOverlayItemWidgetState();
}

class _EditableOverlayItemWidgetState extends ConsumerState<EditableOverlayItemWidget> {
  final GlobalKey _key = GlobalKey();
  
  bool _isSnappingV = false;
  bool _isSnappingH = false;

  void _onMatrixUpdate(Matrix4 m, Matrix4 tm, Matrix4 sm, Matrix4 rm) {
    final translation = vector_math.Vector3.zero();
    final rotation = vector_math.Quaternion.identity();
    final scale = vector_math.Vector3.zero();
    
    m.decompose(translation, rotation, scale);
    final eulerAngles = _getEulerAngles(rotation);
    
    double dx = translation.x;
    double dy = translation.y;

    // Haptic & Snapping Logic
    // We assume the widget center is roughly at dx + 50, dy + 50 for simplicity if we don't measure exactly
    // but a better approach is to check if it's near the center.
    final centerX = widget.canvasSize.width / 2;
    final centerY = widget.canvasSize.height / 2;
    
    bool snapV = false;
    bool snapH = false;

    // Soft snap radius
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

    // Notify parent for guidelines
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(guidelineProvider.notifier).state = {'v': snapV, 'h': snapH};
    });

    final updatedItem = widget.item.copyWith(
      position: Offset(dx, dy),
      scale: scale.x,
      rotation: eulerAngles.z,
    );

    ref.read(manualEditorProvider.notifier).updateOverlay(updatedItem);
  }

  vector_math.Vector3 _getEulerAngles(vector_math.Quaternion q) {
    double ysqr = q.y * q.y;
    double t3 = 2.0 * (q.w * q.z + q.x * q.y);
    double t4 = 1.0 - 2.0 * (ysqr + q.z * q.z);
    return vector_math.Vector3(0, 0, math.atan2(t3, t4));
  }

  @override
  Widget build(BuildContext context) {
    // 3. Interactive Overlay Canvas (Enhanced): Visibility logic
    final isVisible = widget.currentPlaybackTime >= widget.item.startTime && 
                      widget.currentPlaybackTime <= widget.item.endTime;

    if (!isVisible) return const SizedBox.shrink();

    final matrix = Matrix4.identity()
      ..translate(widget.item.position.dx, widget.item.position.dy)
      ..rotateZ(widget.item.rotation)
      ..scale(widget.item.scale);

    return Positioned(
      left: 0,
      top: 0,
      child: Listener(
        onPointerUp: (_) {
          _isSnappingV = false;
          _isSnappingH = false;
          ref.read(guidelineProvider.notifier).state = {'v': false, 'h': false};
        },
        child: MatrixGestureDetector(
          onMatrixUpdate: _onMatrixUpdate,
          child: GestureDetector(
            onTap: widget.onEditTap,
            child: Transform(
              transform: matrix,
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
