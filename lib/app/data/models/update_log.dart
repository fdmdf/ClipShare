import 'dart:convert';
import 'dart:io';

import 'package:clipshare/app/data/models/clip_data.dart';
import 'package:clipshare/app/data/models/version.dart';
import 'package:clipshare/app/utils/extensions/string_extension.dart';
import 'package:clipshare/app/utils/extensions/time_extension.dart';

class UpdateLog {
  final String platform;
  final DateTime date;
  final AppVersion version;
  final String desc;
  final String downloadUrl;

  const UpdateLog({
    required this.platform,
    required this.date,
    required this.version,
    required this.desc,
    required this.downloadUrl,
  });

  factory UpdateLog.fromJson(Map<String, dynamic> json) {
    final versionCode = json['version']['code'];
    final versionName = json['version']['name'];
    return UpdateLog(
      platform: json['platform'],
      date: DateTime.parse(json['date']),
      version: AppVersion(versionName, versionCode),
      desc: json['desc'],
      downloadUrl: json['url'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "platform": platform,
      "date": date.format(),
      "version": version.toString(),
      "desc": desc,
      "downloadUrl": downloadUrl,
    };
  }

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}
