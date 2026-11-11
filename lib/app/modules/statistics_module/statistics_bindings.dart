import 'package:clipshare/app/modules/statistics_module/statistics_controller.dart';
import 'package:get/get.dart';
/**
 * GetX Template Generator - fb.com/htngu.99
 * */

class StatisticsBinding implements Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => StatisticsController());
  }
}