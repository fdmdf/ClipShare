import 'package:clipshare/app/modules/debug_module/debug_controller.dart';
import 'package:get/get.dart';
/**
 * GetX Template Generator - fb.com/htngu.99
 * */

class DebugBinding implements Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => DebugController());
  }
}