import 'package:clipshare/app/modules/clean_data_module/clean_data_controller.dart';
import 'package:clipshare/app/modules/device_module/device_controller.dart';
import 'package:clipshare/app/modules/splash_module/splash_controller.dart';
import 'package:clipshare/app/services/config_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
/**
 * GetX Template Generator - fb.com/htngu.99
 * */

class SplashBinding implements Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => SplashController());
    Get.put(DeviceController(), permanent: true);
    Get.put(CleanDataController(), permanent: true);
  }
}
