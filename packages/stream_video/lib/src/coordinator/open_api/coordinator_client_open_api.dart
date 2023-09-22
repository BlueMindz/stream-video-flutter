import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../../../open_api/video/coordinator/api.dart' as open;
import '../../../composed_version.dart';
import '../../errors/video_error.dart';
import '../../errors/video_error_composer.dart';
import '../../latency/latency_service.dart';
import '../../location/location_service.dart';
import '../../logger/impl/tagged_logger.dart';
import '../../models/call_cid.dart';
import '../../models/call_created_data.dart';
import '../../models/call_metadata.dart';
import '../../models/call_permission.dart';
import '../../models/call_reaction.dart';
import '../../models/call_received_created_data.dart';
import '../../models/call_received_data.dart';
import '../../models/call_settings.dart';
import '../../models/guest_created_data.dart';
import '../../models/queried_calls.dart';
import '../../models/queried_members.dart';
import '../../models/user_info.dart';
import '../../retry/retry_policy.dart';
import '../../shared_emitter.dart';
import '../../token/token.dart';
import '../../token/token_manager.dart';
import '../../utils/none.dart';
import '../../utils/result.dart';
import '../../utils/standard.dart';
import '../coordinator_client.dart';
import '../models/coordinator_events.dart';
import '../models/coordinator_models.dart';
import 'coordinator_ws_open_api.dart';
import 'open_api_extensions.dart';

const _idEvents = 1;

/// An accessor that allows us to communicate with the API around video calls.
class CoordinatorClientOpenApi extends CoordinatorClient {
  CoordinatorClientOpenApi({
    required String rpcUrl,
    required String wsUrl,
    required String apiKey,
    required TokenManager tokenManager,
    required LatencyService latencyService,
    required RetryPolicy retryPolicy,
  })  : _rpcUrl = rpcUrl,
        _wsUrl = wsUrl,
        _apiKey = apiKey,
        _tokenManager = tokenManager,
        _latencyService = latencyService,
        _retryPolicy = retryPolicy;

  final _logger = taggedLogger(tag: 'SV:CoordClient');
  final String _rpcUrl;
  final String _apiKey;
  final String _wsUrl;
  final TokenManager _tokenManager;
  final LatencyService _latencyService;
  final RetryPolicy _retryPolicy;

  late final open.ApiClient _apiClient = open.ApiClient(
    basePath: _rpcUrl,
    authentication: _Authentication(
      apiKey: _apiKey,
      tokenManager: _tokenManager,
      getConnectionId: () => _ws?.connectionId,
    ),
  );
  late final _defaultApi = open.DefaultApi(_apiClient);
  late final _serverSideApi = open.ServerSideApi(_apiClient);
  late final _locationService = LocationService();

  @override
  SharedEmitter<CoordinatorEvent> get events => _events;
  final _events = MutableSharedEmitterImpl<CoordinatorEvent>();

  UserInfo? _user;
  CoordinatorWebSocketOpenApi? _ws;
  StreamSubscription<CoordinatorEvent>? _wsSubscription;

  @override
  Future<Result<None>> connectUser(UserInfo user) async {
    _logger.d(() => '[connectUser] user: $user');
    if (_user != null) {
      _logger.w(() => '[connectUser] rejected (another user in use): $_user');
      return Result.error(
        'Another user is in use, please call "disconnectUser" first',
      );
    }
    _user = user;
    _ws = _createWebSocket(user).also((ws) {
      _wsSubscription = ws.events.listen(_events.emit);
    });
    return openConnection();
  }

  @override
  Future<Result<None>> openConnection() async {
    try {
      final ws = _ws;
      if (ws == null) {
        _logger.w(() => '[openConnection] rejected (no WS)');
        return Result.error('WS is not initialized, call "connectUser" first');
      }
      if (!ws.isDisconnected) {
        _logger.w(() => '[openConnection] rejected (not closed)');
        return Result.error('WS is not closed');
      }
      _logger.i(() => '[openConnection] no args');
      await ws.connect();
      return const Result.success(none);
    } catch (e, stk) {
      _logger.e(() => '[openConnection] failed: $e');
      return Result.failure(VideoErrors.compose(e, stk));
    }
  }

