/// 카카오와 Google에서 로그인 토큰을 받는다. 서버가 그 토큰을 확인하고 우리 토큰을 준다. 작업 005 설계 5g
///
/// 키는 빌드할 때 `--dart-define=KAKAO_NATIVE_APP_KEY=...`와 `--dart-define=GOOGLE_SERVER_CLIENT_ID=...`로 넣는다.
/// 카카오 키는 `android/local.properties`의 `kakao.nativeAppKey`에도 둔다. 둘 다 저장소에 올리지 않는다
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

const _kakaoKey = String.fromEnvironment('KAKAO_NATIVE_APP_KEY');
const _googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

/// 사용자가 로그인을 그만뒀는가. 그만두면 아무 말도 하지 않는다
bool _cancelled(Object e) =>
    (e is PlatformException && e.code == 'CANCELED') ||
    (e is KakaoClientException && e.reason == ClientErrorCause.cancelled) ||
    (e is KakaoAuthException && e.error == AuthErrorCause.accessDenied) ||
    (e is GoogleSignInException &&
        e.code == GoogleSignInExceptionCode.canceled);

/// 디버그 빌드에서만 실패 까닭을 찍는다. 안내서 docs/login-setup.md대로 진단할 수 있게 한다
void _trace(String what, Object e) {
  if (kDebugMode) debugPrint('$what 실패: $e');
}

/// 로그인 수단마다 토큰을 받는다. 사용자가 그만두면 null이다. 시험에서는 바꿔 끼운다
class Social {
  const Social();

  static Future<void>? _kakaoReady;
  static Future<void>? _googleReady;

  /// 초기화가 실패하면 다음에 다시 한다. 한 번 실패로 앱을 다시 켤 때까지 막히지 않게 한다
  Future<void> _kakao() async {
    if (_kakaoKey.isEmpty) throw StateError('KAKAO_NATIVE_APP_KEY 없이 빌드했다');
    try {
      await (_kakaoReady ??= KakaoSdk.init(nativeAppKey: _kakaoKey));
    } catch (_) {
      _kakaoReady = null;
      rethrow;
    }
  }

  Future<void> _google() async {
    if (_googleServerClientId.isEmpty) {
      throw StateError('GOOGLE_SERVER_CLIENT_ID 없이 빌드했다');
    }
    try {
      await (_googleReady ??= GoogleSignIn.instance.initialize(
        serverClientId: _googleServerClientId,
      ));
    } catch (_) {
      _googleReady = null;
      rethrow;
    }
  }

  /// 카카오 접근 토큰. 카카오톡이 있으면 카카오톡으로, 없거나 그만두지 않고 실패하면 카카오 계정으로 로그인한다
  Future<String?> kakao() async {
    try {
      await _kakao();
      if (await isKakaoTalkInstalled()) {
        try {
          return (await UserApi.instance.loginWithKakaoTalk()).accessToken;
        } catch (e) {
          if (_cancelled(e)) return null;
          _trace('카카오톡 로그인', e);
        }
      }
      return (await UserApi.instance.loginWithKakaoAccount()).accessToken;
    } catch (e) {
      if (_cancelled(e)) return null;
      _trace('카카오 로그인', e);
      rethrow;
    }
  }

  /// Google 신분 토큰. 서버가 받는 쪽을 볼 수 있게 웹 클라이언트 ID로 받는다
  Future<String?> google() async {
    try {
      await _google();
      final account = await GoogleSignIn.instance.authenticate();
      final token = account.authentication.idToken;
      // 신분 토큰이 없으면 웹 클라이언트 ID가 틀린 것이다. 그만둔 것과 가려 알린다
      if (token == null) throw StateError('Google 신분 토큰이 없다');
      return token;
    } catch (e) {
      if (_cancelled(e)) return null;
      _trace('Google 로그인', e);
      rethrow;
    }
  }

  /// 로그아웃할 때 그 수단의 로그인 상태도 지운다. 폰에 카카오 토큰이 남지 않게 한다
  Future<void> signOut(String provider) async {
    try {
      if (provider == 'kakao') {
        await _kakao();
        await UserApi.instance.logout();
      } else if (provider == 'google') {
        await _google();
        await GoogleSignIn.instance.signOut();
      }
    } catch (e) {
      _trace('로그아웃', e);
    }
  }

  /// 탈퇴할 때 그 수단과 앱의 연결을 끊는다. 실패해도 탈퇴는 된다. E36
  ///
  /// ponytail: 카카오 갱신 토큰이 만료됐거나 Google에 다시 들어가지 못하면 끊지 못하고 넘어간다. 서버에서 끊으려면
  /// 카카오 어드민 키가 있어야 한다
  Future<void> unlink(String provider) async {
    try {
      if (provider == 'kakao') {
        await _kakao();
        await UserApi.instance.unlink();
      } else if (provider == 'google') {
        await _google();
        // 앱을 다시 켠 뒤에는 Google이 계정을 기억하지 않아 먼저 조용히 다시 들어간다
        await GoogleSignIn.instance.attemptLightweightAuthentication();
        await GoogleSignIn.instance.disconnect();
      }
    } catch (e) {
      _trace('연결 끊기', e);
    }
    await signOut(provider);
  }
}
