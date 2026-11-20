<#
.SYNOPSIS
    openspec-kit（サブエージェント6ロール・5エージェント共通 Skills・TDD/C0-C2基準・フェーズゲート・テンプレート）を対象プロジェクトへ導入／再同期する。

.DESCRIPTION
    対象プロジェクトの openspec/ および対象エージェントの skills/ に以下を導入する。
      1. openspec/templates/        : テスト計画・レビュー記録・チェックリスト・handover・PR本文テンプレート
      2. openspec/agents/           : 6ロールのサブエージェント定義（.claude/ がある場合は .claude/agents/ にも配置）
      3. openspec/scripts/          : フェーズゲート機械検証スクリプト（verify-gate.ps1 / verify-gate.sh）
      4. <agent>/skills/sdd-*       : 5エージェント共通 SDD スキル（sdd-propose / sdd-apply / sdd-archive）の再帰展開
      5. .agents/workflows/sdd-*.md : 旧形式ワークフローの後段 .bak 退避（.agents/skills 配置成功時のみ）
      6. openspec/config.yaml       : 汎用設定（既存がある場合は config.kit.yaml として横に出力）
      7. AGENTS.md                  : OpenSpec 運用ルールをマーカー区間にアトミック挿入（24,000B 超過警告付き）
      8. .gitignore                 : テストエビデンス出力先を追記（未登録の場合のみ）
      9. CLAUDE.md / GEMINI.md      : AGENTS.md を正本としてインポートする入口ファイル（未作成の場合のみ）

    事前に対象プロジェクトで `openspec init` を実行しておくこと。

.PARAMETER TargetPath
    導入先プロジェクトのルートディレクトリ。

.PARAMETER BaseBranch
    トピックブランチの分岐元／PR のマージ先ブランチ名。既定: develop

.PARAMETER EvidenceDir
    テストエビデンス・カバレッジレポートの出力先（Git 管理外）。既定: test/TestResults/

.PARAMETER AgentTargets
    スキル展開先エージェント。auto（既定: .agents/skills 必須＋既存の .claude/.github/.opencode/.hermes を自動検出）、
    all（5エージェントすべて）、または antigravity,claude,copilot,opencode,hermes のカンマ区切り。

.PARAMETER Force
    既存のテンプレート・エージェント・スクリプト・スキルファイルを上書きする（キット更新後の再同期に使用）。

.PARAMETER OverwriteConfig
    既存の openspec/config.yaml をバックアップ（config.yaml.bak-<timestamp>）した上で上書きする。

.PARAMETER SkipConfig
    openspec/config.yaml の処理を行わない（導入済みプロジェクトでテンプレートや AGENTS.md だけを再同期する場合）。

.EXAMPLE
    ./install.ps1 -TargetPath D:\repos\MyApp -BaseBranch develop -WhatIf

.EXAMPLE
    ./install.ps1 -TargetPath D:\repos\MyApp -BaseBranch main -EvidenceDir test-results/ -AgentTargets all -Force -SkipConfig
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$TargetPath,

    [string]$BaseBranch = 'develop',

    [string]$EvidenceDir = 'test/TestResults/',

    [string]$AgentTargets = 'auto',

    [switch]$Force,

    [switch]$OverwriteConfig,

    [switch]$SkipConfig
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$MarkerBeginPrefix = '<!-- openspec-kit:begin'
$MarkerBegin = '<!-- openspec-kit:begin (install.ps1 により管理。手動編集は再同期で上書きされます) -->'
$MarkerEnd = '<!-- openspec-kit:end -->'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Utf8Bom = New-Object System.Text.UTF8Encoding($true)

$AgentRootMap = [ordered]@{
    antigravity = '.agents'
    claude      = '.claude'
    copilot     = '.github'
    opencode    = '.opencode'
    hermes      = '.hermes'
}

