import 'dart:convert';

import 'package:clipshare/app/services/config_service.dart';
import 'package:floor/floor.dart';
import 'package:get/get.dart';

@Entity(
  indices: [
    Index(value: ['tagName', "hisId"], unique: true),
  ],
)
class HistoryTag {
  ///主键 id
  @PrimaryKey(autoGenerate: true)
  late int id;

  ///标签名称
  late String tagName;

  /// 历史 id
  late int hisId;

  HistoryTag(this.tagName, this.hisId, [int? id]) {
    final appConfig = Get.find<ConfigService>();
    this.id = id ?? appConfig.snowflake.nextId();
  }

  HistoryTag.empty({this.id = 0, this.tagName = "", this.hisId = 0});

  static HistoryTag fromJson(Map<String, dynamic> map) {
    return HistoryTag(
      map["tagName"],
      map["hisId"],
      map["id"],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "tagName": tagName,
      "hisId": hisId,
    };
  }

  @override
  String toString() {
    return jsonEncode(toJson());
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HistoryTag && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
