import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:clipshare/app/data/enums/forward_msg_type.dart';
import 'package:clipshare/app/data/enums/history_content_type.dart';
import 'package:clipshare/app/data/enums/msg_type.dart';
import 'package:clipshare/app/data/enums/notification_payload_type.dart';
import 'package:clipshare/app/data/enums/syncing_file_state.dart';
import 'package:clipshare/app/data/enums/translation_key.dart';
import 'package:clipshare/app/data/models/dev_info.dart';
import 'package:clipshare/app/data/models/notification_payload.dart';
import 'package:clipshare/app/data/models/pending_file.dart';
import 'package:clipshare/app/data/models/syncing_file.dart';
import 'package:clipshare/app/data/repository/entity/tables/device.dart';
import 'package:clipshare/app/data/repository/entity/tables/history.dart';
import 'package:clipshare/app/handlers/socket/forward_socket_client.dart';
import 'package:clipshare/app/handlers/socket/secure_socket_client.dart';
import 'package:clipshare/app/modules/history_module/history_controller.dart';
import 'package:clipshare/app/services/channels/android_channel.dart';
import 'package:clipshare/app/services/config_service.dart';
import 'package:clipshare/app/services/db_service.dart';
import 'package:clipshare/app/services/transport/socket_service.dart';
import 'package:clipshare/app/services/syncing_file_progress_service.dart';
import 'package:clipshare/app/services/transport/storage_service.dart';
import 'package:clipshare/app/utils/constants.dart';
import 'package:clipshare/app/utils/extensions/device_extension.dart';
import 'package:clipshare/app/utils/extensions/file_extension.dart';
import 'package:clipshare/app/utils/extensions/number_extension.dart';
import 'package:clipshare/app/utils/extensions/time_extension.dart';
import 'package:clipshare/app/utils/file_util.dart';
import 'package:clipshare/app/utils/global.dart';
import 'package:clipshare/app/utils/notify_util.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:uri_file_reader/uri_file_reader.dart';

import '../../utils/log.dart';

class FileSyncHandler {
  static const tag = "FileSyncer";
  static const _receivedFileNotifyKeyPrefix = 'receive-file';
  final appConfig = Get.find<ConfigService>();
  final dbService = Get.find<DbService>();
  final sktService = Get.find<SocketService>();
  final syncingFileService = Get.find<SyncingFileProgressService>();
  ServerSocket? _server;
  Socket? _forwardSkt;
  late final int _fileId;
  bool hasClient = false;
  /// 文件字节流是否真正开始写入 socket（仅"连上了"不代表开始发送）。
  bool _sendStarted = false;
  /// 保证 _onDone 只触发一次：发送队列不能被重复推进，也不能因异常永久卡住。
  bool _doneCalled = false;
  /// 与接收端相连的那个 socket，异常/超时时用于强制断开以通知对端。
  Socket? _client;
  /// content:// 落地用的临时目录，发送结束后清理。
  Directory? _stagingDir;
  File? _file;
  PendingFile pendingFile;
  late final BuildContext context;
  late final void Function() _onDone;
  late final bool isUri;