  @override
  Future<Result<None>> closeConnection() async {
    try {
      final ws = _ws;
      if (ws == null) {
        _logger.w(() => '[closeConnection] rejected (no WS)');
        return Result.error('WS is not initialized');
      }
      if (ws.isDisconnected) {
        _logger.w(() => '[closeConnection] rejected (already closed)');
        return Result.error('WS is already closed');
      }
      _logger.i(() => '[closeConnection] no args');
      await ws.disconnect();
      return const Result.success(none);
    } catch (e, stk) {
      _logger.e(() => '[closeConnection] failed: $e');
      return Result.failure(VideoErrors.compose(e, stk));
    }
  }

  @override
  Future<Result<None>> disconnectUser() async {
    _logger.d(() => '[disconnectUser] userId: ${_user?.id}');
    if (_user == null) {
      _logger.w(() => '[disconnectUser] rejected (user is null)');
      return const Result.success(none);
    }
    _user = null;

    final closedResult = await closeConnection();
    return closedResult.when(
      success: (_) async {
        _ws = null;
        await _wsSubscription?.cancel();
        _wsSubscription = null;
        return const Result.success(none);
      },
      failure: Result.failure,
    );
  }

  CoordinatorWebSocketOpenApi _createWebSocket(UserInfo user) {
    return CoordinatorWebSocketOpenApi(
      _wsUrl,
      apiKey: _apiKey,
      userInfo: user,
      tokenManager: _tokenManager,
      retryPolicy: _retryPolicy,
    );
  }

  /// Create a new Device used to receive Push Notifications.
  @override
  Future<Result<None>> createDevice({
    required String id,
    required open.CreateDeviceRequestPushProviderEnum pushProvider,
    String? pushProviderName,
    String? userId,
    bool? voipToken,
  }) async {
    try {
      final input = open.CreateDeviceRequest(
        id: id,
        pushProvider: pushProvider,
        pushProviderName: pushProviderName,
        userId: userId,
        voipToken: voipToken,
      );
      _logger.d(() => '[createDevice] input: $input');
      final result = await _defaultApi.createDevice(
        input,
      );
      _logger.v(() => '[createDevice] completed: $result');
      if (result == null) {
        return Result.error('createDevice result is null');
      }
      return const Result.success(none);
    } catch (e, stk) {
      _logger.e(() => '[createDevice] failed: $e; $stk');
      return Result.failure(VideoErrors.compose(e, stk));
    }
  }

  /// List devices used to receive Push Notifications.
  @override
  Future<Result<List<open.Device>>> listDevices({
    required String userId,
  }) async {
    try {
      _logger.d(() => '[listDevices] userId: $userId');
      final result = await _defaultApi.listDevices(
        userId: userId,
      );
      _logger.v(() => '[listDevices] completed: $result');
      if (result == null) {
        return Result.error('listDevices result is null');
      }
      return Result.success(result.devices);
    } catch (e, stk) {
      _logger.e(() => '[listDevices] failed: $e; $stk');
      return Result.failure(VideoErrors.compose(e, stk));
    }
  }

  /// Deletes a Device used to receive Push Notifications.
  @override
  Future<Result<None>> deleteDevice({
    required String id,
    String? userId,
  }) async {
    try {
      _logger.d(() => '[deleteDevice] id: $id, userId: $userId');
      final result = await _defaultApi.deleteDevice(
        id: id,
        userId: userId,
      );
      _logger.v(() => '[deleteDevice] completed: $result');
      if (result == null) {
        return Result.error('deleteDevice result is null');
      }
      return const Result.success(none);
    } catch (e, stk) {
      _logger.e(() => '[deleteDevice] failed: $e; $stk');
      return Result.failure(VideoErrors.compose(e, stk));
    }
  }

  /// Gets the call if already exists.
  @override
  Future<Result<CallReceivedData>> getCall({
    required StreamCallCid callCid,
    int? membersLimit,
    bool? ringing,
    bool? notify,
  }) async {
    try {
      _logger.d(
        () => '[getCall] cid: $callCid, ringing: $ringing'
            ', membersLimit: $membersLimit, ringing: $ringing, notify: $notify',
      );
      final result = await _defaultApi.getCall(
        callCid.type,
        callCid.id,
        membersLimit: membersLimit,
        ring: ringing,
        notify: notify,
      );
      _logger.v(() => '[getCall] completed: $result');
      if (result == null) {
        return Result.error('getCall result is null');
      }

      return Result.success(
        CallReceivedData(
          callCid: callCid,
          metadata: result.call.toCallMetadata(
            membership: result.membership,
            members: result.members,
            ownCapabilities: result.ownCapabilities,
          ),
        ),
      );
    } catch (e, stk) {
      _logger.e(() => '[getCall] failed: $e; $stk');
      return Result.failure(VideoErrors.compose(e, stk));
    }
  }

