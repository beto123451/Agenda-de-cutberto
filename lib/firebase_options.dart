import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions no está configurado para esta plataforma.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCL7uv_MmijNFoG-DvL86VoRbg6j2KJ_aU',
    appId: '1:844270208896:android:c33e19cd0b40ace607a365',
    messagingSenderId: '844270208896',
    projectId: 'cutberto',
    storageBucket: 'cutberto.firebasestorage.app',
  );
}
