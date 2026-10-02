# 서버 배포와 실제 폰

작업 005 슬라이스 8. 설계 5h. Supabase와 Google Cloud 계정, 배포 명령, 출시 서명 키는 사용자가 직접 만들고 돌린다. Claude는 무엇을 누르는지 안내하고, 사용자가 붙여 준 결과로 확인한다. 화면의 메뉴 이름은 콘솔이 바뀌면 조금 다를 수 있다.

먼저 할 것: [로그인 준비](login-setup.md)의 1, 2, 3을 마친다. 카카오 앱 ID, 카카오 네이티브 앱 키, Google 웹 클라이언트 ID가 있어야 한다.

명령은 모두 Git Bash에서 돌린다.

받을 값과 넣을 곳

| 값 | 어디서 | 어디에 넣나 | 비밀인가 |
|---|---|---|---|
| Supabase DB 비밀번호 | Supabase 프로젝트를 만들 때 | DB 주소 안 | 비밀. 비밀번호 관리자에만 둔다 |
| DB 주소 | Supabase의 Connect | Google Secret Manager의 `cherry-database-url` | 비밀. 채팅이나 파일에 붙이지 않는다 |
| 서버 주소 | 배포가 끝나면 나온다 | 앱 빌드 옵션 `API_URL` | 아니다 |
| 출시 키 파일과 비밀번호 | `keytool` | `app/android/key.properties` | 비밀. 저장소에 올리지 않는다 |

## 1. Supabase

1. https://supabase.com 에 가입하고 New project를 누른다
2. 이름은 `cherryconsume`, Region은 **Northeast Asia (Seoul)** 이다. Database Password는 Generate a password로 만든다. 특수문자가 있으면 주소에 넣을 때 깨지니 영문과 숫자만 있는 값을 쓴다. 비밀번호 관리자에 적어 둔다
3. 만들 때 Security의 세 칸을 모두 끈다. **Enable Data API**, **Automatically expose new tables**, **Enable automatic RLS**다. Data API는 표를 인터넷 API로 공개하는 기능이라 우리는 쓰지 않는다. 새 표의 행 단위 보안은 우리 마이그레이션이 켠다
4. 만든 뒤 Integrations → Data API → Overview에서 **Enable Data API**를 끈다. 화면이 다르면 Project Settings → Data API에서 찾는다. 꺼짐으로 보이면 성공이다. 3에서 이미 껐어도 꺼졌는지 본다
5. 위쪽의 Connect를 누르고 Connection String에서 Method를 **Session pooler**로 바꾼다. `postgresql://postgres.영문:[YOUR-PASSWORD]@aws-...-ap-northeast-2.pooler.supabase.com:5432/postgres` 꼴의 주소가 보인다. Direct connection 주소인 `db.영문.supabase.co`는 Cloud Run에서 닿지 않는다
6. 그 주소의 `[YOUR-PASSWORD]`를 2의 비밀번호로 바꾸고 끝에 `?sslmode=require`를 붙인다. 이것이 DB 주소다
7. 터미널에 DB 주소를 넣어 둔다. 화면과 명령 기록에 남지 않게 붙여 넣고 Enter를 누른다. 2의 5까지 이 터미널을 닫지 않는다

   ```bash
   read -rs DB
   ```

8. 닿는지 본다. `PostgreSQL 17`로 시작하는 줄이 보이면 성공이다

   ```bash
   docker run --rm postgres:17 psql "$DB" -Atc "select version()"
   ```

## 2. Google Cloud

1. https://console.cloud.google.com 에서 로그인 준비 때 만든 `cherryconsume` 프로젝트를 고른다
2. 결제 → 결제 계정을 연결한다. 카드를 등록한다. 프로젝트의 결제 화면에 결제 계정 이름이 보이면 성공이다
3. 결제 → 예산 및 알림 → 예산 만들기. 금액은 5,000원, 알림은 50%, 90%, 100%다. 목록에 예산이 보이면 성공이다. 알림은 쓰는 돈을 막지 않고 메일로 알리기만 한다
4. https://cloud.google.com/sdk/docs/install 에서 Windows용 Google Cloud CLI를 깐다. 새 Git Bash를 열고 1의 7을 다시 한 뒤 아래를 돌린다. 브라우저에서 로그인하고 `cherryconsume` 프로젝트를 고른다

   ```bash
   gcloud init
   ```

   프로젝트 ID가 보이면 성공이다

   ```bash
   gcloud config get project
   ```

5. 쓸 기능을 켠다. `finished successfully`가 보이면 성공이다

   ```bash
   gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com secretmanager.googleapis.com iam.googleapis.com
   ```

6. DB 주소를 비밀 저장소에 넣는다. `Created version [1]`이 보이면 성공이다

   ```bash
   printf %s "$DB" | gcloud secrets create cherry-database-url --data-file=-
   ```

