import 'package:flutter/cupertino.dart';

abstract class BaseGuide {
  Widget widget;
  bool allowSkip;

  Future<bool> canNext();

  BaseGuide({
    this.widget = const SizedBox.shrink(),
    this.allowSkip = false,
  });
}
