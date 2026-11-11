import 'package:clipshare/app/modules/update_log_module/update_log_controller.dart';
import 'package:get/get.dart';
/**
 * GetX Template Generator - fb.com/htngu.99
 * */

class UpdateLogBinding implements Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => UpdateLogController());
  }
}