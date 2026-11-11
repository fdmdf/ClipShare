import 'package:clipshare/app/data/enums/translation_key.dart';
import 'package:flutter/material.dart';

extension ThemeModeExt on ThemeMode {

  TranslationKey get tk {
    switch (this) {
      case ThemeMode.system:
        return TranslationKey.themeAuto;
      case ThemeMode.light:
        return TranslationKey.themeLight;
      case ThemeMode.dark:
        return TranslationKey.themeDark;
      default:
        throw Exception("Unknown theme mode $name");
    }
  }
}