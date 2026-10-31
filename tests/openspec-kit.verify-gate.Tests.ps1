#Requires -Modules Pester
# openspec-kit/scripts/verify-gate.ps1 のテスト（Pester 5+）
#   実行: Invoke-Pester ./tests/openspec-kit.verify-gate.Tests.ps1 -Output Detailed

BeforeAll {
    $script:GateScript = Join-Path $PSScriptRoot '..\openspec-kit\scripts\verify-gate.ps1' | Resolve-Path

    function New-GateTestProject([string]$ChangeName = 'sample-change') {
        $dir = Join-Path ([IO.Path]::GetTempPath()) ("osk-gate-" + [guid]::NewGuid().ToString('N'))
        $changeDir = Join-Path $dir "openspec/changes/$ChangeName"
        New-Item -ItemType Directory -Path $changeDir -Force | Out-Null
        return @{ Root = $dir; ChangeDir = $changeDir; ChangeName = $ChangeName }
    }

    function Invoke-Gate([string]$Root, [string]$Gate, [string]$ChangeName = 'sample-change', [string]$Level = '') {
        $argsList = @('-NoProfile', '-File', $script:GateScript, '-Gate', $Gate, '-TargetPath', $Root, '-SkipGitCheck')
        if ($ChangeName) { $argsList += @('-ChangeName', $ChangeName) }
        if ($Level) { $argsList += @('-Level', $Level) }
        $output = & pwsh @argsList 2>&1
        return @{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
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

Describe 'verify-gate.ps1' {
    BeforeEach {
        $ctx = New-GateTestProject
        $script:Root = $ctx.Root
        $script:ChangeDir = $ctx.ChangeDir
    }
    AfterEach {
        Remove-Item -LiteralPath $script:Root -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'Gate 1: propose' {
        It 'L2 の全必須ファイルと LGTM: true が揃っていれば PASS (ExitCode 0)' {
            Set-ValidProposeFiles $script:ChangeDir
            $res = Invoke-Gate $script:Root 'propose'
            $res.ExitCode | Should -Be 0
            $res.Output | Should -Match 'PASSED'
        }

        It 'L2 で test_plan.md が欠落している場合は FAIL (ExitCode 1)' {
            Set-ValidProposeFiles $script:ChangeDir
            Remove-Item -LiteralPath (Join-Path $script:ChangeDir 'test_plan.md')
            $res = Invoke-Gate $script:Root 'propose'
            $res.ExitCode | Should -Be 1
            $res.Output | Should -Match 'test_plan\.md が存在しません'
        }

        It 'L1 かつ skip_specs: true なら test_plan.md と specs/ がなくても PASS' {
            Set-Content -LiteralPath (Join-Path $script:ChangeDir '.openspec.yaml') -Value "level: L1`nskip_specs: true" -Encoding utf8
            Set-Content -LiteralPath (Join-Path $script:ChangeDir 'proposal.md') -Value "# Proposal" -Encoding utf8
            Set-Content -LiteralPath (Join-Path $script:ChangeDir 'tasks.md') -Value "- [ ] 1.1 Fix typo" -Encoding utf8
            Set-Content -LiteralPath (Join-Path $script:ChangeDir 'reviews.md') -Value "- **LGTM**: true" -Encoding utf8
            $res = Invoke-Gate $script:Root 'propose'
            $res.ExitCode | Should -Be 0
        }

        It 'reviews.md に未記入の ✅/❌/⚠️ が残っている場合は FAIL' {
            Set-ValidProposeFiles $script:ChangeDir
            Set-Content -LiteralPath (Join-Path $script:ChangeDir 'reviews.md') -Value "| 1 | 観点 | ✅/❌/⚠️ | |`n- **LGTM**: true" -Encoding utf8
            $res = Invoke-Gate $script:Root 'propose'
            $res.ExitCode | Should -Be 1
            $res.Output | Should -Match '未判定のチェックリスト項目'
        }

        It 'reviews.md の最新判定が LGTM: false の場合は FAIL' {
            Set-ValidProposeFiles $script:ChangeDir
            Set-Content -LiteralPath (Join-Path $script:ChangeDir 'reviews.md') -Value "- **LGTM**: true`n- **LGTM**: false" -Encoding utf8
            $res = Invoke-Gate $script:Root 'propose'
            $res.ExitCode | Should -Be 1
            $res.Output | Should -Match 'LGTM: true ではありません'
        }
    }

    Context 'Gate 2: apply' {
        It 'reviews.md が LGTM: true かつ skip テストがなければ PASS' {
            Set-ValidProposeFiles $script:ChangeDir
            $res = Invoke-Gate $script:Root 'apply'
            $res.ExitCode | Should -Be 0
        }

        It 'テストディレクトリ内に .skip( テストが放置されている場合は FAIL' {
            Set-ValidProposeFiles $script:ChangeDir
            $testDir = Join-Path $script:Root 'test'
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $testDir 'app.test.js') -Value "it.skip('should work', () => {});" -Encoding utf8
            $res = Invoke-Gate $script:Root 'apply'
            $res.ExitCode | Should -Be 1
            $res.Output | Should -Match 'Skip / Ignore 状態のテストが放置'
        }
    }

    Context 'Gate 3: archive' {
        BeforeEach {
            Set-ValidProposeFiles $script:ChangeDir
            Set-Content -LiteralPath (Join-Path $script:ChangeDir 'tasks.md') -Value "- [x] 1.1 Red test`n- [x] 1.2 Green impl" -Encoding utf8
            Set-Content -LiteralPath (Join-Path $script:ChangeDir 'handover.md') -Value "# Handover: sample-change`n- Date: 2026-10-29" -Encoding utf8
            Set-Content -LiteralPath (Join-Path $script:ChangeDir 'reviews.md') -Value "- **LGTM**: true" -Encoding utf8
        }

        It '全タスク [x]、handover.md 記入済み、LGTM: true で PASS' {
            $res = Invoke-Gate $script:Root 'archive'
            $res.ExitCode | Should -Be 0
            $res.Output | Should -Match 'PASSED'
        }

        It 'tasks.md に未完了タスク（- [ ]）が残っている場合は FAIL' {
            Set-Content -LiteralPath (Join-Path $script:ChangeDir 'tasks.md') -Value "- [x] 1.1 Done`n- [ ] 1.2 Remaining" -Encoding utf8
            $res = Invoke-Gate $script:Root 'archive'
            $res.ExitCode | Should -Be 1
            $res.Output | Should -Match '未完了タスク'
        }

        It 'handover.md が未作成または未記入プレースホルダがある場合は FAIL' {
            Set-Content -LiteralPath (Join-Path $script:ChangeDir 'handover.md') -Value "# Handover: <change-name>" -Encoding utf8
            $res = Invoke-Gate $script:Root 'archive'
            $res.ExitCode | Should -Be 1
            $res.Output | Should -Match 'handover\.md に未記入のプレースホルダ'
        }

        It 'reviews.md の最新総括レビューが LGTM: false の場合は FAIL' {
            Set-Content -LiteralPath (Join-Path $script:ChangeDir 'reviews.md') -Value "- **LGTM**: true`n- **LGTM**: false" -Encoding utf8
            $res = Invoke-Gate $script:Root 'archive'
            $res.ExitCode | Should -Be 1
            $res.Output | Should -Match 'LGTM: true ではありません'
        }
    }
}
