import 'package:flutter/material.dart';

enum OverlayType { text, emoji, image, video, mainVideo, mainImage, audio }
enum TextStyleMode { normal, solid, glassmorphic, neon }

class OverlayItem {
  final String id;
  final OverlayType type;
  final String value;
  final Offset position;
  final double scale;
  final double rotation;
  
  // New Timeline Duration fields
  final Duration startTime;
  final Duration endTime;

  // New Styling fields
  final TextStyleMode textStyleMode;
  final TextAlign textAlign;
  final double curveFactor; // 0.0 means straight, >0 means curved
  
  // Animation fields
  final String animationIn;
  final String animationOut;
  final String animationLoop;
  final double animationDuration;

  const OverlayItem({
    required this.id,
    required this.type,
    required this.value,
    this.position = Offset.zero,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.startTime = Duration.zero,
    this.endTime = const Duration(seconds: 10), // Default high duration, adjusted later
    this.textStyleMode = TextStyleMode.normal,
    this.textAlign = TextAlign.center,
    this.curveFactor = 0.0,
    this.animationIn = 'None',
    this.animationOut = 'None',
    this.animationLoop = 'None',
    this.animationDuration = 0.6,
  });

  OverlayItem copyWith({
    String? id,
    OverlayType? type,
    Offset? position,
    double? scale,
    double? rotation,
    String? value,
    Duration? startTime,
    Duration? endTime,
    TextStyleMode? textStyleMode,
    TextAlign? textAlign,
    double? curveFactor,
    String? animationIn,
    String? animationOut,
    String? animationLoop,
    double? animationDuration,
  }) {
    return OverlayItem(
      id: id ?? this.id,
      type: type ?? this.type,
      value: value ?? this.value,
      position: position ?? this.position,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      textStyleMode: textStyleMode ?? this.textStyleMode,
      textAlign: textAlign ?? this.textAlign,
      curveFactor: curveFactor ?? this.curveFactor,
      animationIn: animationIn ?? this.animationIn,
      animationOut: animationOut ?? this.animationOut,
      animationLoop: animationLoop ?? this.animationLoop,
      animationDuration: animationDuration ?? this.animationDuration,
    );
  }
}
