import 'package:get/get.dart';

import 'clean_data_controller.dart';
/**
 * GetX Template Generator - fb.com/htngu.99
 * */

class CleanDataBinding implements Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => CleanDataController());
  }
}