  FileSyncHandler._private({
    required this.pendingFile,
    required void Function(FileSyncHandler) onReady,
    required void Function() onDone,
    required this.context,
    bool useForward = false,
    String? targetDevId,
  }) {
    _fileId = appConfig.snowflake.nextId();
    _onDone = onDone;
    isUri = pendingFile.isUri;
    if (!isUri) {
      final path = pendingFile.filePath;
      _file = File(path);
      if (!_file!.existsSync()) {
        throw Exception("file not found: $path");
      }
    }
    if (useForward) {
      //检查中转设置
      var host = sktService.forwardServerHost;
      var port = sktService.forwardServerPort;
      var forwardEnabled = appConfig.enableForward;
      if (!forwardEnabled || host == null || port == null) {
        throw Exception("Forwarding service not enabled.");
      }
      //连接中转服务器
      Socket.connect(host, port).then((skt) async {
        final fileName = isUri ? pendingFile.fileName : _file!.fileName;
        final size = isUri ? pendingFile.size : await _file!.length();
        _forwardSkt = skt;
        var baseMsg = ForwardSocketClient.baseMsg;
        //向中转服务器发送基本信息
        final payload = utf8.encode(
          json.encode(
            baseMsg..addAll({
              "fileName": fileName,
              "size": size.toString(),
              "fileId": _fileId.toString(),
              "target": targetDevId!,
              "connType": ForwardConnType.sendFile.name,
              "userId": appConfig.userId.toString(),
            }),
          ),
        );
        final msgSize = payload.length;
        final header = SecureSocketClient.createPacketHeader(
          msgSize,
          msgSize,
          1,
          1,
        );
        // 组合头部和载荷
        Uint8List packet = Uint8List(header.length + payload.length);
        // 写入头部
        packet.setAll(0, header);
        // 写入载荷
        packet.setAll(header.length, payload);
        //写入数据
        skt.add(packet);
      }).catchError((Object err, StackTrace stack) {
        logger.error(tag, "connect forward server failed. $err $stack");
        sktService.removeSendFileRecordByForward(this, _fileId, targetDevId);
        _closeTransferSockets(destroyClient: true);
        _finishOnce();
      });
      //告知 SocketService
      sktService.addSendFileRecordByForward(this, _fileId);
      //延时检测是否有客户端连接，超时取消发送
      _delayedClientCheck(() {
        _finishOnce();
        sktService.removeSendFileRecordByForward(this, _fileId, targetDevId!);
      });
    } else {
      // 绑定/监听失败也要推进队列，否则多文件发送会永久停在第一个文件。
      unawaited(_startDirectServer(onReady));
    }
  }

  /// 启动直连模式的临时文件服务，并把端口通过主连接告知接收端。
  Future<void> _startDirectServer(void Function(FileSyncHandler) onReady) async {
    try {
      final server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      _server = server;
      onReady(this);
      server.listen(
        (client) {
          hasClient = true;
          // 必须接住 sendFile2Socket 的异步异常：Android 侧读取 content://
          // 失败时，未处理的异常会让 socket 永不关闭，接收端 onDone 不触发。
          unawaited(sendFile2Socket(client));
        },
        onError: (Object err, StackTrace stack) {
          logger.error(tag, "file server error. $err $stack");
          _closeTransferSockets(destroyClient: true);
          _finishOnce();
        },
        cancelOnError: false,
      );
      _delayedClientCheck(_finishOnce);
    } catch (err, stack) {
      logger.error(tag, "bind file server failed. $err $stack");
      _closeTransferSockets(destroyClient: true);
      _finishOnce();
    }
  }

  ///当文件接收方连接了中转服务器后由 SocketService 调用该方法通知发送端开始发送
  void onForwardReceiverConnected() {
    sktService.removeSendFileRecordByForward(this, _fileId, null);
    final socket = _forwardSkt;
    if (socket == null) {
      logger.error(tag, "forward socket is null when receiver connected");
      _closeTransferSockets(destroyClient: true);
      _finishOnce();
      return;
    }
    hasClient = true;
    // 与直连模式一致：sendFile2Socket 自行兜底所有异常并推进队列。
    unawaited(sendFile2Socket(socket));
  }

