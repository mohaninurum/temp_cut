import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'dart:math' as math;
import 'package:matrix_gesture_detector/matrix_gesture_detector.dart';
import 'package:vector_math/vector_math_64.dart' as vector_math;

import '../../domain/models/overlay_item.dart';

// Provides guideline visibility state to the parent screen
final guidelineProvider = StateProvider<Map<String, bool>>((ref) => {'v': false, 'h': false});

class EditableOverlayItemWidget extends ConsumerStatefulWidget {
  final OverlayItem item;
  final Size canvasSize;
  final Duration currentPlaybackTime;
  final bool isSelected;
  final VoidCallback onEditTap;
  final void Function(OverlayItem)? onUpdate;

  const EditableOverlayItemWidget({
    Key? key,
    required this.item,
    required this.canvasSize,
    required this.currentPlaybackTime,
    this.isSelected = false,
    required this.onEditTap,
    this.onUpdate,
  }) : super(key: key);

  @override
  ConsumerState<EditableOverlayItemWidget> createState() => _EditableOverlayItemWidgetState();
}

class _EditableOverlayItemWidgetState extends ConsumerState<EditableOverlayItemWidget> {
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

  Offset _widgetCenterGlobal = Offset.zero;
  Offset _initialVector = Offset.zero;
  double _initialDistance = 1.0;
  double _initialAngle = 0.0;

  void _onItemPanStart(DragStartDetails details) {
    _basePosition = widget.item.position;
  }

  void _onItemPanUpdate(DragUpdateDetails details) {
    Offset newPosition = _basePosition + details.delta;
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
    );

