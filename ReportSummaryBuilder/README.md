# Test Report Summary Builder

Vector CANoe/vTESTstudio HTML 리포트 여러 개를 한 번에 읽어 통합 서머리, 위치별 상세 HTML, ZIP으로 만드는 Windows 앱입니다.

## 사용 방법

1. `ReportSummaryBuilder-Setup.exe`를 실행해 설치합니다.
2. **원본 HTML 폴더**에서 DRV/AST/RL/RR 등 원본 리포트가 있는 폴더를 선택합니다.
3. **생성 결과 폴더**를 선택하고 **서머리 · ZIP 생성**을 누릅니다.
4. 생성된 `*_Combined_Test_Report.html` 또는 `*_Test_Report.zip`을 확인합니다.

입력 개수에는 제한을 두지 않습니다. 단, `Var_Project` 값이 서로 다르면 **동일 차종의 리포트가 아닙니다.** 알림 후 생성하지 않습니다. Position이 중복된 경우에는 별도 중복 오류로 중단합니다.

## 배포 파일

- `release/installer/ReportSummaryBuilder-Setup.exe`: 사용자별 설치, 바탕 화면/시작 메뉴 바로가기, Windows 앱 제거 지원
- `release/portable/ReportSummaryBuilder.exe`: 설치 없이 실행하는 독립 실행 파일

내부 배포 빌드는 코드 서명이 없으므로 다른 PC에서 Windows SmartScreen 경고가 표시될 수 있습니다. 신뢰된 사내 코드 서명 인증서가 있다면 배포 전에 서명하는 것을 권장합니다.

## 개발 및 빌드

```powershell
dotnet test .\ReportSummaryBuilder.slnx -m:1 -nr:false
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-release.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\release-smoke.ps1
```

원본 HTML은 읽기만 하며 수정하지 않습니다. 기존 출력이 있으면 `.bak_yyyyMMdd_HHmmss` 형식으로 백업한 뒤 새 결과를 게시합니다.
