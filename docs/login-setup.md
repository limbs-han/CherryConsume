# 카카오와 Google 로그인 준비

작업 005 슬라이스 7. 카카오와 Google 개발자 앱은 사용자가 직접 만든다. Claude는 무엇을 누르는지 안내하고, 사용자가 붙여 준 결과로 확인한다. 화면의 메뉴 이름은 콘솔이 바뀌면 조금 다를 수 있다.

앱 정보
- 패키지 이름: `com.cherryconsume.app`
- 이 PC 디버그 키의 SHA-1: `2A:7F:6A:9E:1E:B3:F4:CD:5D:98:1A:E4:96:F3:42:A8:15:B2:CA:CD`
- 이 PC 디버그 키의 카카오 키 해시: `Kn9qnh6z9M1dmBrklvNCqBWyys0=`
- 디버그 키는 이 PC의 `~/.android/debug.keystore`다. 다른 PC나 출시 빌드는 키가 달라 그 키의 값을 따로 등록한다. 출시 키는 슬라이스 8에서 만든다

받을 값과 넣을 곳

| 값 | 어디서 | 어디에 넣나 | 비밀인가 |
|---|---|---|---|
| 카카오 앱 ID | 카카오 앱의 일반 정보 | 서버 환경변수 `CHERRY_KAKAO_APP_ID` | 아니다. 앱이 받은 토큰이 우리 앱 것인지 볼 때 쓴다 |
| 카카오 네이티브 앱 키 | 카카오 앱의 앱 키 | `app/android/local.properties`의 `kakao.nativeAppKey`와 빌드 옵션 `KAKAO_NATIVE_APP_KEY` | 앱 안에 들어가 비밀은 아니지만 저장소에 올리지 않는다 |
| Google 웹 클라이언트 ID | Google Cloud의 OAuth 클라이언트 | 서버 환경변수 `CHERRY_GOOGLE_CLIENT_ID`와 빌드 옵션 `GOOGLE_SERVER_CLIENT_ID` | 아니다. 서버가 받은 토큰의 받는 쪽을 볼 때 쓴다 |

REST API 키, 어드민 키, 클라이언트 보안 비밀은 쓰지 않는다. 받지 않아도 된다.

## 1. 카카오

1. https://developers.kakao.com 에 카카오 계정으로 로그인한다
2. 내 애플리케이션 → 애플리케이션 추가하기. 앱 이름은 `체리컨슘`, 회사명은 본인 이름이다. 저장하면 앱 목록에 체리컨슘이 보인다
3. 체리컨슘의 요약이나 일반 정보에서 **앱 ID** 숫자를 적어 둔다
4. 앱 → 플랫폼 키에서 **네이티브 앱 키**를 적어 둔다. 개편 전 콘솔에서는 앱 설정 → 앱 키다
5. Android 앱을 등록한다. 지금 콘솔은 네이티브 앱 키 안에서, 개편 전 콘솔은 앱 설정 → 플랫폼 → Android 플랫폼 등록에서 한다. 패키지명 `com.cherryconsume.app`, 키 해시 `Kn9qnh6z9M1dmBrklvNCqBWyys0=`를 넣고 저장한다. 목록에 패키지명이 보이면 성공이다
6. 카카오 로그인 → 일반에서 사용 설정을 켠다. 개편 전 콘솔에서는 제품 설정 → 카카오 로그인 → 활성화 설정이다. 상태가 켜짐이면 성공이다
7. 동의항목은 아무것도 켜지 않는다. 서버는 카카오 사용자 번호만 쓰고 이름, 이메일, 사진을 받지 않는다. 동의항목 없이 로그인이 되지 않으면 그 화면을 붙여 준다

## 2. Google