  /// 打开待发送文件的字节流。
  ///
  /// 桌面端直接读本地文件。Android 通过系统分享进来的文件是 content:// URI，
  /// 依赖 uri_file_reader 的 EventChannel 流；当临时 URI 读权限失效、Activity
  /// 已分离或 provider 拒绝时，该流会返回 null 或抛 PlatformException。此时
  /// 退化为「先把 URI 落地成临时本地文件、再按普通文件读」，让 Android→桌面
  /// 与桌面→桌面走同一条已验证过的发送路径，而不是静默失败。
  Future<Stream<List<int>>> _openSendStream() async {
    if (!isUri) {
      return _file!.openRead();
    }
    try {
      final uriStream = await uriFileReader.readFileAsBytesStream(pendingFile.filePath);
      if (uriStream != null) {
        return uriStream.cast<List<int>>();
      }
      logger.warn(tag, "content uri stream is null, fallback to temp file");
    } catch (err, stack) {
      logger.warn(tag, "read content uri failed, fallback to temp file. $err $stack");
    }

    final stagingDir = Directory("${appConfig.cachePath}${Constants.dirSeparate}send_${DateTime.now().microsecondsSinceEpoch}");
    await stagingDir.create(recursive: true);
    _stagingDir = stagingDir;
    final copiedPath = await uriFileReader.copyFileFromUri(pendingFile.filePath, stagingDir.path);
    if (copiedPath == null || !File(copiedPath).existsSync()) {
      throw StateError("unable to read content uri: ${pendingFile.filePath}");
    }
    // 接收端以文件 basename 作为保存名，这里保持分享时的 DISPLAY_NAME。
    final displayName = (pendingFile.fileName ?? "file").replaceAll(RegExp(r'[/\\]'), "_");
    final targetPath = "${stagingDir.path}${Constants.dirSeparate}$displayName";
    var localPath = copiedPath;
    if (displayName.isNotEmpty && targetPath != copiedPath) {
      try {
        File(copiedPath).renameSync(targetPath);
        localPath = targetPath;
      } catch (_) {
        // 重命名失败时仍可用插件返回的路径，内容完整，仅文件名可能不同。
      }
    }
    _file = File(localPath);
    return _file!.openRead();
  }

  ///向 socket 发送文件。
  ///
  /// 任何异常都必须收口在这里：关闭 socket（让接收端 onDone 一定触发）、释放
  /// 临时服务、并且只推进一次发送队列，否则一个文件失败会让后续文件全部卡死。
  Future<void> sendFile2Socket(Socket client) async {
    _client = client;
    final sourcePath = isUri ? pendingFile.filePath : _file!.normalizePath;
    final fileName = isUri ? (pendingFile.fileName ?? "file") : _file!.fileName;
    SyncingFile? syncingFile;
    try {
      final rawStream = await _openSendStream();
      final actualSize = _file != null ? _file!.lengthSync() : (pendingFile.size ?? 0);
      syncingFile = SyncingFile(
        // content provider 声明的 SIZE 可能是 -1（未知），不能拿它做断言。
        totalSize: actualSize < 0 ? 0 : actualSize,
        context: context,
        filePath: sourcePath,
        fromDev: appConfig.device,
        isSender: true,
        startTime: DateTime.now().format(),
        onClose: (done) {
          if (done) return;
          client.destroy();
          syncingFileService.removeSyncingFile(sourcePath);
        },
      );
      syncingFileService.updateSyncingFile(syncingFile);
      final stream = rawStream.transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (data, sink) {
            syncingFile!.addBytes(data);
            sink.add(data);
          },
        ),
      );
      syncingFile.setState(SyncingFileState.syncing);
      // 到这里字节流才真正开始写入；超时兜底必须以它为判据。
      _sendStarted = true;
      await client.addStream(stream);