  /// Gets the call if already exists or attempts to create a new call.
  @override
  Future<Result<CallReceivedOrCreatedData>> getOrCreateCall({
    required StreamCallCid callCid,
    bool? ringing,
    List<open.MemberRequest>? members,
  }) async {
    try {
      _logger.d(
        () => '[getOrCreateCall] cid: $callCid'
            ', ringing: $ringing, members: $members',
      );
      final result = await _defaultApi.getOrCreateCall(
        callCid.type,
        callCid.id,
        open.GetOrCreateCallRequest(
          data: open.CallRequest(
            members: members ?? [],
          ),
          ring: ringing,
        ),
      );
      _logger.v(() => '[getOrCreateCall] completed: $result');
      if (result == null) {
        return Result.error('getOrCreateCall result is null');
      }

      return Result.success(
        CallReceivedOrCreatedData(
          wasCreated: result.created,
          data: CallCreatedData(
            callCid: callCid,
            metadata: result.call.toCallMetadata(
              membership: result.membership,
              members: result.members,
              ownCapabilities: result.ownCapabilities,
            ),
          ),
        ),
      );
    } catch (e, stk) {
      _logger.e(() => '[getOrCreateCall] failed: $e; $stk');
      return Result.failure(VideoErrors.compose(e, stk));
    }
  }

  /// Attempts to join a Call. If successful, gives us more information
  /// about the user and the call itself.
  @override
  Future<Result<CoordinatorJoined>> joinCall({
    required StreamCallCid callCid,
    String? datacenterId,
    bool? ringing,
    bool? create,
  }) async {
    try {
      _logger.d(
        () => '[joinCall] cid: $callCid, dataCenterId: $datacenterId'
            ', ringing: $ringing, create: $create',
      );
      final location = await _locationService.getLocation();
      _logger.v(() => '[joinCall] location: $location');
      final result = await _defaultApi.joinCall(
        callCid.type,
        callCid.id,
        open.JoinCallRequest(
          create: create,
          ring: ringing,
          location: location,
        ),
      );
      _logger.v(() => '[joinCall] completed: $result');
      if (result == null) {
        return Result.error('joinCall result is null');
      }

      return Result.success(
        CoordinatorJoined(
          wasCreated: result.created,
          metadata: result.call.toCallMetadata(
            membership: result.membership,
            members: result.members,
            ownCapabilities: result.ownCapabilities,
          ),
          credentials: result.credentials.toCallCredentials(),
          members: result.members.toCallMembers(),
          users: result.members.toCallUsers(),
          duration: result.duration,
        ),
      );
    } catch (e, stk) {
      _logger.e(() => '[joinCall] failed: $e; $stk');
      return Result.failure(VideoErrors.compose(e, stk));
    }
  }

  /// Sends a custom event with encoded JSON data.
  @override
  Future<Result<None>> sendCustomEvent({
    required StreamCallCid callCid,
    required String eventType,
    Map<String, Object> custom = const {},
  }) async {
    try {
      _logger.d(
        () => '[sendCustomEvent] cid: $callCid'
            ', eventType: $eventType, custom: $custom',
      );
      final result = await _defaultApi.sendEvent(
        callCid.type,
        callCid.id,
        open.SendEventRequest(
          custom: custom,
        ),
      );
      _logger.v(() => '[sendCustomEvent] completed: $result');
      if (result == null) {
        return Result.error('sendCustomEvent result is null');
      }
      return const Result.success(none);
    } catch (e, stk) {
      _logger.e(() => '[sendCustomEvent] failed: $e; $stk');
      return Result.failure(VideoErrors.compose(e, stk));
    }
  }

