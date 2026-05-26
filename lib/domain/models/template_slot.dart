/// Represents the expected media type for a specific slot in a template.
enum SlotMediaType { video, image, any }

/// Defines a specific time window and media requirement within a video template.
class TemplateSlot {
  /// Unique identifier for this media slot.
  final String slotId;
  
  /// The start time for when this slot's media should begin playing.
  final Duration startTime;
  
  /// The end time for when this slot's media should stop playing.
  final Duration endTime;
  
  /// The type of media expected in this slot (video, image, or any).
  final SlotMediaType expectedType;

  /// Creates a new [TemplateSlot].
  const TemplateSlot({
    required this.slotId,
    required this.startTime,
    required this.endTime,
    required this.expectedType,
  });

  /// Converts this [TemplateSlot] to a Map for serialization.
  Map<String, dynamic> toMap() {
    return {
      'slotId': slotId,
      'startTimeMs': startTime.inMilliseconds,
      'endTimeMs': endTime.inMilliseconds,
      'expectedType': expectedType.name,
    };
  }

  /// Creates a [TemplateSlot] from a serialized Map.
  factory TemplateSlot.fromMap(Map<String, dynamic> map) {
    return TemplateSlot(
      slotId: map['slotId'] as String,
      startTime: Duration(milliseconds: map['startTimeMs'] as int),
      endTime: Duration(milliseconds: map['endTimeMs'] as int),
      expectedType: SlotMediaType.values.firstWhere(
        (e) => e.name == map['expectedType'],
        orElse: () => SlotMediaType.any,
      ),
    );
  }

  /// Creates a [TemplateSlot] from a JSON object (same as fromMap).
  factory TemplateSlot.fromJson(Map<String, dynamic> json) => TemplateSlot.fromMap(json);
}
