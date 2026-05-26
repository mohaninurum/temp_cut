import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/template_slot.dart';
import '../../domain/models/video_template.dart';
import '../providers/editor_state_provider.dart';
import 'pure_template_editor_screen.dart';

/// Screen displaying a grid of available templates.
class TemplateBrowserScreen extends ConsumerWidget {
  const TemplateBrowserScreen({Key? key}) : super(key: key);

  /// Helper to provide a sample template for demonstration.
  VideoTemplate _getSampleTemplate() {
    return VideoTemplate(
      templateId: 'sample_template_1',
      templateName: 'Vlog Style 1',
      audioUrl: '', // Provide a valid audio asset URL here for testing
      totalDuration: const Duration(seconds: 10),
      mediaSlots: [
        const TemplateSlot(
          slotId: 'slot_1',
          startTime: Duration(seconds: 0),
          endTime: Duration(seconds: 4),
          expectedType: SlotMediaType.video,
        ),
        const TemplateSlot(
          slotId: 'slot_2',
          startTime: Duration(seconds: 4),
          endTime: Duration(seconds: 7),
          expectedType: SlotMediaType.image,
        ),
        const TemplateSlot(
          slotId: 'slot_3',
          startTime: Duration(seconds: 7),
          endTime: Duration(seconds: 10),
          expectedType: SlotMediaType.video,
        ),
      ],
      textOverlays: [
        const TemplateTextOverlay(
          textOverlayId: 'text_1',
          value: 'Hello World',
          appearanceStartTime: Duration(seconds: 1),
          appearanceEndTime: Duration(seconds: 3),
          xPercentage: 0.5,
          yPercentage: 0.2,
          fontSize: 40.0,
          colorHex: '#FFFFFF',
        ),
        const TemplateTextOverlay(
          textOverlayId: 'text_2',
          value: 'Awesome Vibes',
          appearanceStartTime: Duration(seconds: 5),
          appearanceEndTime: Duration(seconds: 8),
          xPercentage: 0.5,
          yPercentage: 0.8,
          fontSize: 32.0,
          colorHex: '#FFDD00',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Simulated list of templates
    final templates = [
      _getSampleTemplate(),
      _getSampleTemplate().copyWith(templateId: 'sample_2', templateName: 'Travel Reel'),
      _getSampleTemplate().copyWith(templateId: 'sample_3', templateName: 'Fashion Snap'),
    ];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Select Template'),
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 9 / 16,
        ),
        itemCount: templates.length,
        itemBuilder: (context, index) {
          final template = templates[index];
          return GestureDetector(
            onTap: () {
              // Initialize template in global state and navigate to the editor
              ref.read(editorStateProvider.notifier).loadTemplate(template);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PureTemplateEditorScreen()),
              );
            },
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24, width: 1),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.movie_creation_outlined, color: Colors.white, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    template.templateName,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${template.mediaSlots.length} Clips • ${template.totalDuration.inSeconds}s',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// Extension to help copy mock templates quickly
extension on VideoTemplate {
  VideoTemplate copyWith({String? templateId, String? templateName}) {
    return VideoTemplate(
      templateId: templateId ?? this.templateId,
      templateName: templateName ?? this.templateName,
      audioUrl: audioUrl,
      totalDuration: totalDuration,
      textOverlays: textOverlays,
      mediaSlots: mediaSlots,
    );
  }
}