function Read-Text([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Write-Text([string]$Path, [string]$Content, [switch]$WithBom) {
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $enc = if ($WithBom) { $Utf8Bom } else { $Utf8NoBom }
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}

function ConvertTo-Lf([string]$Text) {
    return $Text.Replace("`r`n", "`n").Replace("`r", "")
}

function Format-LfTrailingNewline([string]$Text) {
    return (ConvertTo-Lf $Text).TrimEnd("`n") + "`n"
}

function Assert-NoControlLineBreaks([string]$Name, [string]$Value) {
    if ($Value -match "[\r\n\0]") {
        throw "Invalid -${Name}: 改行（CR/LF）または NUL 文字を含めることはできません。"
    }
}

function Expand-Placeholder([string]$Text, [switch]$EscapeSingleQuote) {
    $bVal = if ($EscapeSingleQuote) { $BaseBranch.Replace("'", "''") } else { $BaseBranch }
    $eVal = if ($EscapeSingleQuote) { $EvidenceDir.Replace("'", "''") } else { $EvidenceDir }
    return [regex]::Replace($Text, '\{\{(BASE_BRANCH|EVIDENCE_DIR)\}\}', {
            param($m)
            if ($m.Groups[1].Value -eq 'BASE_BRANCH') { return $bVal }
            return $eVal
        })
}

function Assert-PathNotLeaf([string]$PathToCheck) {
    if ((Test-Path -LiteralPath $PathToCheck) -and (Test-Path -LiteralPath $PathToCheck -PathType Leaf)) {
        throw "展開先パス '$PathToCheck' がディレクトリではなく通常ファイルとして存在するため導入できません。"
    }
}

function Assert-PathNotContainer([string]$PathToCheck) {
    if ((Test-Path -LiteralPath $PathToCheck) -and (Test-Path -LiteralPath $PathToCheck -PathType Container)) {
        throw "展開先ファイルパス '$PathToCheck' に既にディレクトリが存在するため導入できません。"
    }
}

function Assert-DirectoryTreeDestinations([string]$SrcDir, [string]$DstDir, [switch]$Recurse) {
    Assert-PathNotLeaf $DstDir
    if (-not (Test-Path -LiteralPath $SrcDir -PathType Container)) {
        return
    }
    $srcRoot = (Resolve-Path -LiteralPath $SrcDir).Path.TrimEnd('\', '/')
    if ($Recurse) {
        foreach ($subDir in (Get-ChildItem -LiteralPath $srcRoot -Directory -Recurse)) {
            $rel = $subDir.FullName.Substring($srcRoot.Length).TrimStart('\', '/')
            Assert-PathNotLeaf (Join-Path $DstDir $rel)
        }
        $files = Get-ChildItem -LiteralPath $srcRoot -File -Recurse
    }
    else {
        $files = Get-ChildItem -LiteralPath $srcRoot -File
    }
    foreach ($file in $files) {
        $rel = $file.FullName.Substring($srcRoot.Length).TrimStart('\', '/')
        Assert-PathNotContainer (Join-Path $DstDir $rel)
    }
}

function Resolve-BackupPath([string]$BasePrefix, [string]$InitialCandidate) {
    if (-not (Test-Path -LiteralPath $InitialCandidate)) {
        return $InitialCandidate
    }
    $ts = Get-Date -Format 'yyyyMMddHHmmss'
    $counter = 1
    do {
        $candidate = "$BasePrefix-$ts-$counter"
        $counter++
    } while (Test-Path -LiteralPath $candidate)
    return $candidate
}

function Resolve-AgentTargetList([string]$RawTargets, [string]$ProjectRoot) {
    if ([string]::IsNullOrWhiteSpace($RawTargets)) {
        throw "Invalid -AgentTargets: 空文字または空白のみは指定できません。許容値: auto, all, または antigravity,claude,copilot,opencode,hermes のカンマ区切り。"
    }
    $trimmed = $RawTargets.Trim()
    $tokens = $trimmed -split ','
    $normalized = New-Object System.Collections.Generic.List[string]

    foreach ($rawToken in $tokens) {
        $t = $rawToken.Trim().ToLowerInvariant()
        if ([string]::IsNullOrEmpty($t)) {
            throw "Invalid -AgentTargets '$RawTargets': 空のトークンが含まれています。"
        }
        if ($t -notin @('auto', 'all', 'antigravity', 'claude', 'copilot', 'opencode', 'hermes')) {
            throw "Invalid -AgentTargets '$RawTargets': 未知のターゲット '$t' です。許容値: auto, all, antigravity, claude, copilot, opencode, hermes。"
        }
        if (($t -eq 'auto' -or $t -eq 'all') -and $tokens.Count -gt 1) {
            throw "Invalid -AgentTargets '$RawTargets': '$t' は他のターゲットと同時に指定できません。"
        }
        if (-not $normalized.Contains($t)) {
            $normalized.Add($t)
        }
    }

    $resolved = New-Object System.Collections.Generic.List[string]
    $isZeroStateAuto = $false

    if ($normalized.Count -eq 1 -and $normalized[0] -eq 'auto') {
        $resolved.Add('antigravity')
        $detectedOthers = 0
        foreach ($agentName in @('claude', 'copilot', 'opencode', 'hermes')) {
            $rootRel = $AgentRootMap[$agentName]
            $rootFull = Join-Path $ProjectRoot $rootRel
            if (Test-Path -LiteralPath $rootFull) {
                Assert-PathNotLeaf $rootFull
                $resolved.Add($agentName)
                $detectedOthers++
            }
        }
        if ($detectedOthers -eq 0) {
            $isZeroStateAuto = $true
        }
    }
    elseif ($normalized.Count -eq 1 -and $normalized[0] -eq 'all') {
        foreach ($agentName in $AgentRootMap.Keys) {
            $resolved.Add($agentName)
        }
    }
    else {
        foreach ($agentName in $normalized) {
            $resolved.Add($agentName)
        }
    }

    return [pscustomobject]@{
        Targets         = @($resolved)
        IsZeroStateAuto = $isZeroStateAuto
    }
}

$script:TotalSkillsDeployed = 0
$script:TotalSkillsSkipped = 0

function Copy-KitDirectory([string]$SrcDir, [string]$DstDir, [string]$Label, [switch]$Ps1WithBom, [switch]$Recurse, [switch]$TrackSkillSkip) {
    if (-not (Test-Path -LiteralPath $SrcDir -PathType Container)) {
        return
    }
    $srcRoot = (Resolve-Path -LiteralPath $SrcDir).Path.TrimEnd('\', '/')
    $files = if ($Recurse) {
        Get-ChildItem -LiteralPath $srcRoot -File -Recurse
    }
    else {
        Get-ChildItem -LiteralPath $srcRoot -File
    }

    foreach ($file in $files) {
        $rel = $file.FullName.Substring($srcRoot.Length).TrimStart('\', '/')
        $relDisplay = $rel.Replace('\', '/')
        $dst = Join-Path $DstDir $rel
        if ((Test-Path -LiteralPath $dst -PathType Leaf) -and -not $Force) {
            if ($TrackSkillSkip) {
                $script:TotalSkillsSkipped++
            }
            Write-Host "  [skip] $Label/$relDisplay（既存。上書きは -Force）" -ForegroundColor DarkYellow
            continue
        }
        if ($PSCmdlet.ShouldProcess($dst, "$Label を配置")) {
            $isPs1 = ($file.Extension -eq '.ps1')
            $useBom = $Ps1WithBom -and $isPs1
            $text = Format-LfTrailingNewline (Expand-Placeholder (Read-Text $file.FullName) -EscapeSingleQuote:$isPs1)
            Write-Text $dst $text -WithBom:$useBom
            if ($TrackSkillSkip) {
                $script:TotalSkillsDeployed++
            }
            Write-Host "  [ok]   $Label/$relDisplay" -ForegroundColor Green
        }
    }
}

# --- 0. 前提・事前バリデーション（書き込み前にすべて検証） --------------------
Assert-NoControlLineBreaks 'BaseBranch' $BaseBranch
Assert-NoControlLineBreaks 'EvidenceDir' $EvidenceDir
Assert-NoControlLineBreaks 'AgentTargets' $AgentTargets

$kitRoot = $PSScriptRoot
if (-not (Test-Path -LiteralPath $TargetPath -PathType Container)) {
    throw "TargetPath が存在しません: $TargetPath"
}
$target = (Resolve-Path -LiteralPath $TargetPath).Path
$openspecDir = Join-Path $target 'openspec'

if (-not (Test-Path -LiteralPath $openspecDir -PathType Container)) {
    throw "openspec/ が見つかりません: $openspecDir`n先に対象プロジェクトで 'openspec init' を実行してください。"
}

$targetResolution = Resolve-AgentTargetList -RawTargets $AgentTargets -ProjectRoot $target
$resolvedTargets = $targetResolution.Targets
$isZeroStateAuto = $targetResolution.IsZeroStateAuto

# 展開先パス種別衝突（ディレクトリ位置の通常ファイル／ファイル位置のディレクトリ）を事前検証
Assert-DirectoryTreeDestinations (Join-Path $kitRoot 'templates') (Join-Path $openspecDir 'templates')
Assert-DirectoryTreeDestinations (Join-Path $kitRoot 'agents') (Join-Path $openspecDir 'agents')
Assert-DirectoryTreeDestinations (Join-Path $kitRoot 'scripts') (Join-Path $openspecDir 'scripts')

$claudeRoot = Join-Path $target '.claude'
if (Test-Path -LiteralPath $claudeRoot) {
    Assert-PathNotLeaf $claudeRoot
    Assert-DirectoryTreeDestinations (Join-Path $kitRoot 'agents') (Join-Path $claudeRoot 'agents')
}

foreach ($agentName in $resolvedTargets) {
    $agentRootRel = $AgentRootMap[$agentName]
    $agentRootFull = Join-Path $target $agentRootRel
    Assert-PathNotLeaf $agentRootFull
    Assert-DirectoryTreeDestinations (Join-Path $kitRoot 'skills') (Join-Path $agentRootFull 'skills') -Recurse
}

$configDst = Join-Path $openspecDir 'config.yaml'
if (-not $SkipConfig) {
    Assert-PathNotContainer $configDst
    Assert-PathNotContainer (Join-Path $openspecDir 'config.kit.yaml')
}

$agentsPath = Join-Path $target 'AGENTS.md'
Assert-PathNotContainer $agentsPath
$gitignorePath = Join-Path $target '.gitignore'
Assert-PathNotContainer $gitignorePath
Assert-PathNotContainer (Join-Path $target 'CLAUDE.md')
Assert-PathNotContainer (Join-Path $target 'GEMINI.md')

# AGENTS.md の1回読み取り＆マーカー多重/順序逆転検査（書き込み前に検証）
$existingAgentsLf = $null
$agentsMarkerStatus = 'NEW'
$existingBeginIdx = -1
$existingEndIdx = -1
if (Test-Path -LiteralPath $agentsPath -PathType Leaf) {
    $existingAgentsLf = ConvertTo-Lf (Read-Text $agentsPath)
    $beginMatches = [regex]::Matches($existingAgentsLf, [regex]::Escape($MarkerBeginPrefix))
    $endMatches = [regex]::Matches($existingAgentsLf, [regex]::Escape($MarkerEnd))
    $bCount = $beginMatches.Count
    $eCount = $endMatches.Count
    if ($bCount -eq 0 -and $eCount -eq 0) {
        $agentsMarkerStatus = 'NONE'
    }
    elseif ($bCount -eq 1 -and $eCount -eq 1 -and $beginMatches[0].Index -lt $endMatches[0].Index) {
        $agentsMarkerStatus = 'VALID'
        $existingBeginIdx = $beginMatches[0].Index
        $existingEndIdx = $endMatches[0].Index
    }
    else {
        throw "AGENTS.md の管理マーカーが破損しています（片側マーカーのみ残存、多重出現、または順序不正）: $agentsPath`n手動で '<!-- openspec-kit:begin ... -->' と '$MarkerEnd' のペアを修復または削除してから再実行してください。"
    }
}

Write-Host "openspec-kit を導入します" -ForegroundColor Cyan
Write-Host "  Target       : $target"
Write-Host "  BaseBranch   : $BaseBranch"
Write-Host "  EvidenceDir  : $EvidenceDir"
Write-Host "  AgentTargets : $($resolvedTargets -join ', ') (指定: $AgentTargets)"

# --- 1. テンプレート ----------------------------------------------------------
Copy-KitDirectory (Join-Path $kitRoot 'templates') (Join-Path $openspecDir 'templates') 'templates'

# --- 2. サブエージェント定義 --------------------------------------------------
Copy-KitDirectory (Join-Path $kitRoot 'agents') (Join-Path $openspecDir 'agents') 'agents'
if (Test-Path -LiteralPath $claudeRoot -PathType Container) {
    Copy-KitDirectory (Join-Path $kitRoot 'agents') (Join-Path $claudeRoot 'agents') '.claude/agents'
}

# --- 3. フェーズゲート検証スクリプト ------------------------------------------
Copy-KitDirectory (Join-Path $kitRoot 'scripts') (Join-Path $openspecDir 'scripts') 'scripts' -Ps1WithBom

# --- 4. SDD スキル多面展開 ----------------------------------------------------
$deployedSkillPaths = New-Object System.Collections.Generic.List[string]
foreach ($agentName in $resolvedTargets) {
    $agentRootRel = $AgentRootMap[$agentName]
    $skillsRel = "$agentRootRel/skills"
    $skillsDst = Join-Path (Join-Path $target $agentRootRel) 'skills'
    Copy-KitDirectory (Join-Path $kitRoot 'skills') $skillsDst $skillsRel -Recurse -TrackSkillSkip
    $deployedSkillPaths.Add($skillsRel)
}

# --- 5. レガシーワークフロー（.agents/workflows/sdd-*.md）の後段安全退避 ------
$migratedBackups = New-Object System.Collections.Generic.List[string]
if ($resolvedTargets -contains 'antigravity') {
    $legacyWfDir = Join-Path $target '.agents/workflows'
    if (Test-Path -LiteralPath $legacyWfDir -PathType Container) {
        foreach ($wfName in @('sdd-propose.md', 'sdd-apply.md', 'sdd-archive.md')) {
            $wfPath = Join-Path $legacyWfDir $wfName
            if (-not (Test-Path -LiteralPath $wfPath -PathType Leaf)) {
                continue
            }
            $candidateBak = Resolve-BackupPath -BasePrefix "$wfPath.bak" -InitialCandidate "$wfPath.bak"
            $bakLeaf = Split-Path -Leaf $candidateBak
            if ($PSCmdlet.ShouldProcess($wfPath, "旧 SDD ワークフローを $bakLeaf へ退避")) {
                try {
                    Move-Item -LiteralPath $wfPath -Destination $candidateBak -Force -ErrorAction Stop
                    $migratedBackups.Add(".agents/workflows/$bakLeaf")
                    Write-Host "  [bak]  .agents/workflows/$wfName -> .agents/workflows/$bakLeaf" -ForegroundColor Yellow
                }
                catch {
                    throw "旧ワークフロー '$wfPath' を '$candidateBak' へ退避（リネーム）できませんでした: $($_.Exception.Message)`nファイルを開いているエディタやプロセスを閉じるか、手動でリネーム・削除してから再実行してください。"
                }
            }
        }
    }
}

# --- 6. config.yaml -----------------------------------------------------------
if ($SkipConfig) {
    Write-Host "  [skip] openspec/config.yaml（-SkipConfig）" -ForegroundColor DarkYellow
}
else {
    $configSrc = Join-Path $kitRoot 'config.yaml'
    $configContent = Format-LfTrailingNewline (Expand-Placeholder (Read-Text $configSrc))

    if ((Test-Path -LiteralPath $configDst) -and -not $OverwriteConfig) {
        $sideBySide = Join-Path $openspecDir 'config.kit.yaml'
        if ($PSCmdlet.ShouldProcess($sideBySide, '既存 config.yaml と並べて出力')) {
            Write-Text $sideBySide $configContent
            Write-Host "  [warn] openspec/config.yaml は既存のため openspec/config.kit.yaml に出力しました。手動でマージ後、config.kit.yaml を削除してください（上書きは -OverwriteConfig）" -ForegroundColor Yellow
        }
    }
    else {
        if (Test-Path -LiteralPath $configDst) {
            $tsPrefix = "$configDst.bak-$(Get-Date -Format 'yyyyMMddHHmmss')"
            $backup = Resolve-BackupPath -BasePrefix $tsPrefix -InitialCandidate $tsPrefix
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
}

# --- 7. AGENTS.md（同一ディレクトリ一時ファイル経由のアトミック更新） --------
$snippet = (ConvertTo-Lf (Expand-Placeholder (Read-Text (Join-Path $kitRoot 'AGENTS.openspec.md')))).TrimEnd()
$block = "$MarkerBegin`n`n$snippet`n`n$MarkerEnd"

if ($agentsMarkerStatus -eq 'VALID') {
    $beforeRaw = $existingAgentsLf.Substring(0, $existingBeginIdx)
    $beforePart = if ([string]::IsNullOrWhiteSpace($beforeRaw)) {
        ''
    }
    elseif ($beforeRaw.EndsWith("`n")) {
        $beforeRaw.Substring(0, $beforeRaw.Length - 1)
    }
    else {
        $beforeRaw
    }

    $afterRaw = $existingAgentsLf.Substring($existingEndIdx + $MarkerEnd.Length)
    $afterPart = if ([string]::IsNullOrWhiteSpace($afterRaw)) {
        ''
    }
    else {
        $trimmedAfter = if ($afterRaw.StartsWith("`n")) { $afterRaw.Substring(1) } else { $afterRaw }
        $trimmedAfter.TrimEnd("`n")
    }

    $parts = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrEmpty($beforePart)) { $parts.Add($beforePart) }
    $parts.Add($block)
    if (-not [string]::IsNullOrEmpty($afterPart)) { $parts.Add($afterPart) }
    $newAgents = ($parts -join "`n") + "`n"
    $action = 'マーカー区間を置換'
}
elseif ($agentsMarkerStatus -eq 'NONE') {
    $newAgents = $existingAgentsLf.TrimEnd() + "`n`n---`n`n" + $block + "`n"
    $action = '末尾に追記'
}
else {
    $skeleton = (ConvertTo-Lf (Expand-Placeholder (Read-Text (Join-Path $kitRoot 'AGENTS.project.md')))).TrimEnd()
    $newAgents = $skeleton + "`n`n---`n`n" + $block + "`n"
    $action = '新規作成'
}

$agentsByteCount = $Utf8NoBom.GetByteCount($newAgents)
if ($PSCmdlet.ShouldProcess($agentsPath, "AGENTS.md: $action")) {
    $tmpAgents = Join-Path $target ("AGENTS.md.tmp-" + [guid]::NewGuid().ToString('N'))
    try {
        [System.IO.File]::WriteAllText($tmpAgents, $newAgents, $Utf8NoBom)
        Move-Item -LiteralPath $tmpAgents -Destination $agentsPath -Force
    }
    finally {
        if (Test-Path -LiteralPath $tmpAgents) {
            Remove-Item -LiteralPath $tmpAgents -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host "  [ok]   AGENTS.md（$action / $agentsByteCount bytes。管理区間外の TODO を記入してください）" -ForegroundColor Green
    if ($agentsByteCount -ge 24000) {
        $excessBytes = $agentsByteCount - 24000
        Write-Host "  [warn] AGENTS.md のサイズが 24,000 バイト上限以上です（実バイト数: $agentsByteCount bytes / 超過: $excessBytes bytes）。プロジェクト固有ルールを別ファイル（references 等）へ分割してください。" -ForegroundColor Yellow
    }
}

# --- 8. .gitignore ------------------------------------------------------------
$ignoreLine = $EvidenceDir.Replace('\', '/')
$existingIgnore = if (Test-Path -LiteralPath $gitignorePath -PathType Leaf) { ConvertTo-Lf (Read-Text $gitignorePath) } else { '' }
$alreadyIgnored = ($existingIgnore -split "`n") -contains $ignoreLine

if (-not $alreadyIgnored -and $PSCmdlet.ShouldProcess($gitignorePath, "$ignoreLine を追記")) {
    $trimmedIgnore = $existingIgnore.TrimEnd()
    $newIgnore = if ([string]::IsNullOrEmpty($trimmedIgnore)) {
        "# Test evidence & coverage (openspec-kit)`n$ignoreLine`n"
    }
    else {
        "$trimmedIgnore`n`n# Test evidence & coverage (openspec-kit)`n$ignoreLine`n"
    }
    Write-Text $gitignorePath $newIgnore
    Write-Host "  [ok]   .gitignore に $ignoreLine を追記" -ForegroundColor Green
}

# --- 9. エージェント別エントリファイル（AGENTS.md を正本としてインポート） -------
foreach ($entry in @('CLAUDE.md', 'GEMINI.md')) {
    $entryPath = Join-Path $target $entry
    if (Test-Path -LiteralPath $entryPath -PathType Leaf) {
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

# --- 10. 可観測性サマリとガイダンス -------------------------------------------
Write-Host ""
Write-Host "=== openspec-kit 導入サマリ ===" -ForegroundColor Cyan
Write-Host "  対象ターゲット : $($resolvedTargets -join ', ')"
Write-Host "  スキル展開先   : $($deployedSkillPaths -join ', ')"
Write-Host "  スキル配置件数 : 配置 $($script:TotalSkillsDeployed) 件 / スキップ $($script:TotalSkillsSkipped) 件"
Write-Host "  旧WF退避件数   : $($migratedBackups.Count) 件"
Write-Host "  AGENTS.md      : $agentsByteCount bytes"

if ($script:TotalSkillsSkipped -gt 0 -and -not $Force) {
    Write-Host "  [warn] 既存のスキルファイルが $($script:TotalSkillsSkipped) 件スキップされました。更新された AGENTS.md との不整合を防ぐため、-Force（--force）を付けて再実行することを推奨します。" -ForegroundColor Yellow
}

if ($isZeroStateAuto) {
    Write-Host "  [info] 他のエージェントディレクトリ（.claude / .github / .opencode / .hermes）が未検出のため、.agents/skills のみに配置しました。後から他エージェントを追加する場合は -AgentTargets（--agent-targets）を指定して再実行してください（例: -AgentTargets claude,copilot または -AgentTargets all）。" -ForegroundColor Cyan
}

if ($migratedBackups.Count -gt 0) {
    Write-Host "  [info] 旧 .agents/workflows/sdd-*.md を .bak（$($migratedBackups -join ', ')）へ退避しました。カスタム記述がある場合は内容を確認し、不要であれば .bak ファイルを削除してください。" -ForegroundColor Yellow
}

Write-Host "完了。'openspec instructions proposal --change <name> --json' 等で context / rules が反映されることを確認してください。" -ForegroundColor Cyan
