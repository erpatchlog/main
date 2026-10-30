# collect.ps1 - 이터널 리턴 패치노트 수집 (GitHub Actions / 로컬 공용, GUI 없음)
# 결과: data\state.json, data\patches.js, data\gamedata.js, index.html (단독 파일)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$AppDir     = $PSScriptRoot
$DataDir    = Join-Path $AppDir 'data'
$StateFile  = Join-Path $DataDir 'state.json'
$PatchesJs  = Join-Path $DataDir 'patches.js'
$GameJs     = Join-Path $DataDir 'gamedata.js'
$Viewer     = Join-Path $AppDir 'viewer\index.html'
$Standalone = Join-Path $AppDir 'index.html'

$ListApi      = 'https://playeternalreturn.com/api/v1/posts/news?category=patchnote&page=1&hl=ko-KR'
$CharApi      = 'https://er.dakgg.io/api/v1/data/characters?hl=ko'
$ItemApi      = 'https://er.dakgg.io/api/v1/data/items?hl=ko'
$FirstRunCount = 6    # 데이터가 전혀 없을 때 가져올 최근 글 수
$KeepCount     = 20   # 보관할 최대 글 수

if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir | Out-Null }

function Get-Text([string]$url) {
    $r = Invoke-WebRequest $url -UseBasicParsing -UserAgent 'Mozilla/5.0' -Headers @{ 'Accept-Language' = 'ko-KR' } -TimeoutSec 30
    [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
}

function Write-Utf8([string]$path, [string]$text) {
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($false)))
}

$S = @{ gamedataDate = ''; patches = New-Object System.Collections.ArrayList }

if (Test-Path $StateFile) {
    $j = [IO.File]::ReadAllText($StateFile, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $S.gamedataDate = [string]$j.gamedataDate
    foreach ($p in @($j.patches)) {
        if ($p) {
            [void]$S.patches.Add(@{ id = [int]$p.id; title = [string]$p.title; date = [string]$p.date
                updated = [string]$p.updated; url = [string]$p.url; thumb = [string]$p.thumb; html = [string]$p.html })
        }
    }
}

$origGameDate = $S.gamedataDate

# 실험체 초상화 / 아이템 이미지 (하루 한 번 갱신)
$today = (Get-Date).ToString('yyyy-MM-dd')
if ($S.gamedataDate -ne $today -or -not (Test-Path $GameJs)) {
    $chars = (Get-Text $CharApi | ConvertFrom-Json).characters | ForEach-Object {
        @{ name = $_.name; img = 'https:' + $_.imageUrl }
    }
    $seen = @{}
    $items = foreach ($i in (Get-Text $ItemApi | ConvertFrom-Json).items) {
        if ($seen.ContainsKey($i.name)) { continue }
        $seen[$i.name] = $true
        @{ name = $i.name; img = $i.imageUrl; grade = $i.grade }
    }
    $gd = @{ characters = @($chars); items = @($items) }
    Write-Utf8 $GameJs ('window.ER_GAMEDATA = ' + (ConvertTo-Json -InputObject $gd -Depth 4 -Compress) + ';')
    $S.gamedataDate = $today
}

# 글 페이지에서 본문 HTML 만 잘라냄
function Get-ArticleHtml([string]$url) {
    $c = Get-Text ($url + '?hl=ko-KR')
    $s = $c.IndexOf('er-article-detail__content')
    if ($s -lt 0) { throw "본문을 찾을 수 없습니다: $url" }
    $s = $c.IndexOf('>', $s) + 1
    $e = $c.IndexOf('er-article-detail__recent', $s)
    if ($e -lt 0) { $e = $c.Length } else { $e = $c.LastIndexOf('<div', $e) }
    $c.Substring($s, $e - $s).Trim()
}

$articles = @((Get-Text $ListApi | ConvertFrom-Json).articles | Where-Object { $_.i18ns.ko_KR -and -not $_.i18ns.ko_KR.is_hidden })
if ($articles.Count -eq 0) { throw '패치노트 목록이 비어 있습니다.' }
$isFirst = $S.patches.Count -eq 0
$maxId = if ($isFirst) { 0 } else { ($S.patches | ForEach-Object { $_.id } | Measure-Object -Maximum).Maximum }
$targets = if ($isFirst) { $articles | Select-Object -First $FirstRunCount } else { $articles }

$changed = $false
$recheck = @($articles | Select-Object -First 3 | ForEach-Object { [int]$_.id })   # 최근 글은 수정됐는지 본문 비교
foreach ($a in $targets) {
    # updated_at 은 글을 수정하지 않아도 계속 바뀌는 값이라 변경 판단에 쓰지 않음
    $old = $S.patches | Where-Object { $_.id -eq [int]$a.id } | Select-Object -First 1
    if ($old -and $recheck -notcontains [int]$a.id) { continue }
    if (-not $old -and -not $isFirst -and [int]$a.id -lt $maxId) { continue }

    $html = Get-ArticleHtml $a.url
    $title = [string]$a.i18ns.ko_KR.title
    if ($old -and $old.html -eq $html -and $old.title -eq $title) { continue }

    Write-Host "수집: $title"
    $p = @{ id = [int]$a.id; title = $title; date = $a.created_at; updated = $a.updated_at
        url = $a.url; thumb = $a.thumbnail_url; html = $html }
    if ($old) { $S.patches.Remove($old) }
    [void]$S.patches.Add($p)
    $changed = $true
}

if ($changed) {
    $sorted = @($S.patches | Sort-Object { $_.id } -Descending | Select-Object -First $KeepCount)
    $S.patches = New-Object System.Collections.ArrayList
    foreach ($p in $sorted) { [void]$S.patches.Add($p) }
}

if ($changed -or $S.gamedataDate -ne $origGameDate -or -not (Test-Path $PatchesJs)) {
    $obj = @{ gamedataDate = $S.gamedataDate; patches = @($S.patches) }
    Write-Utf8 $StateFile (ConvertTo-Json -InputObject $obj -Depth 5 -Compress)
    Write-Utf8 $PatchesJs ('window.ER_PATCHES = ' + (ConvertTo-Json -InputObject @($S.patches) -Depth 5 -Compress) + ';')
}

# viewer\index.html 의 데이터 <script src> 두 줄을 내용으로 바꿔 넣은 단독 파일
$t  = [IO.File]::ReadAllText($Viewer, [Text.Encoding]::UTF8)
$gd = ([IO.File]::ReadAllText($GameJs, [Text.Encoding]::UTF8)).Replace('</', '<\/')
$pt = ([IO.File]::ReadAllText($PatchesJs, [Text.Encoding]::UTF8)).Replace('</', '<\/')
$a1 = '<script src="../data/gamedata.js"></script>'
$b1 = '<script src="../data/patches.js"></script>'
if ($t.IndexOf($a1) -lt 0 -or $t.IndexOf($b1) -lt 0) { throw 'viewer\index.html 에서 데이터 script 태그를 찾을 수 없습니다.' }
Write-Utf8 $Standalone ($t.Replace($a1, "<script>`n$gd`n</script>").Replace($b1, "<script>`n$pt`n</script>"))

Write-Host ("완료: 글 {0}개, 변경 {1}" -f $S.patches.Count, $changed)
