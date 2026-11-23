# TypeAlong

## 개요·기술 스택
- 유튜브 영상을 보며 영어 스크립트를 따라 치는 타자연습 앱(웹 프로토타입: `/Volumes/Data/Project/Typing/scripttype`)
- SwiftUI, iOS 17+, iPhone 세로 전용, Bundle ID `com.addvalue.typealong`
- 상태: `Store`(ObservableObject), 저장: UserDefaults(JSON), 외부 패키지 없음
- 영상: WKWebView + YouTube IFrame API (`baseURL` 필수, 없으면 오류 153)
- Xcode 폴더 동기화 그룹: `TypeAlong/` 안에 파일을 만들면 자동 포함(pbxproj 편집 불필요)

## 폴더 구조
- `TypeAlong/Models.swift` 모델, 색상, 붙여넣기 텍스트 파서(`ScriptParser`)
- `TypeAlong/Store.swift` 입력 판정, 통계, 스크립트·진행 저장
- `TypeAlong/Library.swift` 첫 화면(저장한 영상 목록·썸네일 캐시·네트워크 감시), `ContentView.swift` 연습 화면(영상·통계·버튼), `ScriptView.swift` 스크립트
- `TypeAlong/TypingInput.swift` 숨은 UITextField로 키 입력 수신
- `TypeAlong/AddScriptView.swift` 주소·스크립트 붙여넣기 시트
- `TypeAlong/VocabView.swift` 단어장 화면(길게 눌러 저장한 단어, 한글 뜻은 기기 내 번역)
- `TypeAlong/SettingsSheet.swift` 환경 설정 팝업(한글·대소문자·글자 크기·글꼴), `GlassStyle.swift` Liquid Glass·스와이프 뒤로가기
- `ShareExtension/` 유튜브 공유 시트용 확장(주소를 `typealong://add?url=`로 앱에 전달), 루트의 `*-Info.plist` 2개


## 규칙
- 영어는 키보드로 칠 수 있는 ASCII만 허용(`ScriptParser.clean`)
- 다크 테마 고정, 한글 번역은 영어와 같은 크기 이상

## 명령어·현재 상태
- 스킴 `TypeAlong`, 프로젝트 `TypeAlong.xcodeproj`
- 이 컴퓨터는 시뮬레이터 불가 → 컴파일 확인은 `generic/platform=iOS Simulator` 빌드, 실행은 실제 아이폰에 설치
- 현재: 1.0 5.2.3 거절 후 재심사 준비. 빌드 5 업로드 완료(처리 중; 영화·빌보드 목록·현대 인물 명언 삭제, 명언·연설은 고전·퍼블릭 도메인만). 스크린샷 5장·심사 노트 ASC 저장 완료. 남은 일: 빌드 5 선택 후 재심사 제출(사용자 확인), 심사 노트의 첨부 녹화(구버전) 교체. 연령 등급 4+