  /// Sends invite to people for an existing call.
  @override
  Future<Result<None>> inviteUsers({
    required StreamCallCid callCid,
    required Iterable<open.MemberRequest> members,
    bool? ringing,
  }) async {
    try {
      _logger.d(
        () =>
            '[inviteUsers] cid: $callCid, members: $members, ringing: $ringing',
      );
      final result = await _defaultApi.updateCallMembers(
        callCid.type,
        callCid.id,
        open.UpdateCallMembersRequest(
          updateMembers: members.toList(),
        ),
      );
      _logger.v(() => '[inviteUsers] completed: $result');
      if (result == null) {
        return Result.error('inviteUsers result is null');
      }
      return const Result.success(none);
    } catch (e, stk) {
      return Result.failure(VideoErrors.compose(e, stk));
    }
  }

  @override
  Future<Result<None>> requestPermissions({
    required StreamCallCid callCid,
    required List<CallPermission> permissions,
  }) async {
    try {
      final result = await _defaultApi.requestPermission(
        callCid.type,
        callCid.id,
        open.RequestPermissionRequest(
          permissions: [...permissions.map((e) => e.alias)],
        ),
      );
      if (result == null) {
        return Result.error('requestPermissions result is null');
      }
      return const Result.success(none);
    } catch (e, stk) {
      return Result.failure(VideoErrors.compose(e, stk));
    }
  }

  @override
  Future<Result<None>> updateUserPermissions({
    required StreamCallCid callCid,
    required String userId,
    required List<CallPermission> grantPermissions,
    required List<CallPermission> revokePermissions,
  }) async {
    try {
      final result = await _defaultApi.updateUserPermissions(
        callCid.type,
        callCid.id,
        open.UpdateUserPermissionsRequest(
          userId: userId,
          grantPermissions: [...grantPermissions.map((e) => e.alias)],
          revokePermissions: [...revokePermissions.map((e) => e.alias)],
        ),
      );
      if (result == null) {
        return Result.error('updateUserPermissions result is null');
      }
      return const Result.success(none);
    } catch (e, stk) {
      return Result.failure(VideoErrors.compose(e, stk));
    }
  }

  @override
  Future<Result<None>> startRecording(StreamCallCid callCid) async {
    try {
      await _defaultApi.startRecording(callCid.type, callCid.id);
      return const Result.success(none);
    } catch (e, stk) {
      return Result.failure(VideoErrors.compose(e, stk));
    }
  }

  @override
  Future<Result<List<open.CallRecording>>> listRecordings(
    StreamCallCid callCid,
    String sessionId,
  ) async {
    try {
      final result = await _defaultApi.listRecordingsTypeIdSession1(
        callCid.type,
        callCid.id,
        sessionId,
      );
      return Result.success(result?.recordings ?? []);
    } catch (e, stk) {
      return Result.failure(VideoErrors.compose(e, stk));
    }
  }

  @override
  Future<Result<None>> stopRecording(StreamCallCid callCid) async {
    try {
      await _defaultApi.stopRecording(callCid.type, callCid.id);
      return const Result.success(none);
    } catch (e, stk) {
      return Result.failure(VideoErrors.compose(e, stk));
    }
  }

  @override
  Future<Result<String?>> startBroadcasting(StreamCallCid callCid) async {
    try {
      final result = await _defaultApi
          .startBroadcasting(callCid.type, callCid.id)
          .then((it) => it?.playlistUrl);
      return Result.success(result);
    } catch (e, stk) {
      return Result.failure(VideoErrors.compose(e, stk));
    }
  }

  @override
  Future<Result<None>> stopBroadcasting(StreamCallCid callCid) async {
    try {
      await _defaultApi.stopBroadcasting(callCid.type, callCid.id);
      return const Result.success(none);
    } catch (e, stk) {
      return Result.failure(VideoErrors.compose(e, stk));
    }
  }

  @override
  Future<Result<CallReaction>> sendReaction({
    required StreamCallCid callCid,
    required String reactionType,
    String? emojiCode,
    Map<String, Object> custom = const {},
  }) async {
    try {
      final result = await _defaultApi.sendVideoReaction(
        callCid.type,
        callCid.id,
        open.SendReactionRequest(
          type: reactionType,
          emojiCode: emojiCode,
          custom: custom,
        ),
      );
      if (result == null) {
        return Result.error('sendReaction result is null');
      }
      return Result.success(result.reaction.toCallReaction());
    } catch (e, stk) {
      return Result.failure(VideoErrors.compose(e, stk));
    }
  }

