import '../action/participant_action.dart';
import '../call_state.dart';
import '../logger/impl/tagged_logger.dart';
import '../models/call_track_state.dart';
import '../store/store.dart';
import '../sfu/data/models/sfu_track_type.dart';
import '../webrtc/media/constraints/camera_position.dart';

final _logger = taggedLogger(tag: 'SV:Reducer-Participant');

class ParticipantReducer extends Reducer<CallState, ParticipantAction> {
  const ParticipantReducer();

  @override
  CallState reduce(
    CallState state,
    ParticipantAction action,
  ) {
    if (action is SetCameraEnabled) {
      return _reduceCameraEnabled(state, action);
    } else if (action is SetMicrophoneEnabled) {
      return _reduceMicrophoneEnabled(state, action);
    } else if (action is SetAudioInputDevice) {
      return _reduceSetAudioInputDevice(state, action);
    } else if (action is SetScreenShareEnabled) {
      return _reduceScreenShareEnabled(state, action);
    } else if (action is FlipCamera) {
      return _reduceFlipCamera(state, action);
    } else if (action is SetVideoInputDevice) {
      return _reduceSetVideoInputDevice(state, action);
    } else if (action is SetCameraPosition) {
      return _reduceCameraPosition(state, action);
    } else if (action is UpdateSubscriptions) {
      return _reduceUpdateSubscriptions(state, action);
    } else if (action is UpdateSubscription) {
      return _reduceUpdateSubscription(state, action);
    } else if (action is RemoveSubscription) {
      return _reduceRemoveSubscription(state, action);
    } else if (action is SetAudioOutputDevice) {
      return _reduceSetAudioOutputDevice(state, action);
    }
    return state;
  }

  CallState _reduceUpdateSubscriptions(
    CallState state,
    UpdateSubscriptions action,
  ) {
    final sessionId = state.sessionId;
    _logger.d(() => '[reduceSubscriptions] #$sessionId; action: $action');
    var newState = state;
    for (final child in action.actions) {
      if (child is UpdateSubscription) {
        newState = _reduceUpdateSubscription(newState, child);
      } else if (child is RemoveSubscription) {
        newState = _reduceRemoveSubscription(newState, child);
      }
    }
    return newState;
  }

  CallState _reduceUpdateSubscription(
    CallState state,
    UpdateSubscription action,
  ) {
    _logger.d(() => '[updateSub] #${state.sessionId}; action: $action');
    return state.copyWith(
      callParticipants: state.callParticipants.map((participant) {
        final trackState = participant.publishedTracks[action.trackType];
        if (participant.userId == action.userId &&
            participant.sessionId == action.sessionId &&
            trackState is RemoteTrackState) {
          _logger.v(() => '[updateSub] pFound: $participant');
          return participant.copyWith(
            publishedTracks: {
              ...participant.publishedTracks,
              action.trackType: trackState.copyWith(
                subscribed: true,
                videoDimension: action.videoDimension,
              ),
            },
          );
        }
        _logger.v(() => '[updateSub] pSame: $participant');
        return participant;
      }).toList(),
    );
  }

  CallState _reduceRemoveSubscription(
    CallState state,
    RemoveSubscription action,
  ) {
    return state.copyWith(
      callParticipants: state.callParticipants.map((participant) {
        if (participant.userId == action.userId &&
            participant.sessionId == action.sessionId) {
          final trackState = participant.publishedTracks[action.trackType];
          if (trackState is RemoteTrackState) {
            return participant.copyWith(
              publishedTracks: {
                ...participant.publishedTracks,
                action.trackType: trackState.copyWith(
                  subscribed: false,
                ),
              },
            );
          }
        }
        return participant;
      }).toList(),
    );
  }

  CallState _reduceSetAudioOutputDevice(
    CallState state,
    SetAudioOutputDevice action,
  ) {
    return state.copyWith(
      audioOutputDevice: action.device,
      callParticipants: state.callParticipants.map((participant) {
        if (participant.isLocal) return participant;

        final trackState = participant.publishedTracks[SfuTrackType.audio];
        if (trackState is! RemoteTrackState) return participant;

        return participant.copyWith(
          publishedTracks: {
            ...participant.publishedTracks,
            SfuTrackType.audio: trackState.copyWith(
              audioSinkDevice: action.device,
            ),
          },
        );
      }).toList(),
    );
  }

