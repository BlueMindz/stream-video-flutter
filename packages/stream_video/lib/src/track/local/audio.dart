import 'dart:async';

import 'package:stream_video/protobuf/video/sfu/models/models.pbserver.dart'
    as sfu;
import 'package:stream_video/src/track/local/local.dart';
import 'package:stream_video/src/track/options.dart';
import 'package:stream_video/src/track/track.dart';

class LocalAudioTrack extends LocalTrack with AudioTrack {
  LocalAudioTrack({
    required super.type,
    required super.mediaStream,
    required super.mediaStreamTrack,
    required this.currentOptions,
  });

  @override
  covariant AudioCaptureOptions currentOptions;

  /// Creates a new audio track from the default audio input device.
  static Future<LocalAudioTrack> create([
    AudioCaptureOptions? options,
  ]) async {
    options ??= const AudioCaptureOptions();
    final stream = await LocalTrack.createStream(options);

    return LocalAudioTrack(
      type: sfu.TrackType.TRACK_TYPE_AUDIO,
      mediaStream: stream,
      mediaStreamTrack: stream.getAudioTracks().first,
      currentOptions: options,
    );
  }
}