7. 서버만 쓰는 계정을 만든다. 이 계정은 DB 주소를 읽는 것 말고 아무 권한이 없다. 서버가 뚫려도 이미지나 다른 설정을 건드리지 못한다. `Created service account`가 보이면 성공이다

   ```bash
   gcloud iam service-accounts create cherry-api
   ```

8. 계정 이름 둘을 터미널에 넣어 둔다. 첫째는 서버 계정, 둘째는 이미지를 만드는 기본 계정이다

   ```bash
   P="$(gcloud config get project | tr -d '\r')"; RUN_SA="cherry-api@$P.iam.gserviceaccount.com"; BUILD_SA="$(gcloud projects describe "$P" --format='value(projectNumber)' | tr -d '\r')-compute@developer.gserviceaccount.com"
   ```

9. 서버 계정은 DB 주소를 읽고, 기본 계정은 이미지를 만들 수 있게 허락한다. 두 명령 모두 `Updated IAM policy`가 보이면 성공이다

   ```bash
   gcloud secrets add-iam-policy-binding cherry-database-url --member="serviceAccount:$RUN_SA" --role=roles/secretmanager.secretAccessor
   ```

   ```bash
   gcloud projects add-iam-policy-binding "$P" --member="serviceAccount:$BUILD_SA" --role=roles/run.builder
   ```

10. 저장소 맨 위에서 올라갈 파일을 본다. `Dockerfile`, `.dockerignore`, `backend/cherry_api/`, `backend/cherry_core/`, `backend/pyproject.toml`, `backend/uv.lock`, `catalog/` 아래 파일만 보이면 성공이다. `app/`, `docs/`, `key.properties`, `.env`가 하나라도 보이면 배포하지 말고 그 목록을 붙여 준다

    ```bash
    gcloud meta list-files-for-upload .
    ```

11. 저장소 맨 위에서 배포한다. 처음이면 이미지 저장소를 만들지 묻는다. Y를 누른다. 3분에서 5분 걸린다. `Service URL: https://cherry-api-...run.app`이 보이면 성공이다. 이 주소가 서버 주소다

    ```bash
    gcloud run deploy cherry-api --source . --region asia-northeast3 --allow-unauthenticated --max-instances 2 --memory 512Mi --cpu-boost --service-account "$RUN_SA" --set-secrets CHERRY_DATABASE_URL=cherry-database-url:latest --set-env-vars CHERRY_KAKAO_APP_ID=카카오_앱_ID,CHERRY_GOOGLE_CLIENT_ID=웹_클라이언트_ID
    ```

12. 서버가 답하는지 본다. 카드사 이름 목록이 보이면 성공이다. 처음 부르면 서버가 켜지느라 몇 초 걸린다

    ```bash
    curl https://서버_주소/catalog/issuers
    ```

## 3. 출시 서명 키

출시 빌드는 디버그 키 대신 이 키로 서명한다. 키를 잃으면 폰에 깐 앱을 지우지 않고는 새 판으로 바꿀 수 없다.

1. 키를 저장소 밖의 따로 쓰는 폴더에 만든다. `~/.android`는 adb가 꼬일 때 통째로 지우라는 안내가 흔해 쓰지 않는다. 비밀번호를 두 번 넣고 이름 같은 질문은 Enter로 넘긴다. 마지막에 맞는지 물으면 `y`다. `Storing`이 보이면 성공이다

   ```bash
   mkdir -p ~/keys && keytool -genkeypair -v -keystore ~/keys/cherry-upload.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
   ```

2. 키 파일 `C:/Users/SSAFY/keys/cherry-upload.jks`를 USB나 개인 클라우드 드라이브에 한 부 더 둔다. 비밀번호는 비밀번호 관리자에 둔다. 이 PC를 나중에 반납하면 반납 전에 키와 5의 백업을 옮기고 이 PC에서 지운다
3. `app/android/key.properties`를 새로 만들어 네 줄을 쓴다. 이 파일은 저장소에 올라가지 않는다. 키 비밀번호는 1에서 넣은 비밀번호와 같다. 경로는 `C:/`로 시작하는 전체 경로로, 역슬래시 대신 `/`로 쓴다

   ```
   storeFile=C:/Users/SSAFY/keys/cherry-upload.jks
   storePassword=1에서_넣은_비밀번호
   keyAlias=upload
   keyPassword=1에서_넣은_비밀번호
   ```

4. 출시 키의 SHA-1을 본다. `SHA1:`로 시작하는 줄이다

   ```bash
   keytool -list -v -keystore ~/keys/cherry-upload.jks -alias upload
   ```

5. 출시 키의 카카오 키 해시를 본다. `=`로 끝나는 한 줄이다

   ```bash
   keytool -exportcert -alias upload -keystore ~/keys/cherry-upload.jks | openssl sha1 -binary | openssl base64
   ```

