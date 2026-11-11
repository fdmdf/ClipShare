import 'package:clipshare/app/modules/qr_code_scanner_module/qr_code_scanner_controller.dart';
import 'package:get/get.dart';
/**
 * GetX Template Generator - fb.com/htngu.99
 * */

class QRCodeScannerBinding implements Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => QRCodeScannerController());
  }
}