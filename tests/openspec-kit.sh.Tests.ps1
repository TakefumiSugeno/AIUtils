#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# openspec-kit/install.sh および scripts/verify-gate.sh のテスト（Pester 5+）
#   実行: Import-Module Pester -MinimumVersion 5.0; Invoke-Pester ./tests/openspec-kit.sh.Tests.ps1 -Output Detailed

BeforeAll {
    $script:PreviousEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $script:GitBash = if (Test-Path 'C:\Program Files\Git\bin\bash.exe') {
        'C:\Program Files\Git\bin\bash.exe'
    }
    else {
        (Get-Command bash -ErrorAction Stop).Source
    }

    $script:InstallPs1 = Join-Path $PSScriptRoot '..\openspec-kit\install.ps1' | Resolve-Path
    $script:InstallSh = (Resolve-Path (Join-Path $PSScriptRoot '..\openspec-kit\install.sh')).Path.Replace('\', '/')
    $script:GateSh = (Resolve-Path (Join-Path $PSScriptRoot '..\openspec-kit\scripts\verify-gate.sh')).Path.Replace('\', '/')
    $script:KitTemplates = Join-Path $PSScriptRoot '..\openspec-kit\templates' | Resolve-Path
    $script:KitAgents = Join-Path $PSScriptRoot '..\openspec-kit\agents' | Resolve-Path
    $script:KitSkills = Join-Path $PSScriptRoot '..\openspec-kit\skills' | Resolve-Path

    function New-TargetProject {
        $dir = Join-Path ([IO.Path]::GetTempPath()) ("osk-sh-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $dir 'openspec') -Force | Out-Null
        return $dir
    }

    function Invoke-Bash([string]$ScriptPath, [string[]]$Arguments = @()) {
        $psi = [System.Diagnostics.ProcessStartInfo]::new($script:GitBash)
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
        # MSYS2 の argv パースによる {} ブレース展開・グロブ展開・未クォート ' 解釈を抑止する
        $psi.Environment['MSYS'] = 'noglob'

        $allArgs = @($ScriptPath)
        if ($Arguments) {
            $allArgs += $Arguments
        }
        $quotedArgs = foreach ($arg in $allArgs) {
            $s = if ($null -eq $arg) { '' } else { [string]$arg }
            '"' + $s.Replace('"', '"' + "'" + '"' + "'" + '"') + '"'
        }
        $psi.Arguments = ($quotedArgs -join ' ')

        $proc = [System.Diagnostics.Process]::Start($psi)
        try {
            $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
            $stderrTask = $proc.StandardError.ReadToEndAsync()
            $proc.WaitForExit()
            $outText = $stdoutTask.GetAwaiter().GetResult()
            $errText = $stderrTask.GetAwaiter().GetResult()
            $parts = @($outText, $errText) | Where-Object { -not [string]::IsNullOrEmpty($_) }
            return @{ ExitCode = $proc.ExitCode; Output = ($parts -join "`n") }
        }
        finally {
            $proc.Dispose()
        }
    }

    function Read-Utf8([string]$Path) {
        return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
    }

    function Write-Utf8NoBom([string]$Path, [string]$Content) {
        $parent = Split-Path -Parent $Path
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        [IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
    }

    function Get-RelativeFilePaths([string]$BaseDir) {
        if (-not (Test-Path -LiteralPath $BaseDir -PathType Container)) {
            return @()
        }
        $root = (Resolve-Path -LiteralPath $BaseDir).Path.TrimEnd('\', '/')
        return @(
            Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object {
                $_.FullName.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
            } | Sort-Object
        )
    }

    function Test-HasUtf8Bom([string]$Path) {
        $bytes = [IO.File]::ReadAllBytes($Path)
        return ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    }

    function Assert-DirectoryBytesParity([string]$PsDir, [string]$ShDir, [string]$ScenarioName) {
        $psFiles = Get-RelativeFilePaths $PsDir
        $shFiles = Get-RelativeFilePaths $ShDir
        $shFiles | Should -Be $psFiles -Because "$ScenarioName で install.ps1 と install.sh の生成ファイル一覧が一致する必要があります"

        foreach ($rel in $psFiles) {
            $p1 = Join-Path $PsDir $rel
            $p2 = Join-Path $ShDir $rel
            $b1 = [IO.File]::ReadAllBytes($p1)
            $b2 = [IO.File]::ReadAllBytes($p2)
            ($b1 -contains [byte]13) | Should -BeFalse -Because "$ScenarioName / $rel (PS) は LF 統一（CR なし）である必要があります"
            ($b2 -contains [byte]13) | Should -BeFalse -Because "$ScenarioName / $rel (SH) は LF 統一（CR なし）である必要があります"
            [System.Linq.Enumerable]::SequenceEqual($b1, $b2) | Should -BeTrue -Because "$ScenarioName / $rel の生バイト列が install.ps1 と install.sh で完全一致する必要があります (PS=$($b1.Length)B, SH=$($b2.Length)B)"
        }
    }

    function Set-ValidProposeFiles([string]$ChangeDir) {
        Set-Content -LiteralPath (Join-Path $ChangeDir 'proposal.md') -Value "# Proposal`nLevel: L2" -Encoding utf8
        Set-Content -LiteralPath (Join-Path $ChangeDir 'design.md') -Value "# Design" -Encoding utf8
        Set-Content -LiteralPath (Join-Path $ChangeDir 'test_plan.md') -Value "# Test Plan: sample-change`n| UT-01 | ok |" -Encoding utf8
        $specDir = Join-Path $ChangeDir 'specs/auth'
        New-Item -ItemType Directory -Path $specDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $specDir 'spec.md') -Value "## ADDED Requirements`n#### Scenario: Login" -Encoding utf8
        Set-Content -LiteralPath (Join-Path $ChangeDir 'tasks.md') -Value "# Tasks`n- [ ] 1.1 Red test`n- [ ] 1.2 Green impl" -Encoding utf8
        Set-Content -LiteralPath (Join-Path $ChangeDir 'reviews.md') -Value "# Review`n| 1 | 観点 | ✅ | 確認済み |`n- **LGTM**: true" -Encoding utf8
    }
}

Describe 'Bash スクリプト品質・構文検証' {
    It 'install.sh と verify-gate.sh が bash -n 構文チェックを通過する' {
        (& $script:GitBash -n $script:InstallSh 2>&1) | Out-Null
        $LASTEXITCODE | Should -Be 0
        (& $script:GitBash -n $script:GateSh 2>&1) | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It 'install.sh と verify-gate.sh が LF 改行（CR なし・UTF-8 BOM なし）である' {
        foreach ($p in @($script:InstallSh, $script:GateSh)) {
            $bytes = [IO.File]::ReadAllBytes($p)
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB) | Should -BeFalse
            ($bytes -contains [byte]13) | Should -BeFalse
        }
    }
}

Describe 'install.sh' {
    BeforeEach { $script:Target = New-TargetProject }
    AfterEach { Remove-Item -LiteralPath $script:Target -Recurse -Force -ErrorAction SilentlyContinue }

    It '[ST-04] openspec/ がない場合は非ゼロ終了コードで失敗し、ファイルを作成しない' {
        $empty = Join-Path ([IO.Path]::GetTempPath()) ("osk-sh-empty-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $empty | Out-Null
        try {
            $res = Invoke-Bash $script:InstallSh @('--target-path', $empty.Replace('\', '/'))
            $res.ExitCode | Should -Not -Be 0
            $res.Output | Should -Match 'openspec init'
            @(Get-ChildItem -LiteralPath $empty -Recurse -Force) | Should -HaveCount 0
        }
        finally { Remove-Item -LiteralPath $empty -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It '[UT-03][DT-01] 新規導入（.claude + .github 存在、auto）で全テンプレート・6ロール定義・スクリプト・マルチエージェントスキル・AGENTS.md を配置し、Zero-State 案内は出力しない' {
        New-Item -ItemType Directory -Path (Join-Path $script:Target '.claude') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:Target '.github') -Force | Out-Null
        $res = Invoke-Bash $script:InstallSh @('--target-path', $script:Target.Replace('\', '/'), '--base-branch', 'trunk', '--evidence-dir', 'out/evidence/')
        $res.ExitCode | Should -Be 0 -Because $res.Output
        $res.Output | Should -Not -Match '未検出のため' -Because '他エージェント検出時は Zero-State 案内を出力してはなりません'

        $expectedTpl = Get-ChildItem $script:KitTemplates -File | ForEach-Object Name | Sort-Object
        $actualTpl = Get-ChildItem (Join-Path $script:Target 'openspec/templates') -File | ForEach-Object Name | Sort-Object
        $actualTpl | Should -Be $expectedTpl
        $requiredTemplates = @(
            'test_plan.md',
            'review_record.md',
            'checklist_propose.md',
            'checklist_apply_impl.md',
            'checklist_apply_test.md',
            'checklist_archive.md',
            'handover.md',
            'pr_body.md'
        )
        foreach ($tplName in $requiredTemplates) {
            $actualTpl | Should -Contain $tplName -Because "必須テンプレート $tplName が配置される必要があります"
        }

        $actualAgents = Get-ChildItem (Join-Path $script:Target '.claude/agents') -File | ForEach-Object Name | Sort-Object
        $actualAgents.Count | Should -Be 6

        $expectedSkills = Get-RelativeFilePaths $script:KitSkills
        foreach ($skillDir in @('.agents/skills', '.claude/skills', '.github/skills')) {
            (Get-RelativeFilePaths (Join-Path $script:Target $skillDir)) | Should -Be $expectedSkills -Because "$skillDir に全スキルが再帰展開される必要があります"
        }
        Test-Path -LiteralPath (Join-Path $script:Target '.opencode') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:Target '.hermes') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:Target '.agents/workflows') | Should -BeFalse

        (Join-Path $script:Target 'openspec/scripts/verify-gate.sh') | Should -Exist
        (Join-Path $script:Target 'openspec/scripts/verify-gate.ps1') | Should -Exist
        Test-HasUtf8Bom (Join-Path $script:Target 'openspec/scripts/verify-gate.ps1') | Should -BeTrue
        Test-HasUtf8Bom (Join-Path $script:Target 'AGENTS.md') | Should -BeFalse
        Read-Utf8 (Join-Path $script:Target 'openspec/config.yaml') | Should -Match 'ベースブランチ: trunk'
        Read-Utf8 (Join-Path $script:Target 'AGENTS.md') | Should -Match 'git checkout trunk'
        Read-Utf8 (Join-Path $script:Target '.agents/skills/sdd-propose/references/sdd-reference.md') | Should -Match 'git checkout trunk'
        (Get-Content (Join-Path $script:Target '.gitignore')) | Should -Contain 'out/evidence/'
    }

    It '[DT-02][ST-01][E2E-02] 他エージェントディレクトリが一切ない空プロジェクトで --agent-targets auto 実行時、.agents/skills のみ配置し Zero-State 案内を出力する' {
        $res = Invoke-Bash $script:InstallSh @('--target-path', $script:Target.Replace('\', '/'), '--agent-targets', 'auto')
        $res.ExitCode | Should -Be 0 -Because $res.Output

        $expectedSkills = Get-RelativeFilePaths $script:KitSkills
        (Get-RelativeFilePaths (Join-Path $script:Target '.agents/skills')) | Should -Be $expectedSkills
        foreach ($dir in @('.claude', '.github', '.opencode', '.hermes')) {
            Test-Path -LiteralPath (Join-Path $script:Target $dir) | Should -BeFalse
        }
        $res.Output | Should -Match '(--agent-targets|-AgentTargets)' -Because 'Zero-State での追加展開オプション案内が必要です'
    }

    It '[UT-04][DT-03] --agent-targets all で 5 エージェントすべて（.agents, .claude, .github, .opencode, .hermes の各 skills/）に展開し、旧 sdd-*.md を退避する' {
        $wfDir = Join-Path $script:Target '.agents/workflows'
        New-Item -ItemType Directory -Path $wfDir -Force | Out-Null
        Write-Utf8NoBom (Join-Path $wfDir 'sdd-propose.md') 'legacy-propose'

        $res = Invoke-Bash $script:InstallSh @('--target-path', $script:Target.Replace('\', '/'), '--agent-targets', 'all')
        $res.ExitCode | Should -Be 0 -Because $res.Output

        $expectedSkills = Get-RelativeFilePaths $script:KitSkills
        foreach ($dir in @('.agents/skills', '.claude/skills', '.github/skills', '.opencode/skills', '.hermes/skills')) {
            (Get-RelativeFilePaths (Join-Path $script:Target $dir)) | Should -Be $expectedSkills -Because "$dir にスキル一式が必要です"
        }
        Test-Path -LiteralPath (Join-Path $wfDir 'sdd-propose.md') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $wfDir 'sdd-propose.md.bak') | Should -BeTrue
    }

    It '[UT-05][DT-04][DT-05][UT-11] --agent-targets " Claude , copilot " では .claude/skills と .github/skills のみ作成し、.agents/skills は作成せず旧 sdd-*.md も退避しない。antigravity,claude 指定時は両方作成＋退避する' {
        $wfDir = Join-Path $script:Target '.agents/workflows'
        New-Item -ItemType Directory -Path $wfDir -Force | Out-Null
        Write-Utf8NoBom (Join-Path $wfDir 'sdd-propose.md') 'legacy-propose'

        $t = $script:Target.Replace('\', '/')
        $res = Invoke-Bash $script:InstallSh @('--target-path', $t, '--agent-targets', ' Claude , copilot ')
        $res.ExitCode | Should -Be 0 -Because $res.Output

        $expectedSkills = Get-RelativeFilePaths $script:KitSkills
        (Get-RelativeFilePaths (Join-Path $script:Target '.claude/skills')) | Should -Be $expectedSkills
        (Get-RelativeFilePaths (Join-Path $script:Target '.github/skills')) | Should -Be $expectedSkills
        Test-Path -LiteralPath (Join-Path $script:Target '.agents/skills') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $wfDir 'sdd-propose.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $wfDir 'sdd-propose.md.bak') | Should -BeFalse

        # DT-05: antigravity,claude
        $res2 = Invoke-Bash $script:InstallSh @('--target-path', $t, '--agent-targets', 'antigravity,claude', '--force')
        $res2.ExitCode | Should -Be 0 -Because $res2.Output
        Test-Path -LiteralPath (Join-Path $script:Target '.agents/skills/sdd-propose/SKILL.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $wfDir 'sdd-propose.md') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $wfDir 'sdd-propose.md.bak') | Should -BeTrue
    }

    It '[UT-06][UT-07][DT-06][E2E-03] 不正な --agent-targets（空文字・空白・空トークン・未知ターゲット・auto混在）は非ゼロ終了しファイル変更を行わず、その後 --agent-targets claude,claude でリカバリ完了できる' {
        $t = $script:Target.Replace('\', '/')
        foreach ($bad in @('', '   ', 'claude,', ',claude', 'claude,,copilot', 'claude,unknown_cli', 'auto,claude', 'all,claude')) {
            $res = Invoke-Bash $script:InstallSh @('--target-path', $t, '--agent-targets', $bad)
            $res.ExitCode | Should -Not -Be 0 -Because "不正な --agent-targets '$bad' は非ゼロ終了する必要があります"
            $res.Output | Should -Not -Match '未知のオプション:\s*--agent-targets' -Because '--agent-targets オプション自体は認識した上でターゲット値バリデーションで拒否する必要があります'
            @(Get-ChildItem -LiteralPath $script:Target -Recurse -File) | Should -HaveCount 0 -Because "不正値 '$bad' でファイル書き込みが行われてはなりません"
        }

        $rec = Invoke-Bash $script:InstallSh @('--target-path', $t, '--agent-targets', 'claude,claude')
        $rec.ExitCode | Should -Be 0 -Because $rec.Output
        (Get-RelativeFilePaths (Join-Path $script:Target '.claude/skills')) | Should -Be (Get-RelativeFilePaths $script:KitSkills)
    }

    It '[IT-02] 再実行（--force --skip-config）しても AGENTS.md の管理区間は 1 つのまま（冪等）' {
        $t = $script:Target.Replace('\', '/')
        (Invoke-Bash $script:InstallSh @('--target-path', $t)).ExitCode | Should -Be 0
        $agentsPath = Join-Path $script:Target 'AGENTS.md'
        Set-Content -LiteralPath $agentsPath -Value ((Read-Utf8 $agentsPath) + "`n## カスタム追記`n") -Encoding utf8
        (Invoke-Bash $script:InstallSh @('--target-path', $t, '--force', '--skip-config')).ExitCode | Should -Be 0
        $first = Read-Utf8 $agentsPath
        (Invoke-Bash $script:InstallSh @('--target-path', $t, '--force', '--skip-config')).ExitCode | Should -Be 0
        $second = Read-Utf8 $agentsPath
        $second | Should -Be $first
        ([regex]::Matches($second, 'openspec-kit:begin')).Count | Should -Be 1
        $second | Should -Match '## カスタム追記'
    }

    It '[UT-08][UT-22][DT-07][DT-08] 既存スキルは --force なしで保護しつつ AGENTS.md 不整合防止の --force 再実行推奨警告を出力し、--force ありで上書き更新する' {
        $t = $script:Target.Replace('\', '/')
        (Invoke-Bash $script:InstallSh @('--target-path', $t, '--agent-targets', 'claude')).ExitCode | Should -Be 0
        $skillMd = Join-Path $script:Target '.claude/skills/sdd-propose/SKILL.md'
        Write-Utf8NoBom $skillMd 'custom-skill-sh'

        $noForce = Invoke-Bash $script:InstallSh @('--target-path', $t, '--agent-targets', 'claude')
        $noForce.ExitCode | Should -Be 0
        (Read-Utf8 $skillMd).Trim() | Should -Be 'custom-skill-sh'
        $noForce.Output | Should -Match '(?m)^(?=[^\r\n]*\[warn\])(?=[^\r\n]*AGENTS\.md)(?=[^\r\n]*(-Force|--force))[^\r\n]+$' -Because '既存スキルスキップ時は [skip] 行とは別に同一行内に [warn]・AGENTS.md・-Force/--force を含む再実行推奨警告行が必要です'

        $withForce = Invoke-Bash $script:InstallSh @('--target-path', $t, '--agent-targets', 'claude', '--force')
        $withForce.ExitCode | Should -Be 0
        (Read-Utf8 $skillMd) | Should -Not -Be 'custom-skill-sh'
        (Read-Utf8 $skillMd) | Should -Match 'name:\s*sdd-propose'
    }

    It '[UT-08][DT-10] --dry-run (-WhatIf) では新規作成・既存スキル上書き・旧 sdd-*.md の .bak 退避を一切行わず、What If 予定出力にスキルと退避対象が含まれる' {
        $t = $script:Target.Replace('\', '/')
        $res = Invoke-Bash $script:InstallSh @('--target-path', $t, '--dry-run')
        $res.ExitCode | Should -Be 0
        @(Get-ChildItem -LiteralPath $script:Target -Recurse -File) | Should -HaveCount 0

        $existingSkill = Join-Path $script:Target '.claude/skills/sdd-propose/SKILL.md'
        Write-Utf8NoBom $existingSkill 'keep-existing-sh'
        $legacyWf = Join-Path $script:Target '.agents/workflows/sdd-propose.md'
        Write-Utf8NoBom $legacyWf 'keep-legacy-sh'

        $res2 = Invoke-Bash $script:InstallSh @('--target-path', $t, '--agent-targets', 'all', '--force', '--dry-run')
        $res2.ExitCode | Should -Be 0
        (Read-Utf8 $existingSkill).Trim() | Should -Be 'keep-existing-sh'
        Test-Path -LiteralPath $legacyWf | Should -BeTrue
        Test-Path -LiteralPath "$legacyWf.bak" | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:Target '.agents/skills') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:Target 'AGENTS.md') | Should -BeFalse
        $res2.Output | Should -Match 'What If:' -Because '--dry-run 実行時は What If: 出力が必要です'
        $res2.Output | Should -Match 'What If:[^\r\n]*(skills|sdd-propose)' -Because 'What If 出力にスキル展開対象が含まれる必要があります'
        $res2.Output | Should -Match 'What If:[^\r\n]*sdd-propose\.md' -Because 'What If 出力にレガシー退避対象が含まれる必要があります'
    }

    It '[UT-09][UT-10][DT-09][IT-03][ST-02][ST-03] 旧 sdd-*.md のみを .bak / .bak-timestamp-counter へ後段退避し、opsx-propose.md を保護し、再実行で .bak が増殖しない' {
        $t = $script:Target.Replace('\', '/')
        $wfDir = Join-Path $script:Target '.agents/workflows'
        New-Item -ItemType Directory -Path $wfDir -Force | Out-Null
        Write-Utf8NoBom (Join-Path $wfDir 'sdd-propose.md') 'v1-propose'
        Write-Utf8NoBom (Join-Path $wfDir 'sdd-apply.md') 'v1-apply'
        Write-Utf8NoBom (Join-Path $wfDir 'sdd-archive.md') 'v1-archive'
        Write-Utf8NoBom (Join-Path $wfDir 'opsx-propose.md') 'opsx-keep'

        $r1 = Invoke-Bash $script:InstallSh @('--target-path', $t, '--force', '--skip-config')
        $r1.ExitCode | Should -Be 0 -Because $r1.Output
        foreach ($name in @('sdd-propose.md', 'sdd-apply.md', 'sdd-archive.md')) {
            Test-Path -LiteralPath (Join-Path $wfDir $name) | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $wfDir "$name.bak") | Should -BeTrue
        }
        (Read-Utf8 (Join-Path $wfDir 'sdd-propose.md.bak')).Trim() | Should -Be 'v1-propose'
        (Read-Utf8 (Join-Path $wfDir 'opsx-propose.md')).Trim() | Should -Be 'opsx-keep'
        $r1.Output | Should -Match '\.bak'

        # ST-03: 再実行で増殖しない
        (Invoke-Bash $script:InstallSh @('--target-path', $t, '--force', '--skip-config')).ExitCode | Should -Be 0
        @(Get-ChildItem -LiteralPath $wfDir -Filter 'sdd-propose.md.bak*') | Should -HaveCount 1

        # UT-10: 既存 .bak がある状態で同秒連続2回退避
        Write-Utf8NoBom (Join-Path $wfDir 'sdd-propose.md') 'v2-propose'
        (Invoke-Bash $script:InstallSh @('--target-path', $t, '--force', '--skip-config')).ExitCode | Should -Be 0
        Write-Utf8NoBom (Join-Path $wfDir 'sdd-propose.md') 'v3-propose'
        (Invoke-Bash $script:InstallSh @('--target-path', $t, '--force', '--skip-config')).ExitCode | Should -Be 0

        (Read-Utf8 (Join-Path $wfDir 'sdd-propose.md.bak')).Trim() | Should -Be 'v1-propose'
        $stampedBaks = @(Get-ChildItem -LiteralPath $wfDir -File | Where-Object { $_.Name -match '^sdd-propose\.md\.bak-\d{14}-\d+$' } | Sort-Object Name)
        $stampedBaks.Count | Should -Be 2
        (@($stampedBaks | ForEach-Object { (Read-Utf8 $_.FullName).Trim() } | Sort-Object)) | Should -Be @('v2-propose', 'v3-propose')
        (Read-Utf8 (Join-Path $wfDir 'opsx-propose.md')).Trim() | Should -Be 'opsx-keep'
    }

    It '[UT-23] 既存記述肥大化で AGENTS.md が 23,999B で警告なし、24,000B 以上となった場合は実バイト数・超過数・分割案内を警告出力する' {
        $t = $script:Target.Replace('\', '/')
        $agentsPath = Join-Path $script:Target 'AGENTS.md'

        # 23,999B / 24,000B 境界テスト
        $boundaryTarget = New-TargetProject
        try {
            $bt = $boundaryTarget.Replace('\', '/')
            $bAgentsPath = Join-Path $boundaryTarget 'AGENTS.md'
            Write-Utf8NoBom $bAgentsPath "# Boundary Test`n"
            (Invoke-Bash $script:InstallSh @('--target-path', $bt, '--force', '--skip-config')).ExitCode | Should -Be 0
            (Invoke-Bash $script:InstallSh @('--target-path', $bt, '--force', '--skip-config')).ExitCode | Should -Be 0
            $syncedContent = Read-Utf8 $bAgentsPath
            $baseBytes = [IO.File]::ReadAllBytes($bAgentsPath).Length

            $pad23999 = 23999 - $baseBytes
            $pad23999 | Should -BeGreaterThan 0
            Write-Utf8NoBom $bAgentsPath (('A' * $pad23999) + $syncedContent)
            $res23999 = Invoke-Bash $script:InstallSh @('--target-path', $bt, '--force', '--skip-config')
            $res23999.ExitCode | Should -Be 0 -Because $res23999.Output
            [IO.File]::ReadAllBytes($bAgentsPath).Length | Should -Be 23999
            $res23999.Output | Should -Not -Match '\[warn\].*24,?000' -Because '23,999 バイトでは 24,000B 上限超過警告を出してはなりません'

            Write-Utf8NoBom $bAgentsPath (('A' * ($pad23999 + 1)) + $syncedContent)
            $res24000 = Invoke-Bash $script:InstallSh @('--target-path', $bt, '--force', '--skip-config')
            $res24000.ExitCode | Should -Be 0 -Because $res24000.Output
            [IO.File]::ReadAllBytes($bAgentsPath).Length | Should -Be 24000
            $res24000.Output | Should -Match '\[warn\].*24,?000' -Because '24,000 バイト以上では上限超過警告が必要です'
            $res24000.Output | Should -Match '実バイト数:\s*24000'
            $res24000.Output | Should -Match '超過:\s*0'
        }
        finally {
            Remove-Item -LiteralPath $boundaryTarget -Recurse -Force -ErrorAction SilentlyContinue
        }

        Write-Utf8NoBom $agentsPath ("# Large Project Rules`n`n" + ('A' * 20000) + "`n")
        $res = Invoke-Bash $script:InstallSh @('--target-path', $t, '--force', '--skip-config')
        $res.ExitCode | Should -Be 0 -Because $res.Output
        $totalBytes = [IO.File]::ReadAllBytes($agentsPath).Length
        $totalBytes | Should -BeGreaterOrEqual 24000
        $res.Output | Should -Match "$totalBytes"
        $res.Output | Should -Match "$(($totalBytes - 24000))"
        $res.Output | Should -Match '(24,?000|分割|別ファイル|references)'
    }

    It '[UT-24][IT-06] 破損マーカー AGENTS.md（<CaseName>）に対しては二重追記せず非ゼロ終了し、元のファイル内容を保持する' -ForEach @(
        @{ CaseName = 'beginのみ'; Content = "# Project Rules`n`n<!-- openspec-kit:begin (install.ps1 により管理。手動編集は再同期で上書きされます) -->`n途中のルール（endマーカー欠損）`n" },
        @{ CaseName = 'endのみ'; Content = "# Project Rules`n`n<!-- openspec-kit:end -->`n" },
        @{ CaseName = '順序逆転(end先行後にbegin)'; Content = "# Project Rules`n`n<!-- openspec-kit:end -->`n途中`n<!-- openspec-kit:begin -->`n" },
        @{ CaseName = '同一行順序逆転(end ... begin)'; Content = "# Project Rules`n<!-- openspec-kit:end --> <!-- openspec-kit:begin -->`n" },
        @{ CaseName = '重複マーカー(begin ... end ... begin)'; Content = "# Project Rules`n<!-- openspec-kit:begin -->`nA`n<!-- openspec-kit:end -->`n<!-- openspec-kit:begin -->`n" },
        @{ CaseName = '重複マーカー(begin ... begin ... end)'; Content = "# Project Rules`n<!-- openspec-kit:begin -->`n<!-- openspec-kit:begin -->`nA`n<!-- openspec-kit:end -->`n" }
    ) {
        $t = $script:Target.Replace('\', '/')
        $agentsPath = Join-Path $script:Target 'AGENTS.md'
        Write-Utf8NoBom $agentsPath $Content

        $res = Invoke-Bash $script:InstallSh @('--target-path', $t)
        $res.ExitCode | Should -Not -Be 0 -Because "破損マーカー ($CaseName) は非ゼロ終了する必要があります"
        (Read-Utf8 $agentsPath) | Should -Be $Content
    }

    It '[UT-25][IT-06] --base-branch と --evidence-dir に特殊文字 (&, |, \) が含まれていても sed 破壊を起こさずリテラル展開される' {
        $t = $script:Target.Replace('\', '/')
        $specialBranch = 'feat/a&b|c\d'
        $specialEvidence = 'out&1/ev/'
        $res = Invoke-Bash $script:InstallSh @('--target-path', $t, '--base-branch', $specialBranch, '--evidence-dir', $specialEvidence)
        $res.ExitCode | Should -Be 0 -Because $res.Output

        (Read-Utf8 (Join-Path $script:Target 'openspec/config.yaml')).Contains($specialBranch) | Should -BeTrue
        $agents = Read-Utf8 (Join-Path $script:Target 'AGENTS.md')
        $agents.Contains($specialBranch) | Should -BeTrue
        $agents.Contains($specialEvidence) | Should -BeTrue
        (Read-Utf8 (Join-Path $script:Target '.agents/skills/sdd-propose/references/sdd-reference.md')).Contains($specialBranch) | Should -BeTrue
    }

    It '[UT-25] 二重置換が起きず（--base-branch {{EVIDENCE_DIR}}）、シングルクォート含有時も verify-gate.ps1 / verify-gate.sh に構文エラーが生じない' {
        $tDouble = New-TargetProject
        try {
            $resD = Invoke-Bash $script:InstallSh @('--target-path', $tDouble.Replace('\', '/'), '--base-branch', '{{EVIDENCE_DIR}}', '--evidence-dir', 'out/ev/')
            $resD.ExitCode | Should -Be 0 -Because $resD.Output
            (Read-Utf8 (Join-Path $tDouble 'openspec/config.yaml')).Contains('ベースブランチ: {{EVIDENCE_DIR}}') | Should -BeTrue -Because '--base-branch に指定した {{EVIDENCE_DIR}} が --evidence-dir で二重置換されてはなりません'
            (Read-Utf8 (Join-Path $tDouble 'AGENTS.md')).Contains('git checkout {{EVIDENCE_DIR}}') | Should -BeTrue
            (Read-Utf8 (Join-Path $tDouble 'AGENTS.md')).Contains('out/ev/') | Should -BeTrue
            (Read-Utf8 (Join-Path $tDouble '.agents/skills/sdd-propose/references/sdd-reference.md')).Contains('git checkout {{EVIDENCE_DIR}}') | Should -BeTrue
        }
        finally {
            Remove-Item -LiteralPath $tDouble -Recurse -Force -ErrorAction SilentlyContinue
        }

        $tQuote = New-TargetProject
        try {
            $quoteBranch = "feat/it's-branch"
            $quoteEvidence = "out/it's-ev/"
            $resQ = Invoke-Bash $script:InstallSh @('--target-path', $tQuote.Replace('\', '/'), '--base-branch', $quoteBranch, '--evidence-dir', $quoteEvidence)
            $resQ.ExitCode | Should -Be 0 -Because $resQ.Output

            $gatePs1 = Join-Path $tQuote 'openspec/scripts/verify-gate.ps1'
            $tokens = $null
            $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($gatePs1, [ref]$tokens, [ref]$parseErrors) | Out-Null
            $parseErrors | Should -HaveCount 0 -Because 'シングルクォートを含む --base-branch/--evidence-dir 展開後も verify-gate.ps1 の PowerShell 構文は有効である必要があります'

            $gateSh = (Join-Path $tQuote 'openspec/scripts/verify-gate.sh').Replace('\', '/')
            (& $script:GitBash -n $gateSh 2>&1) | Out-Null
            $LASTEXITCODE | Should -Be 0
            (Read-Utf8 (Join-Path $tQuote 'openspec/config.yaml')).Contains($quoteBranch) | Should -BeTrue
            (Read-Utf8 (Join-Path $tQuote 'AGENTS.md')).Contains($quoteBranch) | Should -BeTrue
        }
        finally {
            Remove-Item -LiteralPath $tQuote -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It '[UT-25][IT-06] --base-branch / --evidence-dir / --agent-targets に改行 (\n) が含まれる場合は書き込み前に非ゼロ終了する' -ForEach @(
        @{ Flag = '--base-branch'; Val = "main`nfoo" },
        @{ Flag = '--evidence-dir'; Val = "out/`nevid/" },
        @{ Flag = '--agent-targets'; Val = "claude`ncopilot" }
    ) {
        $t = $script:Target.Replace('\', '/')
        $res = Invoke-Bash $script:InstallSh @('--target-path', $t, $Flag, $Val)
        $res.ExitCode | Should -Not -Be 0 -Because "$Flag に改行が含まれる場合は事前エラー停止する必要があります"
        @(Get-ChildItem -LiteralPath $script:Target -Recurse -File) | Should -HaveCount 0
    }

    It '[IT-06] 配置予定ファイル位置（<ConflictPath>）に既存ディレクトリが存在する場合は前半ファイル書き込み前に非ゼロ終了する' -ForEach @(
        @{ ConflictPath = '.claude/skills/sdd-propose/SKILL.md'; ExtraArgs = @('--agent-targets', 'claude') },
        @{ ConflictPath = 'CLAUDE.md'; ExtraArgs = @() },
        @{ ConflictPath = 'openspec/config.yaml'; ExtraArgs = @() }
    ) {
        New-Item -ItemType Directory -Path (Join-Path $script:Target $ConflictPath) -Force | Out-Null
        $t = $script:Target.Replace('\', '/')
        $argList = @('--target-path', $t) + $ExtraArgs
        $res = Invoke-Bash $script:InstallSh $argList
        $res.ExitCode | Should -Not -Be 0 -Because "$ConflictPath が既存ディレクトリの場合は書き込み前に非ゼロ終了する必要があります"
        Test-Path -LiteralPath (Join-Path $script:Target 'openspec/templates') | Should -BeFalse -Because 'ファイル配置前に衝突を検知して中断する必要があります'
        Test-Path -LiteralPath (Join-Path $script:Target 'AGENTS.md') | Should -BeFalse
    }

    It '[IT-06][IT-07] 展開先（.claude または .claude/skills）がディレクトリではなく通常ファイルとして存在する場合は書き込み前に非ゼロ終了し、旧 sdd-*.md を退避して消してしまわない' {
        $t = $script:Target.Replace('\', '/')
        $wfDir = Join-Path $script:Target '.agents/workflows'
        New-Item -ItemType Directory -Path $wfDir -Force | Out-Null
        $legacyPropose = Join-Path $wfDir 'sdd-propose.md'
        Write-Utf8NoBom $legacyPropose 'must-survive-on-failure-sh'

        $claudeFile = Join-Path $script:Target '.claude'
        Write-Utf8NoBom $claudeFile 'not-a-directory'

        $res = Invoke-Bash $script:InstallSh @('--target-path', $t)
        $res.ExitCode | Should -Not -Be 0 -Because '.claude が通常ファイルの場合は書き込み前に非ゼロ終了する必要があります'
        Test-Path -LiteralPath (Join-Path $script:Target 'openspec/templates') | Should -BeFalse -Because '展開先パス種別検証はファイル書き込み前に行う必要があります'
        Test-Path -LiteralPath $legacyPropose | Should -BeTrue
        Test-Path -LiteralPath "$legacyPropose.bak" | Should -BeFalse
        (Read-Utf8 $claudeFile).Trim() | Should -Be 'not-a-directory'
    }

    It '[IT-07] 事前検証通過後にスキルファイル配置が ReadOnly 属性等で失敗した場合は停止し、旧 .agents/workflows/sdd-*.md が退避されて消滅しない' {
        $t = $script:Target.Replace('\', '/')
        $wfDir = Join-Path $script:Target '.agents/workflows'
        New-Item -ItemType Directory -Path $wfDir -Force | Out-Null
        $legacyPropose = Join-Path $wfDir 'sdd-propose.md'
        Write-Utf8NoBom $legacyPropose 'must-survive-on-copy-failure-sh'

        $skillMd = Join-Path $script:Target '.agents/skills/sdd-propose/SKILL.md'
        Write-Utf8NoBom $skillMd 'readonly-skill-sh'
        Set-ItemProperty -LiteralPath $skillMd -Name IsReadOnly -Value $true
        try {
            $res = Invoke-Bash $script:InstallSh @('--target-path', $t, '--agent-targets', 'antigravity', '--force', '--skip-config')
            $res.ExitCode | Should -Not -Be 0 -Because 'ReadOnly スキルの上書き失敗時は非ゼロ終了する必要があります'
            Test-Path -LiteralPath $legacyPropose | Should -BeTrue -Because 'スキルコピー失敗時は旧ワークフローを退避してはなりません'
            Test-Path -LiteralPath "$legacyPropose.bak" | Should -BeFalse
        }
        finally {
            if (Test-Path -LiteralPath $skillMd) {
                Set-ItemProperty -LiteralPath $skillMd -Name IsReadOnly -Value $false
            }
        }
    }

    It '[IT-08] 旧 .agents/workflows/sdd-*.md の退避（リネーム）がファイルロックで失敗した場合は対象パスと復旧案内を出して非ゼロ終了する' {
        $t = $script:Target.Replace('\', '/')
        $wfDir = Join-Path $script:Target '.agents/workflows'
        New-Item -ItemType Directory -Path $wfDir -Force | Out-Null
        $lockedFile = Join-Path $wfDir 'sdd-propose.md'
        Write-Utf8NoBom $lockedFile 'locked-legacy-workflow-sh'

        $fs = [System.IO.File]::Open($lockedFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        try {
            $res = Invoke-Bash $script:InstallSh @('--target-path', $t, '--force', '--skip-config')
            Test-Path -LiteralPath (Join-Path $script:Target '.agents/skills/sdd-propose/SKILL.md') | Should -BeTrue -Because 'スキル配置成功後の後段退避ステップで検査される必要があります'
            $res.ExitCode | Should -Not -Be 0 -Because '退避リネーム失敗時は非ゼロ終了する必要があります'
            $res.Output | Should -Match 'sdd-propose\.md'
            $res.Output | Should -Match '(退避|バックアップ|\.bak|手動|リネーム|削除)' -Because '退避失敗時の復旧案内が必要です'
        }
        finally {
            $fs.Dispose()
        }
    }

    It '[IT-01] 同一条件（<Mode>）で install.ps1 と install.sh の配置ファイル一覧・生バイト列・LF 統一・BOM 有無が完全一致する' -ForEach @(
        @{ Mode = 'auto'; PreCreateDirs = @('.claude', '.github') },
        @{ Mode = 'all'; PreCreateDirs = @() },
        @{ Mode = 'claude,copilot'; PreCreateDirs = @() }
    ) {
        $psTarget = New-TargetProject
        $shTarget = New-TargetProject
        try {
            foreach ($d in $PreCreateDirs) {
                New-Item -ItemType Directory -Path (Join-Path $psTarget $d) -Force | Out-Null
                New-Item -ItemType Directory -Path (Join-Path $shTarget $d) -Force | Out-Null
            }

            & $script:InstallPs1 -TargetPath $psTarget -BaseBranch 'main' -EvidenceDir 'test-results/' -AgentTargets $Mode *>$null
            $shRes = Invoke-Bash $script:InstallSh @('--target-path', $shTarget.Replace('\', '/'), '--base-branch', 'main', '--evidence-dir', 'test-results/', '--agent-targets', $Mode)
            $shRes.ExitCode | Should -Be 0 -Because $shRes.Output

            Assert-DirectoryBytesParity -PsDir $psTarget -ShDir $shTarget -ScenarioName "Mode=$Mode"
        }
        finally {
            Remove-Item -LiteralPath $psTarget -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $shTarget -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It '[IT-01] 既存 AGENTS.md に end マーカー直後の空行＋## カスタム追記がある再同期状態で install.ps1 と install.sh の生バイト列が完全一致し、空行が増減しない' {
        $psTarget = New-TargetProject
        $shTarget = New-TargetProject
        try {
            foreach ($d in @('.claude', '.github')) {
                New-Item -ItemType Directory -Path (Join-Path $psTarget $d) -Force | Out-Null
                New-Item -ItemType Directory -Path (Join-Path $shTarget $d) -Force | Out-Null
            }

            & $script:InstallPs1 -TargetPath $psTarget -BaseBranch 'main' -EvidenceDir 'test-results/' -AgentTargets 'auto' *>$null
            $shInit = Invoke-Bash $script:InstallSh @('--target-path', $shTarget.Replace('\', '/'), '--base-branch', 'main', '--evidence-dir', 'test-results/', '--agent-targets', 'auto')
            $shInit.ExitCode | Should -Be 0 -Because $shInit.Output

            foreach ($dir in @($psTarget, $shTarget)) {
                $ap = Join-Path $dir 'AGENTS.md'
                $raw = (Read-Utf8 $ap).Replace("`r`n", "`n")
                $withCustom = [regex]::Replace($raw, '(<!-- openspec-kit:end[^\n]*-->)\n*$', "`$1`n`n## カスタム追記`n独自ルール`n")
                Write-Utf8NoBom $ap $withCustom
            }

            & $script:InstallPs1 -TargetPath $psTarget -BaseBranch 'main' -EvidenceDir 'test-results/' -AgentTargets 'auto' -Force -SkipConfig *>$null
            $shSync = Invoke-Bash $script:InstallSh @('--target-path', $shTarget.Replace('\', '/'), '--base-branch', 'main', '--evidence-dir', 'test-results/', '--agent-targets', 'auto', '--force', '--skip-config')
            $shSync.ExitCode | Should -Be 0 -Because $shSync.Output

            Assert-DirectoryBytesParity -PsDir $psTarget -ShDir $shTarget -ScenarioName 'ResyncWithTrailingBlankLine'

            $psAgents = Read-Utf8 (Join-Path $psTarget 'AGENTS.md')
            $psAgents | Should -Match '<!-- openspec-kit:end[^\n]*-->\n\n## カスタム追記\n独自ルール\n' -Because 'end マーカー直後の空行が消えたり増えたりしてはなりません'
        }
        finally {
            Remove-Item -LiteralPath $psTarget -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $shTarget -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'verify-gate.sh' {
    BeforeEach {
        $script:Root = New-TargetProject
        $script:ChangeDir = Join-Path $script:Root 'openspec/changes/sample-change'
        New-Item -ItemType Directory -Path $script:ChangeDir -Force | Out-Null
    }
    AfterEach { Remove-Item -LiteralPath $script:Root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'Gate 1 (propose): L2 の必須ファイルと LGTM: true が揃っていれば PASS' {
        Set-ValidProposeFiles $script:ChangeDir
        $res = Invoke-Bash $script:GateSh @('--gate', 'propose', '--change-name', 'sample-change', '--target-path', $script:Root.Replace('\', '/'), '--skip-git-check')
        $res.ExitCode | Should -Be 0
        $res.Output | Should -Match 'PASSED'
    }

    It 'Gate 1 (propose): L2 で test_plan.md が欠落していれば FAIL' {
        Set-ValidProposeFiles $script:ChangeDir
        Remove-Item -LiteralPath (Join-Path $script:ChangeDir 'test_plan.md')
        $res = Invoke-Bash $script:GateSh @('--gate', 'propose', '--change-name', 'sample-change', '--target-path', $script:Root.Replace('\', '/'), '--skip-git-check')
        $res.ExitCode | Should -Be 1
        $res.Output | Should -Match 'test_plan\.md が存在しません'
    }

    It 'Gate 2 (apply): .skip( テストが放置されている場合は FAIL' {
        Set-ValidProposeFiles $script:ChangeDir
        $testDir = Join-Path $script:Root 'test'
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $testDir 'app.test.js') -Value ('it' + ".skip('pending', () => {});") -Encoding utf8
        $res = Invoke-Bash $script:GateSh @('-Gate', 'apply', '-ChangeName', 'sample-change', '-TargetPath', $script:Root.Replace('\', '/'), '-SkipGitCheck')
        $res.ExitCode | Should -Be 1
        $res.Output | Should -Match 'Skip / Ignore 状態のテストが放置'
    }

    It 'Gate 3 (archive): 全タスク [x]・handover.md 記入済み・LGTM: true で PASS、未完了タスクがあれば FAIL' {
        Set-ValidProposeFiles $script:ChangeDir
        Set-Content -LiteralPath (Join-Path $script:ChangeDir 'tasks.md') -Value "- [x] 1.1 Done`n- [x] 1.2 Done" -Encoding utf8
        Set-Content -LiteralPath (Join-Path $script:ChangeDir 'handover.md') -Value "# Handover: sample-change`n- Date: 2026-10-29" -Encoding utf8
        Set-Content -LiteralPath (Join-Path $script:ChangeDir 'reviews.md') -Value "- **LGTM**: true" -Encoding utf8

        $passRes = Invoke-Bash $script:GateSh @('--gate', 'archive', '--change-name', 'sample-change', '--target-path', $script:Root.Replace('\', '/'), '--skip-git-check')
        $passRes.ExitCode | Should -Be 0

        Set-Content -LiteralPath (Join-Path $script:ChangeDir 'tasks.md') -Value "- [x] 1.1 Done`n- [ ] 1.2 NotDone" -Encoding utf8
        $failRes = Invoke-Bash $script:GateSh @('--gate', 'archive', '--change-name', 'sample-change', '--target-path', $script:Root.Replace('\', '/'), '--skip-git-check')
        $failRes.ExitCode | Should -Be 1
        $failRes.Output | Should -Match '未完了タスク'
    }

    AfterAll {
        if ($null -ne $script:PreviousEncoding) {
            [Console]::OutputEncoding = $script:PreviousEncoding
        }
    }
}
