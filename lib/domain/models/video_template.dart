import 'package:flutter/material.dart';
import 'template_slot.dart';

/// Represents a predefined text overlay that appears automatically
/// at a certain time and position within a video template.
class TemplateTextOverlay {
  /// Unique identifier for this text overlay.
  final String textOverlayId;
  
  /// The predefined text value.
  final String value;
  
  /// When the text should appear in the template duration.
  final Duration appearanceStartTime;
  
  /// When the text should disappear in the template duration.
  final Duration appearanceEndTime;
  
  /// The horizontal position as a percentage of the screen width (0.0 to 1.0).
  final double xPercentage;
  
  /// The vertical position as a percentage of the screen height (0.0 to 1.0).
  final double yPercentage;
  
  /// Font size for the text.
  final double fontSize;
  
  /// Hex color code (e.g., "#FFFFFF").
  final String colorHex;

  /// Creates a new [TemplateTextOverlay].
  const TemplateTextOverlay({
    required this.textOverlayId,
    required this.value,
    required this.appearanceStartTime,
    required this.appearanceEndTime,
    required this.xPercentage,
    required this.yPercentage,
    this.fontSize = 24.0,
    this.colorHex = "#FFFFFF",
  });

  /// Converts to Map for serialization.
  Map<String, dynamic> toMap() {
    return {
      'textOverlayId': textOverlayId,
      'value': value,
      'appearanceStartTimeMs': appearanceStartTime.inMilliseconds,
      'appearanceEndTimeMs': appearanceEndTime.inMilliseconds,
      'xPercentage': xPercentage,
      'yPercentage': yPercentage,
      'fontSize': fontSize,
      'colorHex': colorHex,
    };
  }

  /// Creates an instance from a Map.
  factory TemplateTextOverlay.fromMap(Map<String, dynamic> map) {
    return TemplateTextOverlay(
      textOverlayId: map['textOverlayId'] as String,
      value: map['value'] as String,
      appearanceStartTime: Duration(milliseconds: map['appearanceStartTimeMs'] as int),
      appearanceEndTime: Duration(milliseconds: map['appearanceEndTimeMs'] as int),
      xPercentage: (map['xPercentage'] as num).toDouble(),
      yPercentage: (map['yPercentage'] as num).toDouble(),
      fontSize: (map['fontSize'] as num?)?.toDouble() ?? 24.0,
      colorHex: map['colorHex'] as String? ?? "#FFFFFF",
    );
  }

  /// Creates an instance from JSON.
  factory TemplateTextOverlay.fromJson(Map<String, dynamic> json) => TemplateTextOverlay.fromMap(json);
  
  /// Helper to get a Flutter Color from the hex code.
  Color get flutterColor {
    final hex = colorHex.replaceAll('#', '');
    if (hex.length == 6) {
      return Color(int.parse('FF$hex', radix: 16));
    }
    if (hex.length == 8) {
      return Color(int.parse(hex, radix: 16));
    }
    return Colors.white;
  }
}

/// Represents a complete video template structure, containing audio,
/// text overlays, and predefined media slots for users to fill.
class VideoTemplate {
  /// Unique identifier for this template.
  final String templateId;
  
  /// Display name of the template.
  final String templateName;
  
  /// URL or local asset path of the background audio for this template.
  final String audioUrl;
  
  /// The total duration of the template video.
  final Duration totalDuration;
  
  /// Pre-defined, synced text overlays that appear in the template.
  final List<TemplateTextOverlay> textOverlays;
  
  /// The media slots that the user needs to fill to complete the template.
  final List<TemplateSlot> mediaSlots;

  /// Creates a new [VideoTemplate].
  const VideoTemplate({
    required this.templateId,
    required this.templateName,
    required this.audioUrl,
    required this.totalDuration,
    required this.textOverlays,
    required this.mediaSlots,
  });

  /// Converts this [VideoTemplate] to a Map for serialization.
  Map<String, dynamic> toMap() {
    return {
      'templateId': templateId,
      'templateName': templateName,
      'audioUrl': audioUrl,
      'totalDurationMs': totalDuration.inMilliseconds,
      'textOverlays': textOverlays.map((x) => x.toMap()).toList(),
      'mediaSlots': mediaSlots.map((x) => x.toMap()).toList(),
    };
  }

  /// Creates a [VideoTemplate] from a serialized Map.
  factory VideoTemplate.fromMap(Map<String, dynamic> map) {
    return VideoTemplate(
      templateId: map['templateId'] as String,
      templateName: map['templateName'] as String? ?? 'Untitled Template',
      audioUrl: map['audioUrl'] as String,
      totalDuration: Duration(milliseconds: map['totalDurationMs'] as int),
      textOverlays: List<TemplateTextOverlay>.from(
        (map['textOverlays'] as List<dynamic>).map(
          (x) => TemplateTextOverlay.fromMap(x as Map<String, dynamic>),
        ),
      ),
      mediaSlots: List<TemplateSlot>.from(
        (map['mediaSlots'] as List<dynamic>).map(
          (x) => TemplateSlot.fromMap(x as Map<String, dynamic>),
        ),
      ),
    );
  }

  /// Creates a [VideoTemplate] from JSON.
  factory VideoTemplate.fromJson(Map<String, dynamic> json) => VideoTemplate.fromMap(json);
}
