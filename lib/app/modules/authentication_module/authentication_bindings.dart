import 'package:clipshare/app/modules/authentication_module/authentication_controller.dart';
import 'package:get/get.dart';
/**
 * GetX Template Generator - fb.com/htngu.99
 * */

class AuthenticationBinding implements Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => AuthenticationController());
  }
}