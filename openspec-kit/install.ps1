<#
.SYNOPSIS
    openspec-kit（レビュー機構・運用ルール・テンプレート）を対象プロジェクトへ導入／再同期する。

.DESCRIPTION
    対象プロジェクトの openspec/ に以下を導入する。
      1. openspec/templates/   : レビュー記録・チェックリスト・handover・PR本文テンプレート
      2. openspec/config.yaml  : 汎用設定（既存がある場合は config.kit.yaml として横に出力）
      3. AGENTS.md             : OpenSpec 運用ルールをマーカー区間に挿入（再実行時は区間を置換）。
                                 新規作成時はプロジェクト固有ルールの雛形（AGENTS.project.md）を区間外に出力
      4. .gitignore            : テストエビデンス出力先を追記（未登録の場合のみ）
      5. CLAUDE.md / GEMINI.md : AGENTS.md を正本としてインポートする入口ファイル（未作成の場合のみ）

    事前に対象プロジェクトで `openspec init` を実行しておくこと。

.PARAMETER TargetPath
    導入先プロジェクトのルートディレクトリ。

.PARAMETER BaseBranch
    トピックブランチの分岐元／PR のマージ先ブランチ名。既定: develop

.PARAMETER EvidenceDir
    テストエビデンス・カバレッジレポートの出力先（Git 管理外）。既定: test/TestResults/

.PARAMETER Force
    既存のテンプレートファイルを上書きする（キット更新後の再同期に使用）。

.PARAMETER OverwriteConfig
    既存の openspec/config.yaml をバックアップ（config.yaml.bak-<timestamp>）した上で上書きする。

.PARAMETER SkipConfig
    openspec/config.yaml の処理を行わない（導入済みプロジェクトでテンプレートと AGENTS.md だけを再同期する場合）。

.EXAMPLE
    ./install.ps1 -TargetPath D:\repos\MyApp -BaseBranch develop -WhatIf

