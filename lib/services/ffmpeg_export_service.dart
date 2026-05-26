import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/models/video_template.dart';

/// Service responsible for translating the declarative state of the editor
/// into an imperative, production-ready FFmpeg command for MP4 rendering.
class FFmpegExportService {
  /// Extracts the required TTF font file from Flutter assets into the document directory.
  /// This is strictly required because FFmpeg's `drawtext` needs an absolute system file path.
  static Future<String> _prepareFontFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final fontFile = File('${dir.path}/Roboto-Bold.ttf');
    
    // In a production environment, ensure this font is declared in pubspec.yaml.
    if (!await fontFile.exists()) {
      try {
        final byteData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
        await fontFile.writeAsBytes(byteData.buffer.asUint8List());
      } catch (e) {
        debugPrint('Warning: Could not load bundled font. Ensure it exists in assets. Error: $e');
      }
    }
    return fontFile.path;
  }

  /// Downloads or copies audio from a bundled asset so FFmpeg has absolute access to it.
  static Future<String?> _prepareAudioFile(String url) async {
    if (url.startsWith('http')) return url;
    if (url.isEmpty) return null;
    
    final dir = await getApplicationDocumentsDirectory();
    final fileName = url.split('/').last;
    final file = File('${dir.path}/$fileName');
    
    if (!await file.exists()) {
      try {
        final byteData = await rootBundle.load(url);
        await file.writeAsBytes(byteData.buffer.asUint8List());
      } catch (e) {
         debugPrint('Audio asset load error: $e');
         return null;
      }
    }
    return file.path;
  }

  /// Master orchestrator for dynamic FFmpeg execution.
  static Future<String?> exportStoryVideo({
    required VideoTemplate? template,
    required Map<String, String> filledSlots,
    String? customAudioPath,
    required Size uiCanvasSize,
  }) async {
    try {
      if (template == null) throw Exception('Export requires an active template sequence.');

      final dir = await getApplicationDocumentsDirectory();
      final outputPath = '${dir.path}/rendered_story_${DateTime.now().millisecondsSinceEpoch}.mp4';
      if (File(outputPath).existsSync()) File(outputPath).deleteSync();

      final fontPath = await _prepareFontFile();

      final List<String> ffmpegArgs = [];
      String filterGraph = '';
      int inputIndex = 0;

      // =========================================================================
      // 1. INPUT STANDARDIZATION & TIMELINE TRIMMING
      // =========================================================================
      for (final slot in template.mediaSlots) {
        final path = filledSlots[slot.slotId];
        if (path == null) throw Exception('Cannot export. Slot ${slot.slotId} is empty.');
        
        final durationSec = (slot.endTime - slot.startTime).inMilliseconds / 1000.0;
        final isImage = path.toLowerCase().endsWith('.jpg') || path.toLowerCase().endsWith('.png') || path.toLowerCase().endsWith('.jpeg');
        
        if (isImage) {
          // Force image to act like a video loop exactly matching the slot duration
          ffmpegArgs.addAll(['-loop', '1', '-t', '$durationSec', '-i', path]);
        } else {
          // Trim video precisely to the required slot length
          ffmpegArgs.addAll(['-t', '$durationSec', '-i', path]);
        }
        
        // CRUCIAL STABILITY FILTERS: Force all disparate resolutions and framerates into uniform 1080x1920 30FPS pipelines.
        // Scale handles downsampling, pad adds black bars to keep aspect ratio, fps and setsar ensure concat compatibility.
        filterGraph += '[$inputIndex:v]scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2,fps=30,setsar=1[v$inputIndex];';
        inputIndex++;
      }

      // =========================================================================
      // 2. TIMELINE CONCATENATION
      // =========================================================================
      String concatInputs = '';
      for (int i = 0; i < template.mediaSlots.length; i++) {
        concatInputs += '[v$i]';
      }
      filterGraph += '${concatInputs}concat=n=${template.mediaSlots.length}:v=1:a=0[baseVideo];';
      String currentVideoLayer = 'baseVideo';

      // =========================================================================
      // 3. RESOLUTION & COORDINATE TRANSLATION MATH
      // =========================================================================
      // Calculates precise ratios mapping the dynamic Flutter UI to 1080x1920 video limits.
      final double scaleX = 1080 / uiCanvasSize.width;

      // =========================================================================
      // 4. TEMPLATE TEXT OVERLAYS
      // =========================================================================
      int textIndex = 0;
      for (final textItem in template.textOverlays) {
        int x = (textItem.xPercentage * 1080).round();
        int y = (textItem.yPercentage * 1920).round();
        double start = textItem.appearanceStartTime.inMilliseconds / 1000.0;
        double end = textItem.appearanceEndTime.inMilliseconds / 1000.0;
        
        int scaledFontSize = (textItem.fontSize * scaleX).round();
        
        // Remove # and use standard ffmpeg hex color format
        String color = textItem.colorHex.replaceFirst('#', '');
        if (color.length == 6) {
           color = '0x$color';
        } else if (color.length == 8) {
           // AARRGGBB to 0xRRGGBBAA? Actually FFmpeg uses 0xRRGGBB or #RRGGBB
           color = '#${color.substring(2)}'; 
        }
        
        String nextLayer = 'ttxt$textIndex';
        String safeText = textItem.value.replaceAll(":", "\\:").replaceAll("'", "\u2019"); 
        
        filterGraph += '[$currentVideoLayer]drawtext=fontfile=\'$fontPath\':text=\'$safeText\':x=$x:y=$y:fontsize=$scaledFontSize:fontcolor=$color:enable=\'between(t,$start,$end)\'[$nextLayer];';
        currentVideoLayer = nextLayer;
        textIndex++;
      }


      // Clean up final semicolon
      if (filterGraph.endsWith(';')) filterGraph = filterGraph.substring(0, filterGraph.length - 1);

      // =========================================================================
      // 6. AUDIO MIXING
      // =========================================================================
      int audioInputIndex = -1;
      if (customAudioPath != null && customAudioPath.isNotEmpty) {
        ffmpegArgs.addAll(['-i', customAudioPath]);
        audioInputIndex = inputIndex;
      } else if (template.audioUrl.isNotEmpty) {
        final audioPath = await _prepareAudioFile(template.audioUrl);
        if (audioPath != null) {
          ffmpegArgs.addAll(['-i', audioPath]);
          audioInputIndex = inputIndex;
        }
      }

      // =========================================================================
      // 7. BUILD ARGUMENTS & EXECUTE
      // =========================================================================
      ffmpegArgs.addAll(['-filter_complex', filterGraph]);
      ffmpegArgs.addAll(['-map', '[$currentVideoLayer]']);
      
      if (audioInputIndex != -1) {
        ffmpegArgs.addAll(['-map', '$audioInputIndex:a']);
        ffmpegArgs.addAll(['-shortest']); // Clamps audio strictly to video duration
      }
      
      ffmpegArgs.addAll([
        '-c:v', 'libx264',
        '-preset', 'ultrafast',
        '-crf', '28',
        '-c:a', 'aac',
        '-b:a', '128k',
        '-y',
        outputPath
      ]);

      debugPrint('Executing FFmpeg: ffmpeg ${ffmpegArgs.join(' ')}');

      final FFmpegSession session = await FFmpegKit.executeWithArguments(ffmpegArgs);
      final ReturnCode? returnCode = await session.getReturnCode();
      
      if (ReturnCode.isSuccess(returnCode)) {
        debugPrint('Export success! Video saved to: $outputPath');
        return outputPath;
      } else {
        final logs = await session.getLogsAsString();
        debugPrint('FFmpeg Export Failed. Logs:\n$logs');
        throw Exception('FFmpeg failed with code ${returnCode?.getValue()}');
      }
    } catch (e) {
      debugPrint('Export Service Exception: $e');
      rethrow;
    }
  }
}
