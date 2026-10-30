# 이터널 리턴 패치노트

공식 홈페이지의 패치노트를 30분마다 수집해 GitHub Pages로 보여줍니다.

- `collect.ps1` : 패치노트/실험체/아이템 데이터 수집 후 `index.html` 생성
- `.github/workflows/update.yml` : 30분마다 위 스크립트를 실행하고 변경분을 커밋 + 사이트 배포
- `viewer/index.html` : 화면 템플릿 (수정하면 push 시 자동 재배포)

## 설정 (한 번만)
1. 이 폴더 내용을 GitHub 저장소(main 브랜치)에 올린다.
2. 저장소 **Settings → Pages → Source** 를 **GitHub Actions** 로 바꾼다.
3. **Actions → Update patch notes → Run workflow** 로 첫 배포를 실행한다.
4. 사이트 주소: `https://<계정>.github.io/<저장소>/`

출처: 이터널 리턴 공식 홈페이지, DAK.GG
