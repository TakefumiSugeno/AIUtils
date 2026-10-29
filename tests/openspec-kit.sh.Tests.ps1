#Requires -Modules Pester
# openspec-kit/install.sh および scripts/verify-gate.sh のテスト（Pester 5+）
#   実行: Invoke-Pester ./tests/openspec-kit.sh.Tests.ps1 -Output Detailed

BeforeAll {
    $script:GitBash = if (Test-Path 'C:\Program Files\Git\bin\bash.exe') {
        'C:\Program Files\Git\bin\bash.exe'
    } else {
        (Get-Command bash -ErrorAction Stop).Source
    }

    $script:InstallSh = (Resolve-Path (Join-Path $PSScriptRoot '..\openspec-kit\install.sh')).Path.Replace('\', '/')
    $script:GateSh = (Resolve-Path (Join-Path $PSScriptRoot '..\openspec-kit\scripts\verify-gate.sh')).Path.Replace('\', '/')
    $script:KitTemplates = Join-Path $PSScriptRoot '..\openspec-kit\templates' | Resolve-Path
    $script:KitAgents = Join-Path $PSScriptRoot '..\openspec-kit\agents' | Resolve-Path

    function New-TargetProject {
        $dir = Join-Path ([IO.Path]::GetTempPath()) ("osk-sh-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $dir 'openspec') -Force | Out-Null
        return $dir
    }

    function Invoke-Bash([string]$ScriptPath, [string[]]$Arguments) {
        $out = & $script:GitBash $ScriptPath @Arguments 2>&1
        return @{ ExitCode = $LASTEXITCODE; Output = ($out -join "`n") }
    }

    function Read-Utf8([string]$Path) { [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) }

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

    It 'openspec/ がない場合は非ゼロ終了コードで失敗する' {
        $empty = Join-Path ([IO.Path]::GetTempPath()) ("osk-sh-empty-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $empty | Out-Null
        try {
            $res = Invoke-Bash $script:InstallSh @('--target-path', $empty.Replace('\', '/'))
            $res.ExitCode | Should -Not -Be 0
            $res.Output | Should -Match 'openspec init'
        }
        finally { Remove-Item -LiteralPath $empty -Recurse -Force }
    }

    It '新規導入で全テンプレート・6ロール定義・スクリプト・ワークフロー・AGENTS.md を配置する' {
        New-Item -ItemType Directory -Path (Join-Path $script:Target '.claude') -Force | Out-Null
        $res = Invoke-Bash $script:InstallSh @('--target-path', $script:Target.Replace('\', '/'), '--base-branch', 'trunk', '--evidence-dir', 'out/evidence/')
        $res.ExitCode | Should -Be 0

        $expectedTpl = Get-ChildItem $script:KitTemplates -File | ForEach-Object Name | Sort-Object
        $actualTpl = Get-ChildItem (Join-Path $script:Target 'openspec/templates') -File | ForEach-Object Name | Sort-Object
        $actualTpl | Should -Be $expectedTpl

        $actualAgents = Get-ChildItem (Join-Path $script:Target '.claude/agents') -File | ForEach-Object Name | Sort-Object
        $actualAgents.Count | Should -Be 6

        (Join-Path $script:Target 'openspec/scripts/verify-gate.sh') | Should -Exist
        (Join-Path $script:Target 'openspec/scripts/verify-gate.ps1') | Should -Exist
        Read-Utf8 (Join-Path $script:Target 'openspec/config.yaml') | Should -Match 'ベースブランチ: trunk'
        Read-Utf8 (Join-Path $script:Target 'AGENTS.md') | Should -Match 'git checkout trunk'
        (Get-Content (Join-Path $script:Target '.gitignore')) | Should -Contain 'out/evidence/'
    }

    It '再実行（--force --skip-config）しても AGENTS.md の管理区間は 1 つのまま（冪等）' {
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

    It '--dry-run (-WhatIf) では何も書き込まない' {
        $res = Invoke-Bash $script:InstallSh @('--target-path', $script:Target.Replace('\', '/'), '--dry-run')
        $res.ExitCode | Should -Be 0
        @(Get-ChildItem -LiteralPath $script:Target -Recurse -File) | Should -HaveCount 0
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
        Set-Content -LiteralPath (Join-Path $testDir 'app.test.js') -Value "it.skip('pending', () => {});" -Encoding utf8
        $res = Invoke-Bash $script:GateSh @('-Gate', 'apply', '-ChangeName', 'sample-change', '-TargetPath', $script:Root.Replace('\', '/'), '-SkipGitCheck')
        $res.ExitCode | Should -Be 1
        $res.Output | Should -Match 'Skip / Ignore 状態のテストが放置'
    }

    It 'Gate 3 (archive): 全タスク [x]・handover.md 記入済み・LGTM: true・合意: あり で PASS、未完了タスクがあれば FAIL' {
        Set-ValidProposeFiles $script:ChangeDir
        Set-Content -LiteralPath (Join-Path $script:ChangeDir 'tasks.md') -Value "- [x] 1.1 Done`n- [x] 1.2 Done" -Encoding utf8
        Set-Content -LiteralPath (Join-Path $script:ChangeDir 'handover.md') -Value "# Handover: sample-change`n- Date: 2026-10-29" -Encoding utf8
        Set-Content -LiteralPath (Join-Path $script:ChangeDir 'reviews.md') -Value "- **LGTM**: true`n- **合意**: あり" -Encoding utf8

        $passRes = Invoke-Bash $script:GateSh @('--gate', 'archive', '--change-name', 'sample-change', '--target-path', $script:Root.Replace('\', '/'), '--skip-git-check')
        $passRes.ExitCode | Should -Be 0

        Set-Content -LiteralPath (Join-Path $script:ChangeDir 'tasks.md') -Value "- [x] 1.1 Done`n- [ ] 1.2 NotDone" -Encoding utf8
        $failRes = Invoke-Bash $script:GateSh @('--gate', 'archive', '--change-name', 'sample-change', '--target-path', $script:Root.Replace('\', '/'), '--skip-git-check')
        $failRes.ExitCode | Should -Be 1
        $failRes.Output | Should -Match '未完了タスク'
    }
}