      var path = sourcePath;
      try {
        path = Uri.decodeComponent(sourcePath);
      } catch (_) {
        // 路径本身不是合法的 percent-encoding 时保留原值。
      }
      final history = History(
        id: _fileId,
        uid: appConfig.userId,
        devId: appConfig.devInfo.guid,
        time: DateTime.now().toString(),
        content: path,
        type: HistoryContentType.file.value,
        size: actualSize < 0 ? 0 : actualSize,
        sync: true,
      );
      await Get.find<HistoryController>().addData(history, null, false);
      syncingFile.setState(SyncingFileState.done);
    } catch (err, stack) {
      logger.error(tag, "send file failed: $sourcePath. $err $stack");
      syncingFile?.setState(SyncingFileState.error);
      Global.showSnackBarWarn(text: TranslationKey.failedToLoad.tr);
      // 强制断开，让接收端立即收到 onDone/onError 并清理残缺文件，
      // 而不是一直停在「接收中」并且留下 0 字节文件。
      client.destroy();
    } finally {
      logger.info(tag, "send file($fileName) completed");
      try {
        // destroy 之后 close 可能失败或迟迟不返回，加超时避免连 finally 都卡住。
        await client.close().timeout(const Duration(seconds: 5));
      } catch (_) {
        // ignored
      }
      _closeTransferSockets();
      _cleanupStaging();
      _finishOnce();
    }
  }

  void _finishOnce() {
    if (_doneCalled) return;
    _doneCalled = true;
    try {
      _onDone();
    } catch (err, stack) {
      logger.error(tag, "onDone callback failed. $err $stack");
    }
  }

  /// 释放临时监听服务。[destroyClient] 仅在异常/超时场景为 true，
  /// 正常发送完成后不能 destroy，否则会截掉 close() 尚未 flush 的尾包。
  void _closeTransferSockets({bool destroyClient = false}) {
    try {
      _server?.close();
    } catch (_) {}
    try {
      _forwardSkt?.close();
    } catch (_) {}
    if (destroyClient) {
      try {
        _client?.destroy();
      } catch (_) {}
    }
  }

  void _cleanupStaging() {
    final dir = _stagingDir;
    _stagingDir = null;
    if (dir == null) return;
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}
  }

  ///在一定时间后检查是否真正开始传输，没有则关闭服务并推进队列。
  ///
  /// 旧实现只判断 hasClient，而 Android 的 content:// 分支在 await 插件流时
  /// 卡住也会先置 hasClient = true，导致这个兜底永远不会生效。
  void _delayedClientCheck(void Function() onDone) {
    Future.delayed(20.s, () {
      if (_doneCalled || (hasClient && _sendStarted)) return;
      if (hasClient && !_sendStarted) {
        // 已连上但仍卡在 content:// 解析：再给一段时间，避免大文件或慢
        // provider 被误杀；仍无进展才真正放弃。
        Future.delayed(30.s, () {
          if (_doneCalled || _sendStarted) return;
          logger.info(tag, "file transfer still not started, give up");
          _closeTransferSockets(destroyClient: true);
          onDone();
        });
        return;
      }
      logger.info(tag, "no client connection within 20 seconds, give up");
      _closeTransferSockets(destroyClient: true);
      onDone();
    });
  }

  /// 按配置在接收完成后发送通知，点击通知后打开接收的文件。
  static Future<void> _notifyReceivedFileIfNeeded({
    required ConfigService appConfig,
    required File file,
    required int fileId,
  }) async {
    if (!appConfig.notifyOnReceivedFile) {
      return;
    }
    await NotifyUtil.notify(
      title: file.fileName,
      content: TranslationKey.preferenceSettingsNotifyOnReceivedFileDesc.tr,
      key: '$_receivedFileNotifyKeyPrefix-$fileId',
      payload: NotificationPayload(
        type: NotificationPayloadType.openFile,
        data: {
          NotificationPayload.filePathKey: file.normalizePath,
        },
      ),
    );
  }

  //region 静态方法接收和发送文件

  ///给多个设备发送多个文件
  ///[devices] 发送的设备列表
  ///[files] 发送的文件列表
  ///[i] 发送第几个文件
  static void sendFiles({
    required List<Device> devices,
    required List<PendingFile> files,
    required BuildContext context,
    int i = 0,
  }) {
    if (i >= devices.length) {
      return;
    }
    //给每个设备发送文件
    _sendDevFiles(
      device: devices[i],
      paths: files,
      context: context,
      //发完一个设备后给下一个设备发送
      onDone: () => sendFiles(
        devices: devices,
        files: files,
        i: i + 1,
        context: context,
      ),
    );
  }

  ///给设备发送多个文件
  ///[device] 发送的设备
  ///[paths] 发送的文件列表
  ///[onDone] 发送完成事件
  ///[i] 发送第几个文件
  static void _sendDevFiles({
    required Device device,
    required List<PendingFile> paths,
    required void Function() onDone,
    required BuildContext context,
    int i = 0,
  }) {
    if (i >= paths.length) {
      onDone();
      return;
    }
    _sendFile(
      device: device,
      pendingFile: paths[i],
      context: context,
      //发完一个文件后给设备发送下一个文件
      onDone: () => _sendDevFiles(
        device: device,
        paths: paths,
        onDone: onDone,
        i: i + 1,
        context: context,
      ),
    );
  }

  ///发送文件
  ///[device] 发送的设备
  ///[pendingFile] 发送的文件地址
  static void _sendFile({
    required Device device,
    required PendingFile pendingFile,
    required void Function() onDone,
    required BuildContext context,
  }) async {
    // 这是 async void 入口，任何未捕获异常都会变成 Zone 级错误并且不再推进
    // 队列；用幂等的 finish() 统一收口，保证每个文件一定只推进一次。
    var finished = false;
    void finish() {
      if (finished) return;
      finished = true;
      onDone();
    }
    try {
      int totalSize;
      String fileName;
      if (pendingFile.isUri) {
        totalSize = pendingFile.size ?? 0;
        fileName = pendingFile.fileName ?? "file";
      } else {
        final file = File(pendingFile.filePath);
        totalSize = await file.length();
        fileName = file.fileName;
      }
      //如果存在多级文件夹就拼接上文件夹
      if (pendingFile.directories.isNotEmpty) {
        fileName = "${pendingFile.directories.join("/")}/$fileName";
      }
      if (device.isUseStorage) {
        final storageService = Get.find<StorageService>();
        final appConfig = Get.find<ConfigService>();
        // 存储中转也必须等待发送结束后再推进队列，否则多文件发送会卡在当前设备。
        // content:// 读取失败会一路抛到这里，必须收口，不能让队列断在异常上。
        try {
          await storageService.sendData(DevInfo.fromDevice(device), MsgType.file, {
            "fileId": appConfig.snowflake.nextId(),
            "filePath": pendingFile.filePath,
            "fileName": fileName,
            "isUri": pendingFile.isUri,
            "size": totalSize,
          });
        } catch (err, stack) {
          logger.error(tag, "storage send file failed. $err $stack");
          Global.showSnackBarWarn(text: TranslationKey.failedToLoad.tr);
        } finally {
          finish();
        }
      } else {
        final sktService = Get.find<SocketService>();
        final useForward = sktService.isUseForward(device.guid);
        FileSyncHandler._private(
          pendingFile: pendingFile,
          context: context,
          useForward: useForward,
          targetDevId: useForward ? device.guid : null,
          onReady: (syncer) async {
            device.sendData(MsgType.file, {
              "fileName": fileName,
              "size": totalSize,
              "port": syncer._server?.port,
              "fileId": syncer._fileId,
            });
          },
          onDone: finish,
        );
      }
    } catch (err, stack) {
      logger.error(tag, "prepare send file failed. $err $stack");
      Global.showSnackBarWarn(text: TranslationKey.failedToLoad.tr);
      finish();
    }
  }

  static Future<void> receiveFile({
    required String ip,
    required int port,
    required int size,
    required String fileName,
    required String devId,
    required int userId,
    required int fileId,
    required BuildContext context,
    bool isForward = false,
    String? targetId,
  }) async {
    //中转模式下targetId不能为null
    assert(!isForward || targetId != null);
    final dbService = Get.find<DbService>();
    final appConfig = Get.find<ConfigService>();
    Device? dev = await dbService.deviceDao.getById(devId, appConfig.userId);
    if (dev == null) {
      // 设备记录可能因用户 id 不同 / 尚未落库而查不到。旧实现直接 return，
      // 发送端却已经开好临时端口，只能一直等到超时，表现成"发不出去"。
      // 设备对象只用于展示来源，缺失时用发送端 guid 兜底，先保证文件能收到。
      logger.warn(tag, "dev:$devId not found in db, fallback to sender info");
      dev = Device.empty(
        guid: devId,
        devName: devId,
        uid: appConfig.userId,
        type: "unknown",
      );
    }
    // 发送端可能还没绑定好临时端口，或链路不通；给连接加超时，异常由上层记录并提示。
    final socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 30));
    final safeFileName = FileUtil.sanitizeReceivedFileName(fileName);
    String filePath = "${appConfig.fileStorePath}${Constants.dirSeparate}$safeFileName";
    File file = File(filePath);
    logger.debug(tag, "receive file $filePath");
    final dir = file.parent;
    //如果父级文件夹不存在则创建
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    ///文件存在处理策略：保留发送端带过来的目录层级，不能把文件丢回根目录
    while (file.existsSync()) {
      final seqName = file.buildDuplicateSeqName();
      filePath = "${file.parent.path}${Constants.dirSeparate}$seqName";
      file = File(filePath);
    }
    final syncingFileService = Get.find<SyncingFileProgressService>();
    final syncingFile = SyncingFile(
      // Android 的 content provider 可能把未知大小报成 -1，不能让它触发断言。
      totalSize: size < 0 ? 0 : size,
      context: context,
      filePath: filePath,
      fromDev: dev,
      sink: file.openWrite(),
      isSender: false,
      startTime: DateTime.now().format("yyyy-MM-dd HH:mm:ss"),
      onClose: (done) {
        if (done) {
          return;
        }
        socket.destroy();
        syncingFileService.removeSyncingFile(filePath);
      },
    );
    syncingFileService.updateSyncingFile(syncingFile);
    var start = DateTime.now();
    if (isForward) {
      //告知发送方接收方已经连接
      Map<String, String> data = {
        "connType": ForwardConnType.recFile.name,
        "target": targetId!,
        "fileId": fileId.toString(),
        "self": appConfig.device.guid,
      };
      final payload = utf8.encode(json.encode(data));
      final msgSize = payload.length;
      final header = SecureSocketClient.createPacketHeader(
        msgSize,
        msgSize,
        1,
        1,
      );
      // 组合头部和载荷
      Uint8List packet = Uint8List(header.length + payload.length);
      // 写入头部
      packet.setAll(0, header);
      // 写入载荷
      packet.setAll(header.length, payload);
      //写入数据
      socket.add(packet);
    }
    socket.listen(
      (bytes) {
        syncingFile.addBytes(bytes);
      },
      onError: (err, stack) {
        logger.error(tag, "receive file failed. $err $stack");
        Global.showSnackBarWarn(text: TranslationKey.failedToLoad.tr);
        socket.destroy();
        syncingFile.close(false);
        // close() 是异步的，等流落盘后再删，避免 Windows 上句柄未释放导致残留。
        unawaited(() async {
          await syncingFile.sinkDone;
          try {
            if (file.existsSync()) await file.delete();
          } catch (_) {}
        }());
      },
      cancelOnError: true,
      onDone: () async {
        try {
          // 对端发送完成后会主动关闭写端，本端必须立即释放 Socket，避免连接停留在 CLOSE_WAIT。
          socket.destroy();
          syncingFile.close(true);
          // 等文件流真正落盘，再判断结果、写历史记录，避免记录一个 0 字节的假成功。
          await syncingFile.sinkDone;
          final written = file.existsSync() ? await file.length() : 0;
          if (written <= 0) {
            logger.error(tag, "receive file $filePath failed: no data received");
            Global.showSnackBarWarn(text: TranslationKey.failedToLoad.tr);
            try {
              if (file.existsSync()) await file.delete();
            } catch (_) {}
            return;
          }
          if (size > 0 && written != size) {
            // 发送端声明的大小可能来自 content provider 元数据，与实际字节数不一致，
            // 只告警不丢文件，历史记录里写真实大小。
            logger.warn(tag, "receive file $filePath size mismatch: declared=$size, actual=$written");
          }
          var end = DateTime.now();
          int offset = max(end.difference(start).inSeconds, 1);
          int speed = written ~/ offset;
          logger.info(
            tag,
            "onDone $offset seconds, size: ${written.sizeStr}, speed: ${speed.sizeStr}/s",
          );
          var history = History(
            id: fileId,
            uid: userId,
            devId: devId,
            time: start.toString(),
            content: filePath,
            type: HistoryContentType.file.value,
            size: written,
            sync: true,
          );
          final historyController = Get.find<HistoryController>();
          await historyController.addData(history, null, false);
          await _notifyReceivedFileIfNeeded(
            appConfig: appConfig,
            file: file,
            fileId: fileId,
          );
          if (file.isMediaFile) {
            //媒体文件，刷新媒体库
            if (Platform.isAndroid) {
              var androidChannelService = Get.find<AndroidChannelService>();
              androidChannelService.notifyMediaScan(filePath);
            }
          }
        } catch (err, stack) {
          logger.error(tag, "finalize received file failed. $err $stack");
          Global.showSnackBarWarn(text: TranslationKey.failedToLoad.tr);
        }
      },
    );
  }

  //endregion
}
