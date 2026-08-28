<#
.SYNOPSIS
    プロジェクトの初期ディレクトリ構造を作成し、Git リポジトリを初期化する。

.PARAMETER ProjectPath
    プロジェクトルートの絶対パス（例: D:\programming\repos\MyApp）

.PARAMETER Force
    既存ディレクトリが空でなくても対話的な確認をスキップして続行する。
    エージェントから実行する場合は常にこのオプションを指定する。

.PARAMETER WorkflowSource
    SDD ワークフローファイルのコピー元パス。
    指定した場合、doc/workflow.md としてプロジェクトに配置する。

.EXAMPLE
    .\init_project.ps1 -ProjectPath "D:\programming\repos\MyApp" -Force

.EXAMPLE
    .\init_project.ps1 -ProjectPath "D:\programming\repos\MyApp" -Force -WorkflowSource ".\references\sdd_workflow.md"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,

    [switch]$Force,

    [string]$WorkflowSource
)

$ErrorActionPreference = "Stop"

# プロジェクト名の取得
$appName = Split-Path -Leaf $ProjectPath

Write-Host "=== プロジェクト初期化: $appName ===" -ForegroundColor Cyan
Write-Host "パス: $ProjectPath"

# 既存ディレクトリのチェック
if (Test-Path $ProjectPath) {
    $items = Get-ChildItem -Path $ProjectPath -Force
    if ($items.Count -gt 0) {
        if (-not $Force) {
            Write-Warning "ディレクトリ '$ProjectPath' は既に存在し、空ではありません。"
            $response = Read-Host "続行しますか？ (y/N)"
            if ($response -ne "y" -and $response -ne "Y") {
                Write-Host "中止しました。" -ForegroundColor Yellow
                exit 1
            }
        } else {
            Write-Warning "ディレクトリは既に存在しますが、-Force が指定されたため続行します。"
        }
    }
}

# ディレクトリ構造の作成
$directories = @(
    "doc",
    "doc/mock",
    "doc/tasks",
    "doc/work",
    "src",
    "test"
)

foreach ($dir in $directories) {
    $fullPath = Join-Path $ProjectPath $dir
    if (-not (Test-Path $fullPath)) {
        New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
        Write-Host "  [作成] $dir/" -ForegroundColor Green
    } else {
        Write-Host "  [既存] $dir/" -ForegroundColor DarkGray
    }
}

# 初期空ファイルの作成（既存の場合はスキップ）
$files = @(
    "doc/spec.md",
    "doc/design_detail.md"
)

foreach ($file in $files) {
    $fullPath = Join-Path $ProjectPath $file
    if (-not (Test-Path $fullPath)) {
        $fileName = Split-Path -Leaf $file
        $header = "# " + ($fileName -replace '\.md$', '' -replace '_', ' ')
        Set-Content -Path $fullPath -Value $header -Encoding UTF8
        Write-Host "  [作成] $file" -ForegroundColor Green
    } else {
        Write-Host "  [既存] $file" -ForegroundColor DarkGray
    }
}

# SDD ワークフローファイルの配置
if ($WorkflowSource) {
    $workflowDest = Join-Path $ProjectPath "doc/workflow.md"
    if (-not (Test-Path $workflowDest)) {
        if (Test-Path $WorkflowSource) {
            Copy-Item -Path $WorkflowSource -Destination $workflowDest
            Write-Host "  [作成] doc/workflow.md (コピー元: $WorkflowSource)" -ForegroundColor Green
        } else {
            Write-Warning "ワークフローファイルが見つかりません: $WorkflowSource"
        }
    } else {
        Write-Host "  [既存] doc/workflow.md" -ForegroundColor DarkGray
    }
}

# Git 初期化
$gitDir = Join-Path $ProjectPath ".git"
if (-not (Test-Path $gitDir)) {
    Write-Host ""
    Write-Host "Git リポジトリを初期化しています..." -ForegroundColor Cyan
    Push-Location $ProjectPath
    try {
        git init
        git checkout -b alpha
        Write-Host "  ブランチ 'alpha' を作成しました。" -ForegroundColor Green
    } finally {
        Pop-Location
    }
} else {
    Write-Host ""
    Write-Host "  [既存] Git リポジトリは初期化済みです。" -ForegroundColor DarkGray
    # alpha ブランチが存在しなければ作成
    Push-Location $ProjectPath
    try {
        $branches = git branch --list "alpha" 2>$null
        if (-not $branches) {
            git checkout -b alpha
            Write-Host "  ブランチ 'alpha' を作成しました。" -ForegroundColor Green
        } else {
            git checkout alpha
            Write-Host "  ブランチ 'alpha' に切り替えました。" -ForegroundColor DarkGray
        }
    } finally {
        Pop-Location
    }
}

Write-Host ""
Write-Host "=== 初期化完了 ===" -ForegroundColor Cyan

# 検証: ディレクトリ構造の表示
Write-Host ""
Write-Host "ディレクトリ構造:" -ForegroundColor Cyan
Push-Location $ProjectPath
try {
    Get-ChildItem -Recurse -Depth 2 -Force |
        Where-Object { $_.Name -ne ".git" -and $_.FullName -notlike "*\.git\*" } |
        ForEach-Object {
            $indent = "  " * ($_.FullName.Replace($ProjectPath, "").Split([IO.Path]::DirectorySeparatorChar).Length - 1)
            $icon = if ($_.PSIsContainer) { "[DIR] " } else { "[FILE]" }
            Write-Host "  $indent$icon $($_.Name)"
        }
} finally {
    Pop-Location
}
