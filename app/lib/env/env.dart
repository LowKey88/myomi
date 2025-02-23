import 'package:friend_private/env/dev_env.dart';
import 'package:friend_private/backend/preferences.dart';

abstract class Env {
  static late final EnvFields _instance;

  static void init([EnvFields? instance]) {
    _instance = instance ?? DevEnv() as EnvFields;
  }

   static String? get openAIAPIKey {
    final prefValue = SharedPreferencesUtil().openAiApiKey;
    return (prefValue == '' ) 
        ? _instance.openAIAPIKey 
        : prefValue;
  }

  static String? get apiBaseUrl {
    final prefValue = SharedPreferencesUtil().apiBaseUrl;
    return (prefValue == '' )
        ? _instance.apiBaseUrl
        : prefValue; 
  }
  static String? get instabugApiKey => _instance.instabugApiKey;

  static String? get mixpanelProjectToken => _instance.mixpanelProjectToken;

  // static String? get apiBaseUrl => 'https://based-hardware-development--backened-dev-api.modal.run/';
  // static String? get apiBaseUrl => 'https://camel-lucky-reliably.ngrok-free.app/';
  // static String? get apiBaseUrl => 'https://mutual-fun-boar.ngrok-free.app/';

  static String? get growthbookApiKey => _instance.growthbookApiKey;

  static String? get googleMapsApiKey => _instance.googleMapsApiKey;

  static String? get intercomAppId => _instance.intercomAppId;

  static String? get intercomIOSApiKey => _instance.intercomIOSApiKey;

  static String? get intercomAndroidApiKey => _instance.intercomAndroidApiKey;

  static String? get posthogApiKey => _instance.posthogApiKey;
}

abstract class EnvFields {
  String? get openAIAPIKey;

  String? get instabugApiKey;

  String? get mixpanelProjectToken;

  String? get apiBaseUrl;

  String? get growthbookApiKey;

  String? get googleMapsApiKey;

  String? get intercomAppId;

  String? get intercomIOSApiKey;

  String? get intercomAndroidApiKey;

  String? get posthogApiKey;
}
