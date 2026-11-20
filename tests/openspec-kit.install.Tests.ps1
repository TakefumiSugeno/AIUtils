#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# openspec-kit/install.ps1 のテスト（Pester 5+）
#   実行: Import-Module Pester -MinimumVersion 5.0; Invoke-Pester ./tests/openspec-kit.install.Tests.ps1 -Output Detailed

BeforeAll {
    $script:Installer = Join-Path $PSScriptRoot '..\openspec-kit\install.ps1' | Resolve-Path
    $script:KitRoot = Join-Path $PSScriptRoot '..\openspec-kit' | Resolve-Path
    $script:KitTemplates = Join-Path $PSScriptRoot '..\openspec-kit\templates' | Resolve-Path
    $script:KitAgents = Join-Path $PSScriptRoot '..\openspec-kit\agents' | Resolve-Path
    $script:KitSkills = Join-Path $PSScriptRoot '..\openspec-kit\skills' | Resolve-Path

    function New-TargetProject {
        $dir = Join-Path ([IO.Path]::GetTempPath()) ("osk-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $dir 'openspec') -Force | Out-Null
        return $dir
    }

    function Invoke-Installer([string]$Target, [hashtable]$Extra = @{}) {
        $out = & $script:Installer -TargetPath $Target @Extra *>&1
        return (($out | ForEach-Object { "$_" }) -join "`n")
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
}

Describe 'install.ps1' {
    BeforeEach { $script:Target = New-TargetProject }
    AfterEach { Remove-Item -LiteralPath $script:Target -Recurse -Force -ErrorAction SilentlyContinue }

    It '[ST-04] openspec/ がない場合は失敗し、ファイルを一切作成しない' {
        $empty = Join-Path ([IO.Path]::GetTempPath()) ("osk-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $empty | Out-Null
        try {
            { & $script:Installer -TargetPath $empty *>$null } | Should -Throw '*openspec init*'
            @(Get-ChildItem -LiteralPath $empty -Recurse -Force) | Should -HaveCount 0
        }
        finally { Remove-Item -LiteralPath $empty -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It '[UT-02] openspec-kit/workflows ディレクトリが廃止され存在しない' {
        $legacyWorkflowsDir = Join-Path $script:KitRoot 'workflows'
        Test-Path -LiteralPath $legacyWorkflowsDir | Should -BeFalse -Because '旧 openspec-kit/workflows/ は openspec-kit/skills/ へ完全移行し削除されている必要があります'
    }

    Context '新規導入' {
        BeforeEach {
            New-Item -ItemType Directory -Path (Join-Path $script:Target '.claude') -Force | Out-Null
            $script:InstallOutput = Invoke-Installer $script:Target @{ BaseBranch = 'trunk'; EvidenceDir = 'out/evidence/' }
        }

        It '全テンプレート（主要8ファイル含む）を配置する' {
            $expected = Get-ChildItem $script:KitTemplates -File | ForEach-Object Name | Sort-Object
            $actual = Get-ChildItem (Join-Path $script:Target 'openspec/templates') -File | ForEach-Object Name | Sort-Object
            $actual | Should -Be $expected
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
                $actual | Should -Contain $tplName -Because "必須テンプレート $tplName が配置される必要があります"
            }
        }

        It '6ロールのサブエージェント定義を openspec/agents と .claude/agents に配置する' {
            $expected = Get-ChildItem $script:KitAgents -File | ForEach-Object Name | Sort-Object
            $actualOpenSpec = Get-ChildItem (Join-Path $script:Target 'openspec/agents') -File | ForEach-Object Name | Sort-Object
            $actualClaude = Get-ChildItem (Join-Path $script:Target '.claude/agents') -File | ForEach-Object Name | Sort-Object
            $actualOpenSpec | Should -Be $expected
            $actualClaude | Should -Be $expected
            $actualOpenSpec.Count | Should -Be 6
        }

        It 'verify-gate.ps1 を UTF-8 BOM 付きで openspec/scripts に配置し、プレースホルダを置換する' {
            $gateScript = Join-Path $script:Target 'openspec/scripts/verify-gate.ps1'
            $gateScript | Should -Exist
            Test-HasUtf8Bom $gateScript | Should -BeTrue
            $text = Read-Utf8 $gateScript
            $text | Should -Match "BaseBranch = 'trunk'"
        }

        It '[UT-01][UT-03] SDD スキル（sdd-propose / sdd-apply / sdd-archive）を references/・scripts/ ごと .agents/skills と .claude/skills に再帰配置し、プレースホルダ置換と BOM なし UTF-8 を満たす' {
            $expectedRel = Get-RelativeFilePaths $script:KitSkills
            $expectedRel | Should -Contain 'sdd-propose/SKILL.md'
            $expectedRel | Should -Contain 'sdd-propose/references/sdd-reference.md'
            $expectedRel | Should -Contain 'sdd-propose/references/antigravity-orchestration.md'
            $expectedRel | Should -Contain 'sdd-propose/scripts/run_propose_review.py'
            $expectedRel | Should -Contain 'sdd-apply/SKILL.md'
            $expectedRel | Should -Contain 'sdd-archive/scripts/run_archive_review.py'

            foreach ($skillRoot in @('.agents/skills', '.claude/skills')) {
                $dstDir = Join-Path $script:Target $skillRoot
                $actualRel = Get-RelativeFilePaths $dstDir
                $actualRel | Should -Be $expectedRel -Because "$skillRoot に全スキルファイルが再帰展開される必要があります"

                $proposeRef = Join-Path $dstDir 'sdd-propose/references/sdd-reference.md'
                Read-Utf8 $proposeRef | Should -Match 'git checkout trunk'
                Read-Utf8 $proposeRef | Should -Not -Match '\{\{(BASE_BRANCH|EVIDENCE_DIR)\}\}'

                foreach ($f in (Get-ChildItem -LiteralPath $dstDir -Recurse -File)) {
                    Test-HasUtf8Bom $f.FullName | Should -BeFalse -Because "$($f.FullName) は UTF-8 (BOM なし) で出力される必要があります"
                }
            }
            Test-Path -LiteralPath (Join-Path $script:Target '.agents/workflows') | Should -BeFalse -Because '新規導入時に旧 .agents/workflows は作成しない'
        }

        It 'config.yaml のプレースホルダを置換する' {
            $config = Read-Utf8 (Join-Path $script:Target 'openspec/config.yaml')
            $config | Should -Match 'ベースブランチ: trunk'
            $config | Should -Not -Match '\{\{BASE_BRANCH\}\}'
        }

        It 'AGENTS.md を雛形＋管理区間で作成し、プレースホルダを置換する' {
            $agents = Read-Utf8 (Join-Path $script:Target 'AGENTS.md')
            $agents | Should -Match '## プロジェクト固有ルール'
            $agents | Should -Match 'openspec-kit:begin'
            $agents | Should -Match 'openspec-kit:end'
            $agents | Should -Match 'git checkout trunk'
            $agents | Should -Match 'out/evidence/'
            $agents | Should -Not -Match '\{\{(BASE_BRANCH|EVIDENCE_DIR)\}\}'
        }

        It 'review_record.md の {{date}} は置換しない' {
            Read-Utf8 (Join-Path $script:Target 'openspec/templates/review_record.md') | Should -Match '\{\{date\}\}'
        }

        It '.gitignore にエビデンス出力先を追記する' {
            (Get-Content (Join-Path $script:Target '.gitignore')) | Should -Contain 'out/evidence/'
        }

        It 'CLAUDE.md / GEMINI.md を @AGENTS.md で作成する' {
            (Read-Utf8 (Join-Path $script:Target 'CLAUDE.md')).Trim() | Should -Be '@AGENTS.md'
            (Read-Utf8 (Join-Path $script:Target 'GEMINI.md')).Trim() | Should -Be '@AGENTS.md'
        }

        It 'Markdown ファイルは BOM なし UTF-8 で書き込む' {
            Test-HasUtf8Bom (Join-Path $script:Target 'AGENTS.md') | Should -BeFalse
        }
    }

    Context 'マルチエージェントスキル多面展開 (-AgentTargets)' {
        It '[UT-03][DT-01] .claude/ と .github/ のみ存在時に -AgentTargets auto で .agents/skills, .claude/skills, .github/skills, .claude/agents に展開し、未存在の .opencode/skills, .hermes/skills は作成せず Zero-State 案内も出力しない' {
            New-Item -ItemType Directory -Path (Join-Path $script:Target '.claude') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $script:Target '.github') -Force | Out-Null

            $out = Invoke-Installer $script:Target @{ AgentTargets = 'auto' }

            $expectedRel = Get-RelativeFilePaths $script:KitSkills
            foreach ($dir in @('.agents/skills', '.claude/skills', '.github/skills')) {
                (Get-RelativeFilePaths (Join-Path $script:Target $dir)) | Should -Be $expectedRel
            }
            (Get-ChildItem (Join-Path $script:Target '.claude/agents') -File).Count | Should -Be 6
            Test-Path -LiteralPath (Join-Path $script:Target '.opencode') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $script:Target '.hermes') | Should -BeFalse
            $out | Should -Not -Match '未検出のため' -Because '他エージェント検出時は Zero-State 案内を出力してはなりません'
        }

        It '[DT-02][ST-01][E2E-02] 他エージェントディレクトリが一切ない空プロジェクトで -AgentTargets auto 実行時、.agents/skills/sdd-* のみ配置され、Zero-State 案内（-AgentTargets 再実行案内）が出力される' {
            $out = Invoke-Installer $script:Target @{ AgentTargets = 'auto' }

            $expectedRel = Get-RelativeFilePaths $script:KitSkills
            (Get-RelativeFilePaths (Join-Path $script:Target '.agents/skills')) | Should -Be $expectedRel
            foreach ($dir in @('.claude', '.github', '.opencode', '.hermes')) {
                Test-Path -LiteralPath (Join-Path $script:Target $dir) | Should -BeFalse -Because "未検出の $dir を自動作成してはならない"
            }
            $out | Should -Match '(-AgentTargets|--agent-targets)' -Because '後から他エージェントを追加する際の再実行オプション案内が必要です'
        }

        It '[UT-04][DT-03] -AgentTargets all で 5 エージェントすべて（.agents, .claude, .github, .opencode, .hermes の各 skills/）に再帰展開し、旧 .agents/workflows/sdd-*.md も退避する' {
            $wfDir = Join-Path $script:Target '.agents/workflows'
            New-Item -ItemType Directory -Path $wfDir -Force | Out-Null
            Write-Utf8NoBom (Join-Path $wfDir 'sdd-propose.md') 'legacy-propose'

            Invoke-Installer $script:Target @{ AgentTargets = 'all' } | Out-Null

            $expectedRel = Get-RelativeFilePaths $script:KitSkills
            foreach ($dir in @('.agents/skills', '.claude/skills', '.github/skills', '.opencode/skills', '.hermes/skills')) {
                (Get-RelativeFilePaths (Join-Path $script:Target $dir)) | Should -Be $expectedRel -Because "$dir にスキル一式が必要です"
            }
            Test-Path -LiteralPath (Join-Path $wfDir 'sdd-propose.md') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $wfDir 'sdd-propose.md.bak') | Should -BeTrue
        }

        It '[UT-05][DT-04][UT-11] -AgentTargets " Claude , copilot "（antigravity を含まない CSV）では .claude/skills と .github/skills のみ作成し、.agents/skills は作成せず旧 .agents/workflows/sdd-*.md も退避しない' {
            $wfDir = Join-Path $script:Target '.agents/workflows'
            New-Item -ItemType Directory -Path $wfDir -Force | Out-Null
            Write-Utf8NoBom (Join-Path $wfDir 'sdd-propose.md') 'legacy-propose'

            Invoke-Installer $script:Target @{ AgentTargets = ' Claude , copilot ' } | Out-Null

            $expectedRel = Get-RelativeFilePaths $script:KitSkills
            (Get-RelativeFilePaths (Join-Path $script:Target '.claude/skills')) | Should -Be $expectedRel
            (Get-RelativeFilePaths (Join-Path $script:Target '.github/skills')) | Should -Be $expectedRel
            Test-Path -LiteralPath (Join-Path $script:Target '.agents/skills') | Should -BeFalse -Because 'antigravity 未指定時は .agents/skills を作成しない'
            Test-Path -LiteralPath (Join-Path $wfDir 'sdd-propose.md') | Should -BeTrue -Because '.agents/skills 非対象時は旧ワークフローを退避してはならない'
            Test-Path -LiteralPath (Join-Path $wfDir 'sdd-propose.md.bak') | Should -BeFalse
        }

        It '[DT-04][DT-05] -AgentTargets "claude,hermes" と "antigravity,claude" でそれぞれ指定ターゲットのみ作成し、antigravity 含有時のみ旧 sdd-*.md を退避する' {
            $wfDir = Join-Path $script:Target '.agents/workflows'
            New-Item -ItemType Directory -Path $wfDir -Force | Out-Null
            Write-Utf8NoBom (Join-Path $wfDir 'sdd-apply.md') 'legacy-apply'

            Invoke-Installer $script:Target @{ AgentTargets = 'claude,hermes' } | Out-Null
            Test-Path -LiteralPath (Join-Path $script:Target '.claude/skills/sdd-apply/SKILL.md') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $script:Target '.hermes/skills/sdd-apply/SKILL.md') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $script:Target '.agents/skills') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $wfDir 'sdd-apply.md') | Should -BeTrue

            Invoke-Installer $script:Target @{ AgentTargets = 'antigravity,claude'; Force = $true } | Out-Null
            Test-Path -LiteralPath (Join-Path $script:Target '.agents/skills/sdd-apply/SKILL.md') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $wfDir 'sdd-apply.md') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $wfDir 'sdd-apply.md.bak') | Should -BeTrue
        }

        It '[UT-06][UT-07][DT-06][E2E-03] 不正な -AgentTargets（空文字・空白のみ・空トークン・未知ターゲット・auto混在）は書き込み前にエラー停止し、その後正しい -AgentTargets claude でリカバリ導入できる。重複 "claude,claude" は重複排除して正常完了する' {
            foreach ($bad in @('', '   ', 'claude,', ',claude', 'claude,,copilot', 'claude,unknown_cli', 'auto,claude', 'all,claude')) {
                { Invoke-Installer $script:Target @{ AgentTargets = $bad } } | Should -Throw -Because "不正な AgentTargets '$bad' は拒否される必要があります"
                @(Get-ChildItem -LiteralPath $script:Target -Recurse -File) | Should -HaveCount 0 -Because "不正値 '$bad' でファイル書き込みが行われてはなりません"
            }

            # E2E-03 Recovery: 正しい指定で再実行すれば正常完了すること
            Invoke-Installer $script:Target @{ AgentTargets = 'claude,claude' } | Out-Null
            $expectedRel = Get-RelativeFilePaths $script:KitSkills
            (Get-RelativeFilePaths (Join-Path $script:Target '.claude/skills')) | Should -Be $expectedRel
            Test-Path -LiteralPath (Join-Path $script:Target 'AGENTS.md') | Should -BeTrue
        }
    }

    Context '既存ファイル保護・-Force 警告・-WhatIf 抑止' {
        It '既存 AGENTS.md の末尾に管理区間を追記し、既存内容を保持する' {
            Set-Content -LiteralPath (Join-Path $script:Target 'AGENTS.md') -Value "# 既存`n`n独自ルール" -Encoding utf8
            Invoke-Installer $script:Target | Out-Null
            $agents = Read-Utf8 (Join-Path $script:Target 'AGENTS.md')
            $agents | Should -Match '独自ルール'
            $agents | Should -Match 'openspec-kit:begin'
        }

        It '[IT-02] 再実行（-Force -SkipConfig）しても管理区間は1つのまま（冪等）で区間外は保持される' {
            Invoke-Installer $script:Target | Out-Null
            $path = Join-Path $script:Target 'AGENTS.md'
            Set-Content -LiteralPath $path -Value ((Read-Utf8 $path) + "`n## 追記セクション`n") -Encoding utf8
            Invoke-Installer $script:Target @{ Force = $true; SkipConfig = $true } | Out-Null
            $first = Read-Utf8 $path
            Invoke-Installer $script:Target @{ Force = $true; SkipConfig = $true } | Out-Null
            $second = Read-Utf8 $path
            $second | Should -Be $first
            ([regex]::Matches($second, 'openspec-kit:begin')).Count | Should -Be 1
            $second | Should -Match '## 追記セクション'
        }

        It '既存 config.yaml は上書きせず config.kit.yaml を出力する' {
            $config = Join-Path $script:Target 'openspec/config.yaml'
            Set-Content -LiteralPath $config -Value 'schema: spec-driven' -Encoding utf8
            Invoke-Installer $script:Target | Out-Null
            (Get-Content $config -Raw).Trim() | Should -Be 'schema: spec-driven'
            Join-Path $script:Target 'openspec/config.kit.yaml' | Should -Exist
        }

        It '-OverwriteConfig はバックアップを作成して上書きする' {
            $config = Join-Path $script:Target 'openspec/config.yaml'
            Set-Content -LiteralPath $config -Value 'schema: spec-driven' -Encoding utf8
            Invoke-Installer $script:Target @{ OverwriteConfig = $true } | Out-Null
            Get-ChildItem (Join-Path $script:Target 'openspec') -Filter 'config.yaml.bak-*' | Should -HaveCount 1
            Read-Utf8 $config | Should -Match 'reviews:'
        }

        It '-SkipConfig は config を一切出力しない' {
            Invoke-Installer $script:Target @{ SkipConfig = $true } | Out-Null
            Join-Path $script:Target 'openspec/config.yaml' | Should -Not -Exist
            Join-Path $script:Target 'openspec/config.kit.yaml' | Should -Not -Exist
        }

        It '既存テンプレートは -Force なしではスキップする' {
            $tpl = Join-Path $script:Target 'openspec/templates/review_record.md'
            New-Item -ItemType Directory -Path (Split-Path $tpl) -Force | Out-Null
            Set-Content -LiteralPath $tpl -Value 'custom' -Encoding utf8
            Invoke-Installer $script:Target | Out-Null
            (Get-Content $tpl -Raw).Trim() | Should -Be 'custom'
        }

        It '.gitignore に登録済みなら重複追記しない' {
            Invoke-Installer $script:Target | Out-Null
            Invoke-Installer $script:Target | Out-Null
            @(Get-Content (Join-Path $script:Target '.gitignore') | Where-Object { $_ -eq 'test/TestResults/' }) | Should -HaveCount 1
        }

        It '[UT-08][UT-22][DT-07][DT-08] 既存スキルは -Force なしで保護しつつ AGENTS.md 不整合防止の -Force 再実行推奨警告を出力し、-Force ありで上書き更新する' {
            Invoke-Installer $script:Target @{ AgentTargets = 'claude' } | Out-Null
            $skillMd = Join-Path $script:Target '.claude/skills/sdd-propose/SKILL.md'
            Write-Utf8NoBom $skillMd 'custom-skill-content'

            # DT-07: -Force なし
            $outNoForce = Invoke-Installer $script:Target @{ AgentTargets = 'claude' }
            (Read-Utf8 $skillMd).Trim() | Should -Be 'custom-skill-content'
            $outNoForce | Should -Match '(?m)^(?=[^\r\n]*\[warn\])(?=[^\r\n]*AGENTS\.md)(?=[^\r\n]*(-Force|--force))[^\r\n]+$' -Because '既存スキルスキップ時は [skip] 行とは別に同一行内に [warn]・AGENTS.md・-Force/--force を含む再実行推奨警告行が必要です'

            # DT-08: -Force あり
            Invoke-Installer $script:Target @{ AgentTargets = 'claude'; Force = $true } | Out-Null
            (Read-Utf8 $skillMd) | Should -Not -Be 'custom-skill-content'
            (Read-Utf8 $skillMd) | Should -Match 'name:\s*sdd-propose'
        }

        It '[UT-08][DT-10] -WhatIf では新規ファイル作成・既存スキル上書き・旧 sdd-*.md の .bak 退避を一切行わず、What If 予定出力にスキルと退避対象が含まれる' {
            # 空プロジェクトへの -WhatIf
            & $script:Installer -TargetPath $script:Target -WhatIf *>$null
            @(Get-ChildItem -LiteralPath $script:Target -Recurse -File) | Should -HaveCount 0

            # 既存スキル＋旧ワークフローがある状態で -AgentTargets all -Force -WhatIf
            $existingSkill = Join-Path $script:Target '.claude/skills/sdd-propose/SKILL.md'
            Write-Utf8NoBom $existingSkill 'keep-existing'
            $legacyWf = Join-Path $script:Target '.agents/workflows/sdd-propose.md'
            Write-Utf8NoBom $legacyWf 'keep-legacy'

            $whatIfRaw = & pwsh -NoProfile -File $script:Installer -TargetPath $script:Target -AgentTargets 'all' -Force -WhatIf 2>&1
            $LASTEXITCODE | Should -Be 0
            $whatIfOut = (($whatIfRaw | ForEach-Object { "$_" }) -join "`n")

            (Read-Utf8 $existingSkill).Trim() | Should -Be 'keep-existing'
            Test-Path -LiteralPath $legacyWf | Should -BeTrue
            Test-Path -LiteralPath "$legacyWf.bak" | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $script:Target '.agents/skills') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $script:Target 'AGENTS.md') | Should -BeFalse
            $whatIfOut | Should -Match 'What If:' -Because '-WhatIf 実行時は What If: 出力が必要です'
            $whatIfOut | Should -Match 'What If:[^\r\n]*(skills|sdd-propose)' -Because 'What If 出力にスキル展開対象が含まれる必要があります'
            $whatIfOut | Should -Match 'What If:[^\r\n]*sdd-propose\.md' -Because 'What If 出力にレガシー退避対象が含まれる必要があります'
        }
    }

    Context 'レガシーワークフロー (.agents/workflows/sdd-*.md) の安全移行' {
        It '[UT-09][UT-10][DT-09][IT-03][ST-02][ST-03] 旧 sdd-*.md のみを .bak（既存 .bak がある場合は .bak-timestamp-counter）へ後段退避し、退避案内を出力し、opsx-propose.md を保護し、再実行で .bak が増殖しない' {
            $wfDir = Join-Path $script:Target '.agents/workflows'
            New-Item -ItemType Directory -Path $wfDir -Force | Out-Null
            Write-Utf8NoBom (Join-Path $wfDir 'sdd-propose.md') 'v1-propose'
            Write-Utf8NoBom (Join-Path $wfDir 'sdd-apply.md') 'v1-apply'
            Write-Utf8NoBom (Join-Path $wfDir 'sdd-archive.md') 'v1-archive'
            Write-Utf8NoBom (Join-Path $wfDir 'opsx-propose.md') 'opsx-keep'

            # 1回目 (ST-02): .bak への退避
            $out1 = Invoke-Installer $script:Target @{ Force = $true; SkipConfig = $true }
            foreach ($name in @('sdd-propose.md', 'sdd-apply.md', 'sdd-archive.md')) {
                Test-Path -LiteralPath (Join-Path $wfDir $name) | Should -BeFalse
                Test-Path -LiteralPath (Join-Path $wfDir "$name.bak") | Should -BeTrue
            }
            (Read-Utf8 (Join-Path $wfDir 'sdd-propose.md.bak')).Trim() | Should -Be 'v1-propose'
            (Read-Utf8 (Join-Path $wfDir 'opsx-propose.md')).Trim() | Should -Be 'opsx-keep'
            $out1 | Should -Match '\.bak' -Because '退避したバックアップファイルの案内が必要です'

            # 2回目 (ST-03): 移行完了後の再実行で .bak が増殖しないこと
            Invoke-Installer $script:Target @{ Force = $true; SkipConfig = $true } | Out-Null
            @(Get-ChildItem -LiteralPath $wfDir -Filter 'sdd-propose.md.bak*') | Should -HaveCount 1

            # UT-10 / IT-03: 既存 .bak がある状態で再び sdd-propose.md が置かれた場合（同秒連続2回含む）
            Write-Utf8NoBom (Join-Path $wfDir 'sdd-propose.md') 'v2-propose'
            Invoke-Installer $script:Target @{ Force = $true; SkipConfig = $true } | Out-Null
            Write-Utf8NoBom (Join-Path $wfDir 'sdd-propose.md') 'v3-propose'
            Invoke-Installer $script:Target @{ Force = $true; SkipConfig = $true } | Out-Null

            Test-Path -LiteralPath (Join-Path $wfDir 'sdd-propose.md') | Should -BeFalse
            (Read-Utf8 (Join-Path $wfDir 'sdd-propose.md.bak')).Trim() | Should -Be 'v1-propose'
            $stampedBaks = @(Get-ChildItem -LiteralPath $wfDir -File | Where-Object { $_.Name -match '^sdd-propose\.md\.bak-\d{14}-\d+$' } | Sort-Object Name)
            $stampedBaks.Count | Should -Be 2 -Because '既存 .bak を上書きせず .bak-<timestamp>-<counter> で衝突回避する必要があります'
            $contents = @($stampedBaks | ForEach-Object { (Read-Utf8 $_.FullName).Trim() } | Sort-Object)
            $contents | Should -Be @('v2-propose', 'v3-propose')
            (Read-Utf8 (Join-Path $wfDir 'opsx-propose.md')).Trim() | Should -Be 'opsx-keep'
        }
    }

    Context 'AGENTS.md の安全更新・サイズ上限・異常系耐性' {
        It '[UT-23][IT-04] 新規 AGENTS.md は 24,000B 未満（BOM なし）で verify-gate.ps1 が通り、既存記述肥大化で 24,000B 以上となった場合は実バイト数・超過数・分割案内を警告出力する' {
            Invoke-Installer $script:Target @{ BaseBranch = 'main'; EvidenceDir = 'test-results/' } | Out-Null
            $agentsPath = Join-Path $script:Target 'AGENTS.md'
            Test-HasUtf8Bom $agentsPath | Should -BeFalse
            $normalBytes = [IO.File]::ReadAllBytes($agentsPath).Length
            $normalBytes | Should -BeLessThan 24000
            $normalBytes | Should -BeLessOrEqual 16000

            # IT-04: 配置された verify-gate.ps1 が pre-propose (-SkipGitCheck) で正常動作すること
            $gateScript = Join-Path $script:Target 'openspec/scripts/verify-gate.ps1'
            { & $gateScript -Gate 'pre-propose' -TargetPath $script:Target -SkipGitCheck *>$null } | Should -Not -Throw

            # UT-23: 境界値（23,999B で警告なし / 24,000B で警告あり・実バイト数: 24000・超過: 0）
            $boundaryTarget = New-TargetProject
            try {
                $bAgentsPath = Join-Path $boundaryTarget 'AGENTS.md'
                Write-Utf8NoBom $bAgentsPath "# Boundary Test`n"
                Invoke-Installer $boundaryTarget @{ Force = $true; SkipConfig = $true } | Out-Null
                Invoke-Installer $boundaryTarget @{ Force = $true; SkipConfig = $true } | Out-Null
                $syncedContent = Read-Utf8 $bAgentsPath
                $baseBytes = [IO.File]::ReadAllBytes($bAgentsPath).Length

                $pad23999 = 23999 - $baseBytes
                $pad23999 | Should -BeGreaterThan 0
                Write-Utf8NoBom $bAgentsPath (('A' * $pad23999) + $syncedContent)
                $out23999 = Invoke-Installer $boundaryTarget @{ Force = $true; SkipConfig = $true }
                [IO.File]::ReadAllBytes($bAgentsPath).Length | Should -Be 23999
                $out23999 | Should -Not -Match '\[warn\].*24,?000' -Because '23,999 バイトでは 24,000B 上限超過警告を出してはなりません'

                Write-Utf8NoBom $bAgentsPath (('A' * ($pad23999 + 1)) + $syncedContent)
                $out24000 = Invoke-Installer $boundaryTarget @{ Force = $true; SkipConfig = $true }
                [IO.File]::ReadAllBytes($bAgentsPath).Length | Should -Be 24000
                $out24000 | Should -Match '\[warn\].*24,?000' -Because '24,000 バイト以上では上限超過警告が必要です'
                $out24000 | Should -Match '実バイト数:\s*24000'
                $out24000 | Should -Match '超過:\s*0'
            }
            finally {
                Remove-Item -LiteralPath $boundaryTarget -Recurse -Force -ErrorAction SilentlyContinue
            }

            # UT-23: 管理区間外に 20,000B のテキストを持つ既存 AGENTS.md を再同期（合計 >= 24,000B）
            $largeCustom = "# Large Project Rules`n`n" + ('A' * 20000) + "`n"
            Write-Utf8NoBom $agentsPath $largeCustom
            $outWarn = Invoke-Installer $script:Target @{ Force = $true; SkipConfig = $true }
            $totalBytes = [IO.File]::ReadAllBytes($agentsPath).Length
            $totalBytes | Should -BeGreaterOrEqual 24000
            $outWarn | Should -Match "$totalBytes" -Because '実バイト数の出力が必要です'
            $outWarn | Should -Match "$(($totalBytes - 24000))" -Because '24,000 バイトからの超過バイト数の出力が必要です'
            $outWarn | Should -Match '(24,?000|分割|別ファイル|references)' -Because '上限超過と分割案内の警告が必要です'
        }

        It '[UT-24][IT-06] 破損マーカー AGENTS.md（<CaseName>）に対しては二重追記せずエラー終了し、元のファイル内容を保持する' -ForEach @(
            @{ CaseName = 'beginのみ'; Content = "# Project Rules`n`n<!-- openspec-kit:begin (install.ps1 により管理。手動編集は再同期で上書きされます) -->`n途中のルール（endマーカー欠損）`n" },
            @{ CaseName = 'endのみ'; Content = "# Project Rules`n`n<!-- openspec-kit:end -->`n" },
            @{ CaseName = '順序逆転(end先行後にbegin)'; Content = "# Project Rules`n`n<!-- openspec-kit:end -->`n途中`n<!-- openspec-kit:begin -->`n" },
            @{ CaseName = '同一行順序逆転(end ... begin)'; Content = "# Project Rules`n<!-- openspec-kit:end --> <!-- openspec-kit:begin -->`n" },
            @{ CaseName = '重複マーカー(begin ... end ... begin)'; Content = "# Project Rules`n<!-- openspec-kit:begin -->`nA`n<!-- openspec-kit:end -->`n<!-- openspec-kit:begin -->`n" },
            @{ CaseName = '重複マーカー(begin ... begin ... end)'; Content = "# Project Rules`n<!-- openspec-kit:begin -->`n<!-- openspec-kit:begin -->`nA`n<!-- openspec-kit:end -->`n" }
        ) {
            $agentsPath = Join-Path $script:Target 'AGENTS.md'
            Write-Utf8NoBom $agentsPath $Content

            { Invoke-Installer $script:Target } | Should -Throw -Because "破損マーカー ($CaseName) はエラー停止する必要があります"
            (Read-Utf8 $agentsPath) | Should -Be $Content -Because '破損した AGENTS.md を二重追記でさらに破壊してはなりません'
        }

        It '[UT-25][IT-06] BaseBranch と EvidenceDir に特殊文字 (&, |, \) が含まれていても壊れずリテラル展開される' {
            $specialBranch = 'feat/a&b|c\d'
            $specialEvidence = 'out&1/ev/'
            Invoke-Installer $script:Target @{ BaseBranch = $specialBranch; EvidenceDir = $specialEvidence } | Out-Null

            $config = Read-Utf8 (Join-Path $script:Target 'openspec/config.yaml')
            $config.Contains($specialBranch) | Should -BeTrue -Because 'config.yaml に特殊文字を含む BaseBranch がそのまま展開される必要があります'

            $agents = Read-Utf8 (Join-Path $script:Target 'AGENTS.md')
            $agents.Contains($specialBranch) | Should -BeTrue -Because 'AGENTS.md に特殊文字を含む BaseBranch がそのまま展開される必要があります'
            $agents.Contains($specialEvidence) | Should -BeTrue -Because 'AGENTS.md に特殊文字を含む EvidenceDir がそのまま展開される必要があります'

            $proposeRef = Read-Utf8 (Join-Path $script:Target '.agents/skills/sdd-propose/references/sdd-reference.md')
            $proposeRef.Contains($specialBranch) | Should -BeTrue -Because 'スキル内リファレンスにも特殊文字を含む BaseBranch がそのまま展開される必要があります'
        }

        It '[UT-25] 二重置換が起きず（BaseBranch={{EVIDENCE_DIR}}）、シングルクォート含有時も verify-gate.ps1 に構文エラーが生じない' {
            # 二重置換チェック
            $tDouble = New-TargetProject
            try {
                Invoke-Installer $tDouble @{ BaseBranch = '{{EVIDENCE_DIR}}'; EvidenceDir = 'out/ev/' } | Out-Null
                (Read-Utf8 (Join-Path $tDouble 'openspec/config.yaml')).Contains('ベースブランチ: {{EVIDENCE_DIR}}') | Should -BeTrue -Because 'BaseBranch に指定した {{EVIDENCE_DIR}} が EvidenceDir で二重置換されてはなりません'
                (Read-Utf8 (Join-Path $tDouble 'AGENTS.md')).Contains('git checkout {{EVIDENCE_DIR}}') | Should -BeTrue
                (Read-Utf8 (Join-Path $tDouble 'AGENTS.md')).Contains('out/ev/') | Should -BeTrue
                (Read-Utf8 (Join-Path $tDouble '.agents/skills/sdd-propose/references/sdd-reference.md')).Contains('git checkout {{EVIDENCE_DIR}}') | Should -BeTrue
            }
            finally {
                Remove-Item -LiteralPath $tDouble -Recurse -Force -ErrorAction SilentlyContinue
            }

            # シングルクォートエスケープ & verify-gate.ps1 構文解析
            $tQuote = New-TargetProject
            try {
                $quoteBranch = "feat/it's-branch"
                $quoteEvidence = "out/it's-ev/"
                Invoke-Installer $tQuote @{ BaseBranch = $quoteBranch; EvidenceDir = $quoteEvidence } | Out-Null

                $gateScript = Join-Path $tQuote 'openspec/scripts/verify-gate.ps1'
                $tokens = $null
                $parseErrors = $null
                [System.Management.Automation.Language.Parser]::ParseFile($gateScript, [ref]$tokens, [ref]$parseErrors) | Out-Null
                $parseErrors | Should -HaveCount 0 -Because 'シングルクォートを含む BaseBranch/EvidenceDir 展開後も verify-gate.ps1 の PowerShell 構文は有効である必要があります'
                (Read-Utf8 (Join-Path $tQuote 'openspec/config.yaml')).Contains($quoteBranch) | Should -BeTrue
                (Read-Utf8 (Join-Path $tQuote 'AGENTS.md')).Contains($quoteBranch) | Should -BeTrue
            }
            finally {
                Remove-Item -LiteralPath $tQuote -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It '[UT-25][IT-06] BaseBranch / EvidenceDir / AgentTargets に改行 (\n) が含まれる場合は書き込み前にエラー停止する' -ForEach @(
            @{ ParamName = 'BaseBranch'; Extra = @{ BaseBranch = "main`nfoo" } },
            @{ ParamName = 'EvidenceDir'; Extra = @{ EvidenceDir = "out/`nevid/" } },
            @{ ParamName = 'AgentTargets'; Extra = @{ AgentTargets = "claude`ncopilot" } }
        ) {
            { Invoke-Installer $script:Target $Extra } | Should -Throw -Because "$ParamName に改行が含まれる場合は事前エラー停止する必要があります"
            @(Get-ChildItem -LiteralPath $script:Target -Recurse -File) | Should -HaveCount 0
        }

        It '[IT-06] 配置予定ファイル位置（<ConflictPath>）に既存ディレクトリが存在する場合は前半ファイル書き込み前にエラー停止する' -ForEach @(
            @{ ConflictPath = '.claude/skills/sdd-propose/SKILL.md'; Extra = @{ AgentTargets = 'claude' } },
            @{ ConflictPath = 'CLAUDE.md'; Extra = @{} },
            @{ ConflictPath = 'openspec/config.yaml'; Extra = @{} }
        ) {
            New-Item -ItemType Directory -Path (Join-Path $script:Target $ConflictPath) -Force | Out-Null

            { Invoke-Installer $script:Target $Extra } | Should -Throw -Because "$ConflictPath が既存ディレクトリの場合は書き込み前にエラー停止する必要があります"
            Test-Path -LiteralPath (Join-Path $script:Target 'openspec/templates') | Should -BeFalse -Because 'ファイル配置前に衝突を検知して中断する必要があります'
            Test-Path -LiteralPath (Join-Path $script:Target 'AGENTS.md') | Should -BeFalse
        }

        It '[IT-07] 事前検証通過後にスキルファイル配置が ReadOnly 属性等で失敗した場合は停止し、旧 .agents/workflows/sdd-*.md が退避されて消滅しない' {
            $wfDir = Join-Path $script:Target '.agents/workflows'
            New-Item -ItemType Directory -Path $wfDir -Force | Out-Null
            $legacyPropose = Join-Path $wfDir 'sdd-propose.md'
            Write-Utf8NoBom $legacyPropose 'must-survive-on-copy-failure'

            $skillMd = Join-Path $script:Target '.agents/skills/sdd-propose/SKILL.md'
            Write-Utf8NoBom $skillMd 'readonly-skill'
            Set-ItemProperty -LiteralPath $skillMd -Name IsReadOnly -Value $true
            try {
                { Invoke-Installer $script:Target @{ AgentTargets = 'antigravity'; Force = $true; SkipConfig = $true } } | Should -Throw -Because 'ReadOnly スキルの上書き失敗時はエラー停止する必要があります'
                Test-Path -LiteralPath $legacyPropose | Should -BeTrue -Because 'スキルコピー失敗時は旧ワークフローを退避してはなりません'
                Test-Path -LiteralPath "$legacyPropose.bak" | Should -BeFalse
            }
            finally {
                if (Test-Path -LiteralPath $skillMd) {
                    Set-ItemProperty -LiteralPath $skillMd -Name IsReadOnly -Value $false
                }
            }
        }

        It '[IT-06][IT-07] 展開先（.claude または .claude/skills）がディレクトリではなく通常ファイルとして存在する場合は書き込み前にエラー停止し、旧 .agents/workflows/sdd-*.md を退避して消してしまわない' {
            $wfDir = Join-Path $script:Target '.agents/workflows'
            New-Item -ItemType Directory -Path $wfDir -Force | Out-Null
            $legacyPropose = Join-Path $wfDir 'sdd-propose.md'
            Write-Utf8NoBom $legacyPropose 'must-survive-on-failure'

            # .claude をディレクトリではなく通常ファイルとして作成（既定 auto でも事前検証されること）
            $claudeFile = Join-Path $script:Target '.claude'
            Write-Utf8NoBom $claudeFile 'not-a-directory'

            { Invoke-Installer $script:Target } | Should -Throw -Because '.claude が通常ファイルの場合は書き込み前にエラー停止する必要があります'
            Test-Path -LiteralPath (Join-Path $script:Target 'openspec/templates') | Should -BeFalse -Because '展開先パス種別検証はファイル書き込み前に行う必要があります'
            Test-Path -LiteralPath $legacyPropose | Should -BeTrue -Because 'スキル展開失敗時は旧 .agents/workflows/sdd-*.md を退避してはなりません'
            Test-Path -LiteralPath "$legacyPropose.bak" | Should -BeFalse
            (Read-Utf8 $claudeFile).Trim() | Should -Be 'not-a-directory'
        }

        It '[IT-08] 旧 .agents/workflows/sdd-*.md の退避（リネーム）がファイルロックで失敗した場合は対象パスと復旧案内を出してエラー終了する' {
            $wfDir = Join-Path $script:Target '.agents/workflows'
            New-Item -ItemType Directory -Path $wfDir -Force | Out-Null
            $lockedFile = Join-Path $wfDir 'sdd-propose.md'
            Write-Utf8NoBom $lockedFile 'locked-legacy-workflow'

            $fs = [System.IO.File]::Open($lockedFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            try {
                $errText = ''
                try {
                    Invoke-Installer $script:Target @{ Force = $true; SkipConfig = $true } | Out-Null
                }
                catch {
                    $errText = "$_"
                }
                Test-Path -LiteralPath (Join-Path $script:Target '.agents/skills/sdd-propose/SKILL.md') | Should -BeTrue -Because 'スキル配置成功後の後段退避ステップで検査される必要があります'
                $errText | Should -Not -BeNullOrEmpty -Because '退避リネーム失敗時はエラー停止する必要があります'
                $errText | Should -Match 'sdd-propose\.md' -Because '失敗した対象パスの明示が必要です'
                $errText | Should -Match '(退避|バックアップ|\.bak|手動|リネーム|削除)' -Because '退避失敗時の復旧案内が必要です'
            }
            finally {
                $fs.Dispose()
            }
        }
    }
}
