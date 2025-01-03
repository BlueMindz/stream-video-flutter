import 'package:equatable/equatable.dart';
import 'sfu_codec.dart';

import 'sfu_video_layer_setting.dart';

class SfuVideoSender with EquatableMixin {
  SfuVideoSender({
    required this.codec,
    required this.layers,
  });

  final SfuCodec codec;
  final List<SfuVideoLayerSetting> layers;

  @override
  bool? get stringify => true;

  @override
  List<Object?> get props => [codec, layers];
}