  /// Queries users based on the given input.
  @override
  Future<Result<QueriedMembers>> queryMembers({
    required StreamCallCid callCid,
    required Map<String, Object> filterConditions,
    String? next,
    String? prev,
    List<open.SortParamRequest> sorts = const [],
    int? limit,
  }) async {
    try {
      final result = await _defaultApi.queryMembers(
        open.QueryMembersRequest(
          type: callCid.type,
          id: callCid.id,
          filterConditions: filterConditions,
          next: next,
          prev: prev,
          sort: sorts,
          limit: limit,
        ),
      );
      if (result == null) {
        return Result.error('queryMembers result is null');
      }
      return Result.success(result.toQueriedMembers(callCid));
    } catch (e, stk) {
      return Result.failure(VideoErrors.compose(e, stk));
    }
  }

  /// Queries calls based on the given input.
  @override
  Future<Result<QueriedCalls>> queryCalls({
    required Map<String, Object> filterConditions,
    String? next,
    String? prev,
    List<open.SortParamRequest> sorts = const [],
    int? limit,
  }) async {
    try {
      final result = await _defaultApi.queryCalls(
        open.QueryCallsRequest(
          filterConditions: filterConditions,
          next: next,
          prev: prev,
          sort: sorts,
          limit: limit,
        ),
      );
      if (result == null) {
        return Result.error('queryCalls result is null');
      }
      return Result.success(result.toQueriedCalls());
    } catch (e, stk) {
      return Result.failure(VideoErrors.compose(e, stk));
    }
  }

  @override
  Future<Result<None>> blockUser({
    required StreamCallCid callCid,
    required String userId,
  }) async {
    try {
      final result = await _defaultApi.blockUser(
        callCid.type,
        callCid.id,
        open.BlockUserRequest(userId: userId),
      );
      if (result == null) {
        return Result.error('blockUser result is null');
      }
      return const Result.success(none);
    } catch (e, stk) {
      return Result.failure(VideoErrors.compose(e, stk));
    }
  }

  @override
  Future<Result<None>> unblockUser({
    required StreamCallCid callCid,
    required String userId,
  }) async {
    try {
      final result = await _defaultApi.unblockUser(
        callCid.type,
        callCid.id,
        open.UnblockUserRequest(userId: userId),
      );
      if (result == null) {
        return Result.error('unblockUser result is null');
      }
      return const Result.success(none);
    } catch (e, stk) {
      return Result.failure(VideoErrors.compose(e, stk));
    }
  }

  @override
  Future<Result<None>> endCall(StreamCallCid callCid) async {
    try {
      final result = await _defaultApi.endCall(callCid.type, callCid.id);
      if (result == null) {
        return Result.error('endCall result is null');
      }
      return const Result.success(none);
    } catch (e, stk) {
      return Result.failure(VideoErrors.compose(e, stk));
    }
  }

  @override
  Future<Result<CallMetadata>> goLive({
    required StreamCallCid callCid,
    bool? startHls,
    bool? startRecording,
    bool? startTranscription,
  }) async {
    try {
      final result = await _defaultApi.goLive(
        callCid.type,
        callCid.id,
        open.GoLiveRequest(
          startHls: startHls,
          startRecording: startRecording,
          startTranscription: startTranscription,
        ),
      );
      if (result == null) {
        return Result.error('goLive result is null');
      }

      return Result.success(result.call.toCallMetadata());
    } catch (e, stk) {
      return Result.failure(VideoErrors.compose(e, stk));
    }
  }

  @override
  Future<Result<CallMetadata>> stopLive(StreamCallCid callCid) async {
    try {
      final result = await _defaultApi.stopLive(callCid.type, callCid.id);
      if (result == null) {
        return Result.error('stopLive result is null');
      }

      return Result.success(result.call.toCallMetadata());
    } catch (e, stk) {
      return Result.failure(VideoErrors.compose(e, stk));
    }
  }

  @override
  Future<Result<None>> muteUsers({
    required StreamCallCid callCid,
    required List<String> userIds,
    bool? muteAllUsers,
    bool? audio,
    bool? video,
    bool? screenshare,
  }) async {
    try {
      final result = await _defaultApi.muteUsers(
        callCid.type,
        callCid.id,
        open.MuteUsersRequest(
          userIds: userIds,
          muteAllUsers: muteAllUsers,
          audio: audio,
          video: video,
          screenshare: screenshare,
        ),
      );
      if (result == null) {
        return Result.error('stopLive result is null');
      }

      return const Result.success(none);
    } catch (e, stk) {
      return Result.failure(VideoErrors.compose(e, stk));
    }
  }

