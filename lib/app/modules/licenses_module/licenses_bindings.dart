import 'package:clipshare/app/modules/licenses_module/licenses_controller.dart';
import 'package:get/get.dart';
/**
 * GetX Template Generator - fb.com/htngu.99
 * */

class LicensesBinding implements Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => LicensesController());
  }
}