import 'package:clipshare/app/modules/working_mode_selection_module/working_mode_selection_controller.dart';
import 'package:get/get.dart';
/**
 * GetX Template Generator - fb.com/htngu.99
 * */

class WorkingModeSelectionBinding implements Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => WorkingModeSelectionController());
  }
}