# 77 README 기술 스택 배지와 프로필 README 꾸미기

- 날짜: 2026-10-05
- 결과물: [README 기술 스택](../../README.md), [프로필 README](https://github.com/limbs-han/limbs-han)
- 커밋: `6eacf4f` docs: README 기술 스택을 배지 표로 바꾸기
- 커밋: `limbs-han/limbs-han` 저장소 `337b854` docs: 프로필 README를 요약표와 프로젝트 카드로 다시 꾸미기
- 커밋: `limbs-han/limbs-han` 저장소 `7738adb` docs: 빵긋에 Jira, namu-reco에 Spark, Airflow, Docker 배지 더하기

## 요청

> readme 에 사용한 기술스택 반영해서 배지 적어줘 databricks 이런거
>
> 그리고 꾸민것 처럼 limbs-han/README.md 도 꾸며줘 이건 인사팀 사람들이 보는거니깐 특히 더 신경써서 예쁘고 잘 읽히게끔

작업 012 단계 2에서 Play Console 앱 만들기를 안내한 뒤에 나온 요청이다.

## 과정

### 첫 결과
README 기술 스택 절을 분야, 기술 배지, 하는 일 세 칸 표로 바꿨다. 앱은 Flutter, Dart, Android, SQLite, 데이터 파이프라인은 Python, Pydantic, Databricks, Apache Spark, 자동화는 GitHub Actions, GitHub Pages다. 배지 로고가 shields에서 그려지는지 하나씩 확인했고 Iceberg와 AWS EC2는 로고가 없어 글자 배지로 뒀다.

프로필 README는 원래 문구를 바꾸지 않고 배치만 다시 짰다. 맨 위에 메일 배지와 학력, 교육, 자격증 세 칸 요약표를 두고, 다섯 칸 프로젝트 표를 프로젝트마다 기간과 역할 딱지, 한 일 목록, 기술 배지로 나눴다. 숫자는 굵게 했다. 원래 없던 체리컨슘 프로젝트를 이 저장소에서 확인한 사실로 더했다. GitHub와 같은 규칙으로 그리는 미리보기에서 "95.6%" 뒤 굵은 글씨가 풀려 HTML 굵기로 바꿨다.
- 선택: 체리컨슘 자리 → Hannun 다음 (추천)
- 선택: 스킬 → Databricks와 Flutter
- 선택: 올리기 → 둘 다 커밋하고 푸시

스킬의 데이터 처리 줄에 Databricks, 프로그래밍 줄에 Flutter와 Dart를 더해 올렸다.

### 수정 요청 1
> 그리고 limbs-han/readme 를 수정해준건 이쁘고 좋은데
> 빵긋의 뱃지엔 Jira 를 넣어줬으면 좋겠고
> namu-reco의 뱃지엔 spark 와 airflow, Docker를 넣어줘

반영: 빵긋 배지에 Jira, namu-reco 배지에 Spark, Airflow, Docker를 더해 올렸다.

## 최종 결과

체리컨슘 README에 기술 스택 배지 표가 있고, GitHub 프로필 맨 위에 요약표와 프로젝트 다섯 개가 보인다.