  CallState _reduceCameraPosition(
    CallState state,
    SetCameraPosition action,
  ) {
    return state.copyWith(
      callParticipants: state.callParticipants.map((participant) {
        if (participant.isLocal) {
          final trackState = participant.publishedTracks[SfuTrackType.video];
          if (trackState is LocalTrackState) {
            // Creating a new track state to reset the source device.
            // CopyWith doesn't support null values.
            final newTrackState = TrackState.local(
              muted: trackState.muted,
              cameraPosition: action.cameraPosition,
            );

            return participant.copyWith(
              publishedTracks: {
                ...participant.publishedTracks,
                SfuTrackType.video: newTrackState,
              },
            );
          }
        }
        return participant;
      }).toList(),
    );
  }

  CallState _reduceFlipCamera(
    CallState state,
    FlipCamera action,
  ) {
    return state.copyWith(
      callParticipants: state.callParticipants.map((participant) {
        if (participant.isLocal) {
          final trackState = participant.publishedTracks[SfuTrackType.video];
          if (trackState is LocalTrackState) {
            // Creating a new track state to reset the source device.
            // CopyWith doesn't support null values.
            final newTrackState = TrackState.local(
              muted: trackState.muted,
              cameraPosition: trackState.cameraPosition?.flip(),
            );

            return participant.copyWith(
              publishedTracks: {
                ...participant.publishedTracks,
                SfuTrackType.video: newTrackState,
              },
            );
          }
        }
        return participant;
      }).toList(),
    );
  }

  CallState _reduceSetVideoInputDevice(
    CallState state,
    SetVideoInputDevice action,
  ) {
    return state.copyWith(
      videoInputDevice: action.device,
      callParticipants: state.callParticipants.map((participant) {
        if (participant.isLocal) {
          final trackState = participant.publishedTracks[SfuTrackType.video];
          if (trackState is LocalTrackState) {
            return participant.copyWith(
              publishedTracks: {
                ...participant.publishedTracks,
                SfuTrackType.video: trackState.copyWith(
                  sourceDevice: action.device,
                  // reset camera position to default
                  cameraPosition: CameraPosition.front,
                ),
              },
            );
          }
        }
        return participant;
      }).toList(),
    );
  }

  CallState _reduceSetAudioInputDevice(
    CallState state,
    SetAudioInputDevice action,
  ) {
    return state.copyWith(
      audioInputDevice: action.device,
      callParticipants: state.callParticipants.map((participant) {
        if (participant.isLocal) {
          final trackState = participant.publishedTracks[SfuTrackType.audio];
          if (trackState is LocalTrackState) {
            return participant.copyWith(
              publishedTracks: {
                ...participant.publishedTracks,
                SfuTrackType.audio: trackState.copyWith(
                  sourceDevice: action.device,
                ),
              },
            );
          }
        }
        return participant;
      }).toList(),
    );
  }

  CallState _reduceCameraEnabled(
    CallState state,
    SetCameraEnabled action,
  ) {
    return _toggleTrackType(state, SfuTrackType.video, action.enabled);
  }

  CallState _reduceMicrophoneEnabled(
    CallState state,
    SetMicrophoneEnabled action,
  ) {
    return _toggleTrackType(state, SfuTrackType.audio, action.enabled);
  }

  CallState _reduceScreenShareEnabled(
    CallState state,
    SetScreenShareEnabled action,
  ) {
    return _toggleTrackType(state, SfuTrackType.screenShare, action.enabled);
  }

  CallState _toggleTrackType(
    CallState state,
    SfuTrackType trackType,
    bool enabled,
  ) {
    return state.copyWith(
      callParticipants: state.callParticipants.map((participant) {
        if (participant.isLocal) {
          final publishedTracks = participant.publishedTracks;
          final trackState = publishedTracks[trackType] ?? TrackState.local();
          if (trackState is LocalTrackState) {
            var cameraPosition = trackState.cameraPosition;
            if (trackType == SfuTrackType.video && cameraPosition == null) {
              cameraPosition = CameraPosition.front;
            }
            return participant.copyWith(
              publishedTracks: {
                ...publishedTracks,
                trackType: trackState.copyWith(
                  muted: !enabled,
                  cameraPosition: cameraPosition,
                ),
              },
            );
          }
        }
        return participant;
      }).toList(),
    );
  }
}