6. 카카오 개발자 콘솔의 Android 키 해시 칸에 5의 값을 한 줄 더 넣는다. 디버그 키 해시는 지우지 않는다. 두 줄이 보이면 성공이다
7. Google Cloud의 클라이언트 → 클라이언트 만들기 → 유형 Android, 패키지 이름 `com.cherryconsume.app`, SHA-1은 4의 값이다. 디버그용 Android 클라이언트는 그대로 둔다. Android 클라이언트가 두 개 보이면 성공이다

## 4. 실제 폰에서 한 흐름

1. app 폴더에서 출시 APK를 만든다. 폰에는 출시 APK만 깐다. profile 빌드는 디버그 키로 서명된다. `Built build\app\outputs\flutter-apk\app-release.apk`가 보이면 성공이다

   ```bash
   flutter build apk --release --dart-define=API_URL=https://서버_주소 --dart-define=KAKAO_NATIVE_APP_KEY=카카오_네이티브_앱_키 --dart-define=GOOGLE_SERVER_CLIENT_ID=웹_클라이언트_ID
   ```

2. 폰을 USB로 잇는다. 디버그 앱이 깔려 있으면 서명이 달라 덮어쓰지 못하니 먼저 지운다. 디버그 앱의 기록은 PC 서버에 있어 지워도 잃지 않는다

   ```bash
   adb uninstall com.cherryconsume.app
   ```

3. 출시 APK를 깐다. `Success`가 보이면 성공이다

   ```bash
   adb install build/app/outputs/flutter-apk/app-release.apk
   ```

4. USB를 빼고 Wi-Fi를 끈 채 LTE로 해 본다. 순서는 시작 화면에서 카카오로 시작, 빈 홈, 카드 검색, 등록 시트, 카드가 든 홈, 결제 기록, 추천, 추천에서 결제 기록이다. 끊기는 곳 없이 끝나면 성공이다
5. 안 되면 그 화면을 찍고, Google Cloud 콘솔 → Cloud Run → `cherry-api` → 로그의 마지막 몇 줄을 붙여 준다. 로그에 사용자 번호가 보이면 가리고 붙인다

## 5. 백업

Supabase 무료는 자동 백업이 없다. 실제 사용자가 생기기 전에 유료 전환이나 정기 백업을 정한다. 그 전까지는 일주일에 한 번 PC에 떠 둔다. 1의 7을 먼저 한다.

```bash
mkdir -p ~/cherry-backups && docker run --rm postgres:17 pg_dump "$DB" -n public -Fc > ~/cherry-backups/cherry-$(date +%Y%m%d).dump && echo 백업 성공
```

`백업 성공`이 보이면 성공이다. 우리 표가 든 `public` 스키마만 떠서 다른 Postgres에도 복원할 수 있다. 사용자 기록이 들어 있으니 저장소나 공개 폴더에 두지 않는다.

## 다시 배포할 때

서버 코드나 카탈로그가 바뀌면 저장소 맨 위에서 다시 배포한다. 환경변수와 비밀은 그대로 남는다. 서버와 앱이 함께 바뀌었으면 서버를 먼저 배포하고 앱을 나중에 깐다. 옛 서버는 새 앱이 싣는 칸을 몰라 저장을 거절한다.

```bash
gcloud run deploy cherry-api --source . --region asia-northeast3
```

## 자주 나는 것

- 배포 중 권한 오류: 2의 9의 둘째 명령을 빠뜨렸다
- 서버가 켜지지 않고 로그에 `Network is unreachable`: Direct connection 주소를 넣었다. 1의 5부터 다시 해 Session pooler 주소를 만들고, 아래로 새 판을 넣은 뒤 다시 배포한다
- 로그에 `password authentication failed`: DB 주소의 비밀번호가 틀렸다. 고치는 방법은 바로 위와 같다

  ```bash
  printf %s "$DB" | gcloud secrets versions add cherry-database-url --data-file=-
  ```

- 로그에 `Permission denied on secret`: 2의 9의 첫 명령을 빠뜨렸다
- 로그에 `prepared statement` 오류: DB 주소의 포트가 6543이면 Transaction pooler를 고른 것이다. 1의 5에서 Session pooler를 고른다
- 앱이 "서버에 연결하지 못했어요": `API_URL`이 `https://`로 시작하는지, 끝에 `/`가 붙지 않았는지 본다
- 카카오 키 해시 오류나 Google 설정 오류: 3의 6, 3의 7을 빠뜨렸다
- Supabase가 멈췄다는 메일: 1주일 동안 쓰지 않았다. Supabase 화면에서 Restore를 누른다. 데이터는 남아 있다. 멈춘 지 90일이 지나면 화면에서 다시 켤 수 없으니 그 전에 켠다