  @override
  Future<Result<CallMetadata>> updateCall({
    required StreamCallCid callCid,
    Map<String, Object> custom = const {},
    StreamRingSettings? ring,
    StreamAudioSettings? audio,
    StreamVideoSettings? video,
    StreamScreenShareSettings? screenShare,
    StreamRecordingSettings? recording,
    StreamTranscriptionSettings? transcription,
    StreamBackstageSettings? backstage,
    StreamGeofencingSettings? geofencing,
  }) async {
    try {
      final result = await _defaultApi.updateCall(
        callCid.type,
        callCid.id,
        open.UpdateCallRequest(
          settingsOverride: open.CallSettingsRequest(
            ring: ring?.toOpenDto(),
            audio: audio?.toOpenDto(),
            video: video?.toOpenDto(),
            screensharing: screenShare?.toOpenDto(),
            recording: recording?.toOpenDto(),
            transcription: transcription?.toOpenDto(),
            backstage: backstage?.toOpenDto(),
            geofencing: geofencing?.toOpenDto(),
          ),
          custom: custom,
        ),
      );
      if (result == null) {
        return Result.error('updateCall result is null');
      }
      return Result.success(result.call.toCallMetadata());
    } catch (e, stk) {
      return Result.failure(VideoErrors.compose(e, stk));
    }
  }

  /// Signals other users that I have accepted the incoming call.
  /// Causes the [CoordinatorCallAcceptedEvent] event to be emitted
  /// to all the call members.
  @override
  Future<Result<None>> acceptCall({
    required StreamCallCid cid,
  }) async {
    try {
      await _defaultApi.acceptCall(cid.type, cid.id);
      return const Result.success(none);
    } catch (e) {
      return Result.failure(VideoErrors.compose(e));
    }
  }

  /// Signals other users that I have rejected the incoming call.
  /// Causes the [CoordinatorCallRejectedEvent] event to be emitted
  /// to all the call members.
  @override
  Future<Result<None>> rejectCall({
    required StreamCallCid cid,
  }) async {
    try {
      await _defaultApi.rejectCall(cid.type, cid.id);
      return const Result.success(none);
    } catch (e) {
      return Result.failure(VideoErrors.compose(e));
    }
  }

  @override
  Future<Result<GuestCreatedData>> createGuest({
    required String id,
    String? name,
    String? role,
    String? image,
    List<String>? teams,
    Map<String, Object> custom = const {},
  }) async {
    try {
      final res = await _defaultApi.createGuest(
        open.CreateGuestRequest(
          user: open.UserRequest(
            id: id,
            custom: custom,
            image: image,
            name: name,
            role: role,
            teams: teams ?? [],
          ),
        ),
      );

      if (res != null) {
        return Result.success(res.toGuestCreatedData());
      } else {
        return const Result.failure(
          VideoError(message: 'Guest could not be created.'),
        );
      }
    } catch (e) {
      return Result.failure(VideoErrors.compose(e));
    }
  }
}

typedef GetConnectionId = String? Function();

class _Authentication extends open.Authentication {
  _Authentication({
    required this.apiKey,
    required this.tokenManager,
    required this.getConnectionId,
  });

  final String apiKey;
  final TokenManager tokenManager;
  final GetConnectionId getConnectionId;

  @override
  Future<void> applyToParams(
    List<open.QueryParam> queryParams,
    Map<String, String> headerParams,
  ) async {
    final tokenResult = await tokenManager.getToken();
    if (tokenResult is! Success<UserToken>) {
      throw (tokenResult as Failure).error;
    }
    queryParams.add(open.QueryParam('api_key', apiKey));
    final connectionId = getConnectionId();
    if (connectionId != null) {
      queryParams.add(open.QueryParam('connection_id', connectionId));
    }
    headerParams['Authorization'] = tokenResult.getDataOrNull()!.rawValue;
    headerParams['stream-auth-type'] =
        tokenResult.getDataOrNull()!.authType.name;
    headerParams['X-Stream-Client'] = streamClientVersion;
    headerParams['x-client-request-id'] = const Uuid().v4();
  }
}
