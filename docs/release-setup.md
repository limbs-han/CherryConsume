# 출시 서명과 실제 폰

작업 006 단계 7과 8. 서버가 없어져 옛 `deploy-setup.md`에서 출시 서명 키와 실제 폰 부분만 옮겼다. 키와 비밀번호는 사용자가 직접 만들고 넣는다. Claude는 무엇을 누르는지 안내하고, 사용자가 붙여 준 결과로 확인한다.

명령은 모두 PowerShell에서 돌린다. Windows에 기본으로 깔린 PowerShell 5.1 기준이다.

`keytool`이나 `adb`를 찾지 못한다고 나오면 전체 경로로 부른다. 이 PC의 `adb`는 `C:\Users\SSAFY\dev\android-sdk\platform-tools\adb.exe`다. `keytool`은 Android Studio 설치 폴더의 `jbr\bin\keytool.exe`다.

| 값 | 어디서 | 어디에 넣나 | 비밀인가 |
|---|---|---|---|
| 출시 키 파일과 비밀번호 | `keytool` | `app/android/key.properties` | 비밀. 저장소에 올리지 않는다 |

## 1. 출시 서명 키

출시 빌드는 디버그 키 대신 이 키로 서명한다. 키를 잃으면 폰에 깐 앱을 지우지 않고는 새 판으로 바꿀 수 없다. 이미 만들었으면 4로 맞는지만 본다.

1. 키를 저장소 밖의 따로 쓰는 폴더에 만든다. `~\.android`는 adb가 꼬일 때 통째로 지우라는 안내가 흔해 쓰지 않는다. 비밀번호를 두 번 넣고 이름 같은 질문은 Enter로 넘긴다. 마지막에 맞는지 물으면 `y`다. `Storing`이 보이면 성공이다

   ```powershell
   New-Item -ItemType Directory -Force ~\keys | Out-Null; keytool -genkeypair -v -keystore "$HOME\keys\cherry-upload.jks" -alias upload -keyalg RSA -keysize 2048 -validity 10000
   ```

2. 키 파일 `C:\Users\SSAFY\keys\cherry-upload.jks`를 USB나 개인 클라우드 드라이브에 한 부 더 둔다. 비밀번호는 비밀번호 관리자에 둔다. 이 PC를 나중에 반납하면 반납 전에 키를 옮기고 이 PC에서 지운다
3. `app\android\key.properties`를 새로 만들어 네 줄을 쓴다. 이 파일은 저장소에 올라가지 않는다. 키 비밀번호는 1에서 넣은 비밀번호와 같다. 이 파일 안의 경로는 역슬래시 대신 `/`로 쓴다

   ```
   storeFile=C:/Users/SSAFY/keys/cherry-upload.jks
   storePassword=1에서_넣은_비밀번호
   keyAlias=upload
   keyPassword=1에서_넣은_비밀번호
   ```

4. 키가 열리는지 본다. 비밀번호를 물으면 1의 비밀번호다. `Alias name: upload`가 보이면 성공이다

   ```powershell
   keytool -list -v -keystore "$HOME\keys\cherry-upload.jks" -alias upload
   ```

## 2. 실제 폰에 깔기

1. app 폴더에서 출시 APK를 만든다. 폰에는 출시 APK만 깐다. profile 빌드는 디버그 키로 서명된다. `Built build\app\outputs\flutter-apk\app-release.apk`가 보이면 성공이다

   ```powershell
   flutter build apk --release
   ```

2. 폰을 USB로 잇는다. 디버그 앱이 깔려 있으면 서명이 달라 덮어쓰지 못해 먼저 지워야 한다. 기록은 폰 안에만 있어 앱을 지우면 함께 지워진다. 남길 기록이 있으면 먼저 디버그 앱의 설정 → 기록 내보내기로 파일을 만든다

   ```powershell
   adb uninstall com.cherryconsume.app
   ```

3. 출시 APK를 깐다. `Success`가 보이면 성공이다. 2에서 내보낸 파일이 있으면 설정 → 기록 가져오기로 되살린다

   ```powershell
   adb install build\app\outputs\flutter-apk\app-release.apk
   ```

## 3. 기록 지키기

기록은 폰 안에만 있고 Android 자동 백업은 꺼져 있다. 폰을 바꾸거나 초기화하기 전에는 설정 → 기록 내보내기로 파일을 만들어 PC나 개인 드라이브에 둔다. 파일에는 결제 기록이 그대로 들어 있어 남에게 보내지 않는다.