    if (widget.onUpdate != null) {
      widget.onUpdate!(updatedItem);
    }
  }

  void _onItemPanEnd(DragEndDetails details) {
    _isSnappingV = false;
    _isSnappingH = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(guidelineProvider.notifier).state = {'v': false, 'h': false};
    });
  }

  void _onHandlePanStart(DragStartDetails details) {
    _baseScale = widget.item.scale;
    _baseRotation = widget.item.rotation;
    
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      _widgetCenterGlobal = renderBox.localToGlobal(renderBox.size.center(Offset.zero));
      _initialVector = details.globalPosition - _widgetCenterGlobal;
      _initialDistance = _initialVector.distance;
      _initialAngle = _initialVector.direction;
    }
  }

  void _onResizePanUpdate(DragUpdateDetails details) {
    if (_initialDistance == 0) return;
    
    final currentVector = details.globalPosition - _widgetCenterGlobal;
    final currentDistance = currentVector.distance;

    final scaleDelta = currentDistance / _initialDistance;

    double newScale = (_baseScale * scaleDelta).clamp(0.1, 5.0);

    if (widget.onUpdate != null) {
      widget.onUpdate!(
        widget.item.copyWith(
          scale: newScale,
        ),
      );
    }
  }

  void _onRotatePanUpdate(DragUpdateDetails details) {
    if (_initialDistance == 0) return;
    
    final currentVector = details.globalPosition - _widgetCenterGlobal;
    final currentAngle = currentVector.direction;

    final angleDelta = currentAngle - _initialAngle;

    double newRotation = _baseRotation + angleDelta;

    if (widget.onUpdate != null) {
      widget.onUpdate!(
        widget.item.copyWith(
          rotation: newRotation,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.item.type == OverlayType.audio) return const SizedBox.shrink();

    final isVisible = widget.currentPlaybackTime >= widget.item.startTime && 
                      widget.currentPlaybackTime <= widget.item.endTime;

    if (!isVisible) return const SizedBox.shrink();

    return Positioned(
      left: widget.item.position.dx,
      top: widget.item.position.dy,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: _onItemPanStart,
        onPanUpdate: _onItemPanUpdate,
        onPanEnd: _onItemPanEnd,
        onTap: widget.onEditTap,
        child: Transform.rotate(
          angle: widget.item.rotation,
          child: Transform.scale(
            scale: widget.item.scale,
            child: _applyAnimations(
                widget.isSelected
                    ? Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            margin: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                            child: _buildStyledContent(),
                          ),
                          Positioned(
                            top: 8, left: 8, 
                            child: Transform.scale(scale: 1.0 / widget.item.scale, child: _buildCornerHandle()),
                          ),
                          Positioned(
                            top: 8, right: 8, 
                            child: Transform.scale(scale: 1.0 / widget.item.scale, child: _buildCornerHandle()),
                          ),
                          Positioned(
                            bottom: 8, left: 8, 
                            child: Transform.scale(scale: 1.0 / widget.item.scale, child: _buildCornerHandle()),
                          ),
                          Positioned(
                            bottom: 0, 
                            right: 0, 
                            child: Transform.scale(
                              scale: 1.0 / widget.item.scale,
                              alignment: Alignment.bottomRight,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanStart: _onHandlePanStart,
                                onPanUpdate: _onResizePanUpdate,
                                child: Container(
                                  color: Colors.transparent,
                                  width: 64,
                                  height: 64,
                                  alignment: Alignment.bottomRight,
                                  padding: const EdgeInsets.only(right: 12, bottom: 12),
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 2)],
                                    ),
                                    child: const Icon(Icons.zoom_out_map, color: Colors.black, size: 16),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0, 
                            left: 64, 
                            right: 64,
                            child: Transform.scale(
                              scale: 1.0 / widget.item.scale,
                              alignment: Alignment.bottomCenter,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanStart: _onHandlePanStart,
                                onPanUpdate: _onRotatePanUpdate,
                                child: Container(
                                  color: Colors.transparent,
                                  height: 48,
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: const BoxDecoration(
                                        color: Colors.white, 
                                        shape: BoxShape.circle, 
                                        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 2)],
                                      ),
                                      child: const Icon(Icons.refresh, color: Colors.black, size: 16),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : Container(margin: const EdgeInsets.all(32), child: _buildStyledContent()),
              ),
            ),
          ),
        ),
      );
  }

  Widget _applyAnimations(Widget child) {
    final dur = widget.item.animationDuration * 1000;
    if (dur <= 0) return child; // safety

    final tIn = (widget.currentPlaybackTime - widget.item.startTime).inMilliseconds / dur;
    final tOut = (widget.item.endTime - widget.currentPlaybackTime).inMilliseconds / dur;

    double scale = 1.0;
    double opacity = 1.0;
    double rotation = 0.0;
    Offset translation = Offset.zero;

    // In Animation
    if (widget.item.animationIn != 'None' && tIn < 1.0 && tIn >= 0.0) {
      final p = Curves.easeOut.transform(tIn);
      _applyAnimLogic(widget.item.animationIn, p, true, (s, o, r, t) {
        scale = s; opacity = o; rotation = r; translation = t;
      });
    }
    // Loop Animation
    else if (widget.item.animationLoop != 'None') {
      final tLoop = ((widget.currentPlaybackTime - widget.item.startTime).inMilliseconds % dur) / dur;
      final p = tLoop; 
      _applyAnimLogic(widget.item.animationLoop, p, false, (s, o, r, t) {
        scale = s; opacity = o; rotation = r; translation = t;
      });
    }

    // Out Animation (overrides if ending)
    if (widget.item.animationOut != 'None' && tOut < 1.0 && tOut >= 0.0) {
      final p = Curves.easeIn.transform(tOut); // 1.0 -> 0.0
      _applyAnimLogic(widget.item.animationOut, p, true, (s, o, r, t) {
        scale = s; opacity = o; rotation = r; translation = t;
      });
    }

    Widget animatedChild = child;
    if (translation != Offset.zero) animatedChild = Transform.translate(offset: translation, child: animatedChild);
    if (scale != 1.0) animatedChild = Transform.scale(scale: scale, child: animatedChild);
    if (rotation != 0.0) animatedChild = Transform.rotate(angle: rotation, child: animatedChild);
    if (opacity != 1.0) animatedChild = Opacity(opacity: opacity.clamp(0.0, 1.0), child: animatedChild);

    return animatedChild;
  }

  void _applyAnimLogic(String type, double p, bool isInOrOut, Function(double s, double o, double r, Offset t) apply) {
    double s = 1.0, o = 1.0, r = 0.0; Offset t = Offset.zero;
    if (isInOrOut) {
      switch (type) {
        case 'Fade': o = p; break;
        case 'Scale': s = p; o = p.clamp(0.0, 1.0); break;
        case 'Spin': r = (1.0 - p) * -3.14159 * 2; s = p; break;
        case 'Slide': t = Offset(0, (1.0 - p) * 100); o = p; break;
        case 'Reveal': s = p; break;
        case 'Gradient': o = p; break;
      }
    } else {
      // Loop animations
      final cycle = p > 0.5 ? 2*(1-p) : 2*p; 
      final eased = Curves.easeInOut.transform(cycle);
      switch (type) {
        case 'Fade': o = 0.3 + 0.7 * eased; break;
        case 'Scale': s = 0.8 + 0.2 * eased; break;
        case 'Spin': r = p * 3.14159 * 2; break;
        case 'Slide': t = Offset(0, 20 * eased); break;
        case 'Reveal': s = 0.9 + 0.1 * eased; break;
        case 'Gradient': o = 0.5 + 0.5 * eased; break;
      }
    }
    apply(s, o, r, t);
  }

  Widget _buildHandle() {
    return Container(); // Deprecated, use _buildCornerHandle
  }

  Widget _buildCornerHandle() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: _onHandlePanStart,
      onPanUpdate: _onResizePanUpdate,
      child: Container(
        color: Colors.transparent,
        width: 48,
        height: 48,
        alignment: Alignment.center,
        child: Container(
          width: 12, height: 12,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 2)],
          ),
        ),
      ),
    );
  }

  Widget _buildStyledContent() {
    if (widget.item.type == OverlayType.image) {
      return Container(
        constraints: const BoxConstraints(maxWidth: 200, maxHeight: 200),
        child: Image.file(
          File(widget.item.value), // Assuming 'value' stores the file path
          fit: BoxFit.contain,
        ),
      );
    } else if (widget.item.type == OverlayType.emoji) {
      return Container(
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
