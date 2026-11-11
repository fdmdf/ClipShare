import 'package:clipshare/app/modules/log_module/log_controller.dart';
import 'package:get/get.dart';
/**
 * GetX Template Generator - fb.com/htngu.99
 * */

class LogBinding implements Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => LogController());
  }
}