1. https://console.cloud.google.com 에 Google 계정으로 로그인하고 새 프로젝트를 만든다. 이름은 `cherryconsume`이다
2. Google 인증 플랫폼이나 OAuth 동의 화면에서 시작한다. 앱 이름 `체리컨슘`, 지원 이메일은 본인 메일, 대상은 외부다. 테스트 사용자에 로그인해 볼 본인 Gmail을 더한다. 테스트 사용자만 로그인할 수 있는 상태라 출시 전까지는 이대로 둔다
3. 클라이언트 → 클라이언트 만들기 → 유형 **웹 애플리케이션**, 이름 `cherry-server`. 만들면 나오는 **클라이언트 ID**를 적어 둔다. `....apps.googleusercontent.com`으로 끝난다. 클라이언트 보안 비밀은 쓰지 않는다
4. 클라이언트 만들기를 한 번 더 → 유형 **Android**, 패키지 이름 `com.cherryconsume.app`, SHA-1 `2A:7F:6A:9E:1E:B3:F4:CD:5D:98:1A:E4:96:F3:42:A8:15:B2:CA:CD`. 이 클라이언트의 ID는 어디에도 넣지 않는다. Google이 패키지와 서명으로 우리 앱을 알아본다

## 3. 키 넣기

1. `app/android/local.properties`에 한 줄을 더한다. 이 파일은 저장소에 올라가지 않는다. 앞 줄 끝에 붙지 않게 새 줄에 쓴다. 붙으면 Flutter가 빌드할 때 그 줄을 지운다

   ```
   kakao.nativeAppKey=카카오_네이티브_앱_키
   ```

2. 서버를 켤 때 환경변수를 준다. backend 폴더에서 돌린다

   ```bash
   CHERRY_DEV_LOGIN=1 CHERRY_KAKAO_APP_ID=카카오_앱_ID CHERRY_GOOGLE_CLIENT_ID=웹_클라이언트_ID CHERRY_DATABASE_URL=postgresql://cherry:cherry@127.0.0.1:5433/cherry uv run uvicorn cherry_api.main:create_app --factory --port 8000
   ```

## 4. 실제 폰에서 해 보기

1. 폰의 개발자 옵션에서 USB 디버깅을 켜고 PC에 USB로 잇는다. `flutter devices`에 폰이 보이면 성공이다
2. 폰이 PC의 서버에 닿게 한다. app 폴더에서 돌린다

   ```bash
   adb reverse tcp:8000 tcp:8000
   ```

3. 앱을 폰에 깐다. app 폴더에서 돌린다

   ```bash
   flutter run --dart-define=API_URL=http://127.0.0.1:8000 --dart-define=KAKAO_NATIVE_APP_KEY=카카오_네이티브_앱_키 --dart-define=GOOGLE_SERVER_CLIENT_ID=웹_클라이언트_ID
   ```

4. 시작 화면에서 "카카오로 시작"을 누른다. 카카오톡이나 카카오 계정 화면이 뜨고, 동의하면 빈 홈이 보이면 성공이다
5. 설정 → 로그아웃 뒤 "Google로 시작"을 누른다. Google 계정을 고르면 빈 홈이 보이면 성공이다. 카카오와 다른 새 계정이다. E29
6. 안 되면 앱 화면은 "로그인하지 못했어요"만 보인다. `flutter run`을 돌린 창의 "로그인 실패:"로 시작하는 줄과 서버 창의 마지막 몇 줄을 붙여 준다. 디버그 빌드에서만 까닭을 찍는다

자주 나는 것
- 카카오 키 해시 오류: 1의 5에 넣은 키 해시와 이 PC의 키가 다르다
- Google `GoogleSignInException`의 설정 오류: 2의 4의 SHA-1이나 패키지 이름이 다르거나, 빌드 옵션의 웹 클라이언트 ID가 다르다
- "GOOGLE_SERVER_CLIENT_ID 없이 빌드했다"나 "KAKAO_NATIVE_APP_KEY 없이 빌드했다": `flutter run`에 그 빌드 옵션을 빠뜨렸다
- 서버 401: 서버 환경변수의 앱 ID나 웹 클라이언트 ID가 앱과 다르다. Google만 401이면 서버가 Google 토큰 확인 API를 POST로 부르는 것이 원인일 수 있다. 그 줄을 붙여 주면 GET으로 바꿔 본다
- 서버 503: 서버를 켤 때 환경변수를 주지 않았다