.EXAMPLE
    ./install.ps1 -TargetPath D:\repos\MyApp -BaseBranch main -EvidenceDir test-results/ -Force
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$TargetPath,

    [string]$BaseBranch = 'develop',

    [string]$EvidenceDir = 'test/TestResults/',

    [switch]$Force,

    [switch]$OverwriteConfig,

    [switch]$SkipConfig
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$MarkerBegin = '<!-- openspec-kit:begin (install.ps1 により管理。手動編集は再同期で上書きされます) -->'
$MarkerEnd = '<!-- openspec-kit:end -->'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Read-Text([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Write-Text([string]$Path, [string]$Content) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

function Expand-Placeholder([string]$Text) {
    return $Text.Replace('{{BASE_BRANCH}}', $BaseBranch).Replace('{{EVIDENCE_DIR}}', $EvidenceDir)
}

# --- 前提チェック -------------------------------------------------------------
$kitRoot = $PSScriptRoot
$target = (Resolve-Path -LiteralPath $TargetPath).Path
$openspecDir = Join-Path $target 'openspec'

if (-not (Test-Path -LiteralPath $openspecDir -PathType Container)) {
    throw "openspec/ が見つかりません: $openspecDir`n先に対象プロジェクトで 'openspec init' を実行してください。"
}

Write-Host "openspec-kit を導入します" -ForegroundColor Cyan
Write-Host "  Target     : $target"
Write-Host "  BaseBranch : $BaseBranch"
Write-Host "  EvidenceDir: $EvidenceDir"

# --- 1. テンプレート ----------------------------------------------------------
$templatesSrc = Join-Path $kitRoot 'templates'
$templatesDst = Join-Path $openspecDir 'templates'

foreach ($file in Get-ChildItem -LiteralPath $templatesSrc -File) {
    $dst = Join-Path $templatesDst $file.Name
    if ((Test-Path -LiteralPath $dst) -and -not $Force) {
        Write-Host "  [skip] templates/$($file.Name)（既存。上書きは -Force）" -ForegroundColor DarkYellow
        continue
    }
    if ($PSCmdlet.ShouldProcess($dst, 'テンプレートを配置')) {
        Write-Text $dst (Expand-Placeholder (Read-Text $file.FullName))
        Write-Host "  [ok]   templates/$($file.Name)" -ForegroundColor Green
    }
}

# --- 2. config.yaml -----------------------------------------------------------
$configSrc = Join-Path $kitRoot 'config.yaml'
$configDst = Join-Path $openspecDir 'config.yaml'
$configContent = Expand-Placeholder (Read-Text $configSrc)

if ($SkipConfig) {
    Write-Host "  [skip] openspec/config.yaml（-SkipConfig）" -ForegroundColor DarkYellow
}
elseif ((Test-Path -LiteralPath $configDst) -and -not $OverwriteConfig) {
    $sideBySide = Join-Path $openspecDir 'config.kit.yaml'
    if ($PSCmdlet.ShouldProcess($sideBySide, '既存 config.yaml と並べて出力')) {
        Write-Text $sideBySide $configContent
        Write-Host "  [warn] openspec/config.yaml は既存のため openspec/config.kit.yaml に出力しました。手動でマージ後、config.kit.yaml を削除してください（上書きは -OverwriteConfig）" -ForegroundColor Yellow
    }
}
else {
    if (Test-Path -LiteralPath $configDst) {
        $backup = "$configDst.bak-$(Get-Date -Format 'yyyyMMddHHmmss')"
        if ($PSCmdlet.ShouldProcess($backup, '既存 config.yaml をバックアップ')) {
            Copy-Item -LiteralPath $configDst -Destination $backup
            Write-Host "  [ok]   config.yaml をバックアップ: $(Split-Path -Leaf $backup)" -ForegroundColor Green
        }
    }
    if ($PSCmdlet.ShouldProcess($configDst, 'config.yaml を配置')) {
        Write-Text $configDst $configContent
        Write-Host "  [ok]   openspec/config.yaml（context の技術スタック等の TODO を記入してください）" -ForegroundColor Green
    }
}

# --- 3. AGENTS.md -------------------------------------------------------------
$snippet = Expand-Placeholder (Read-Text (Join-Path $kitRoot 'AGENTS.openspec.md'))
$block = "$MarkerBegin`n`n$($snippet.TrimEnd())`n`n$MarkerEnd"
$agentsPath = Join-Path $target 'AGENTS.md'

if (Test-Path -LiteralPath $agentsPath) {
    $agents = Read-Text $agentsPath
    $begin = $agents.IndexOf('<!-- openspec-kit:begin')
    $end = $agents.IndexOf($MarkerEnd)
    if ($begin -ge 0 -and $end -gt $begin) {
        $newAgents = $agents.Substring(0, $begin) + $block + $agents.Substring($end + $MarkerEnd.Length)
        $action = 'マーカー区間を置換'
    }
    else {
        $newAgents = $agents.TrimEnd() + "`n`n---`n`n" + $block + "`n"
        $action = '末尾に追記'
    }
}
else {
    # 新規作成時はプロジェクト固有部分の雛形（管理区間外）＋管理区間を出力する
    $skeleton = Expand-Placeholder (Read-Text (Join-Path $kitRoot 'AGENTS.project.md'))
    $newAgents = $skeleton.TrimEnd() + "`n`n---`n`n" + $block + "`n"
    $action = '新規作成'
}

if ($PSCmdlet.ShouldProcess($agentsPath, "AGENTS.md: $action")) {
    Write-Text $agentsPath $newAgents
    Write-Host "  [ok]   AGENTS.md（$action。管理区間外の TODO（概要・フォーマットコマンド等）を記入してください）" -ForegroundColor Green
}

# --- 4. .gitignore ------------------------------------------------------------
$gitignorePath = Join-Path $target '.gitignore'
$ignoreLine = $EvidenceDir.Replace('\', '/')
$existingIgnore = if (Test-Path -LiteralPath $gitignorePath) { Read-Text $gitignorePath } else { '' }
$alreadyIgnored = ($existingIgnore -split "`r?`n") -contains $ignoreLine

if (-not $alreadyIgnored -and $PSCmdlet.ShouldProcess($gitignorePath, "$ignoreLine を追記")) {
    $prefix = if (-not $existingIgnore) { '' } elseif ($existingIgnore.EndsWith("`n")) { "`n" } else { "`n`n" }
    Write-Text $gitignorePath ($existingIgnore + $prefix + "# Test evidence & coverage (openspec-kit)`n$ignoreLine`n")
    Write-Host "  [ok]   .gitignore に $ignoreLine を追記" -ForegroundColor Green
}

# --- 5. エージェント別エントリファイル（AGENTS.md を正本としてインポート） -------
foreach ($entry in @('CLAUDE.md', 'GEMINI.md')) {
    $entryPath = Join-Path $target $entry
    if (Test-Path -LiteralPath $entryPath) {
        if (-not ((Read-Text $entryPath) -match '@AGENTS\.md')) {
            Write-Host "  [warn] $entry は既存で @AGENTS.md を参照していません。必要に応じて '@AGENTS.md' を追記してください" -ForegroundColor Yellow
        }
        continue
    }
    if ($PSCmdlet.ShouldProcess($entryPath, '@AGENTS.md を参照するエントリファイルを作成')) {
        Write-Text $entryPath "@AGENTS.md`n"
        Write-Host "  [ok]   $entry（@AGENTS.md）" -ForegroundColor Green
    }
}

Write-Host "完了。'openspec instructions proposal --change <name> --json' 等で context / rules が反映されることを確認してください。" -ForegroundColor Cyan
