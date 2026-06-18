import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';
import 'screen_capture_service.dart';
import 'ocr_service.dart';
import 'api_service.dart';

class PipelineCoordinator {
  final ScreenCaptureService captureService;
  final IOcrService ocrService;
  final IApiService apiService;

  StreamSubscription<Uint8List>? _frameSubscription;
  Rect? roi;

  final Set<String> sentLines = {};
  final List<String> offlineQueue = [];
  bool isOnline = true;

  bool isSuspended = false;
  String? serializedQueueState;

  final List<String> eventLogs = [];
  final List<String> apiUploads = [];
  int framesProcessed = 0;
  bool _isProcessingFrame = false;

  PipelineCoordinator({
    required this.captureService,
    required this.ocrService,
    required this.apiService,
  });

  void start() {
    _frameSubscription?.cancel();
    _frameSubscription = captureService.frameStream.listen(
      (Uint8List frame) async {
        if (_isProcessingFrame) {
          eventLogs.add("Frame dropped due to concurrent processing");
          return;
        }
        _isProcessingFrame = true;
        try {
          if (isSuspended) return;
          framesProcessed++;
          try {
            final String recognizedText = await ocrService.recognizeText(frame, roi: roi);
            
            final lines = recognizedText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);
            final newLines = <String>[];
            for (final line in lines) {
              if (!sentLines.contains(line)) {
                newLines.add(line);
                sentLines.add(line);
              }
            }

            if (newLines.isEmpty) {
              eventLogs.add("No new lines; duplicate filtered.");
              return;
            }

            final textToSend = newLines.join('\n');
            
            if (!isOnline) {
              offlineQueue.add(textToSend);
              eventLogs.add("Offline; queued text: $textToSend");
              return;
            }

            try {
              await apiService.extractQuestions(textToSend);
              apiUploads.add(textToSend);
              eventLogs.add("Successfully uploaded: $textToSend");
            } catch (e) {
              offlineQueue.add(textToSend);
              eventLogs.add("Upload failed ($e); queued text: $textToSend");
            }
          } catch (ocrError) {
            eventLogs.add("OCR Failure: $ocrError; API skipped.");
          }
        } finally {
          _isProcessingFrame = false;
        }
      },
      onError: (err) {
        eventLogs.add("Frame stream error: $err");
      }
    );
  }

  Future<void> setOnline(bool online) async {
    isOnline = online;
    if (isOnline) {
      await flushOfflineQueue();
    }
  }

  Future<void> flushOfflineQueue() async {
    final toProcess = List<String>.from(offlineQueue);
    offlineQueue.clear();
    for (final text in toProcess) {
      if (!isOnline) {
        offlineQueue.add(text);
        continue;
      }
      try {
        await apiService.extractQuestions(text);
        apiUploads.add(text);
        eventLogs.add("Flushed from queue: $text");
      } catch (e) {
        offlineQueue.add(text);
        eventLogs.add("Flush failed ($e) for text: $text");
      }
    }
  }

  Future<void> stop() async {
    await captureService.stopCapture();
    await _frameSubscription?.cancel();
    _frameSubscription = null;
    offlineQueue.clear();
    eventLogs.add("Pipeline stopped; queue cleared.");
  }

  void suspend() {
    isSuspended = true;
    _frameSubscription?.pause();
    serializedQueueState = offlineQueue.join('|||');
    eventLogs.add("Pipeline suspended; state serialized.");
  }

  void resume() {
    isSuspended = false;
    _frameSubscription?.resume();
    if (serializedQueueState != null && serializedQueueState!.isNotEmpty) {
      offlineQueue.clear();
      offlineQueue.addAll(serializedQueueState!.split('|||'));
    }
    serializedQueueState = null;
    eventLogs.add("Pipeline resumed.");
  }

  void dispose() {
    stop();
    sentLines.clear();
    offlineQueue.clear();
  }
}
