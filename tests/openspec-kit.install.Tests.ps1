#Requires -Modules Pester
# openspec-kit/install.ps1 のテスト（Pester 5）
#   実行: Invoke-Pester ./tests/openspec-kit.install.Tests.ps1 -Output Detailed

BeforeAll {
    $script:Installer = Join-Path $PSScriptRoot '..\openspec-kit\install.ps1' | Resolve-Path
    $script:KitTemplates = Join-Path $PSScriptRoot '..\openspec-kit\templates' | Resolve-Path

    function New-TargetProject {
        $dir = Join-Path ([IO.Path]::GetTempPath()) ("osk-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $dir 'openspec') -Force | Out-Null
        return $dir
    }

    function Invoke-Installer([string]$Target, [hashtable]$Extra = @{}) {
        & $script:Installer -TargetPath $Target @Extra 6>$null | Out-Null
    }

    function Read-Utf8([string]$Path) { [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) }
}

Describe 'install.ps1' {
    BeforeEach { $script:Target = New-TargetProject }
    AfterEach { Remove-Item -LiteralPath $script:Target -Recurse -Force -ErrorAction SilentlyContinue }

    It 'openspec/ がない場合は失敗する' {
        $empty = Join-Path ([IO.Path]::GetTempPath()) ("osk-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $empty | Out-Null
        try { { & $script:Installer -TargetPath $empty 6>$null } | Should -Throw '*openspec init*' }
        finally { Remove-Item -LiteralPath $empty -Recurse -Force }
    }

    Context '新規導入' {
        BeforeEach { Invoke-Installer $script:Target @{ BaseBranch = 'trunk'; EvidenceDir = 'out/evidence/' } }

        It '全テンプレートを配置する' {
            $expected = Get-ChildItem $script:KitTemplates -File | ForEach-Object Name | Sort-Object
            $actual = Get-ChildItem (Join-Path $script:Target 'openspec/templates') -File | ForEach-Object Name | Sort-Object
            $actual | Should -Be $expected
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

        It 'BOM なし UTF-8 で書き込む' {
            $bytes = [IO.File]::ReadAllBytes((Join-Path $script:Target 'AGENTS.md'))
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB) | Should -BeFalse
        }
    }

    Context '既存ファイルがある場合' {
        It '既存 AGENTS.md の末尾に管理区間を追記し、既存内容を保持する' {
            Set-Content -LiteralPath (Join-Path $script:Target 'AGENTS.md') -Value "# 既存`n`n独自ルール" -Encoding utf8
            Invoke-Installer $script:Target
            $agents = Read-Utf8 (Join-Path $script:Target 'AGENTS.md')
            $agents | Should -Match '独自ルール'
            $agents | Should -Match 'openspec-kit:begin'
        }

        It '再実行（-Force）しても管理区間は1つのまま（冪等）で区間外は保持される' {
            Invoke-Installer $script:Target
            $path = Join-Path $script:Target 'AGENTS.md'
            Set-Content -LiteralPath $path -Value ((Read-Utf8 $path) + "`n## 追記セクション`n") -Encoding utf8
            Invoke-Installer $script:Target @{ Force = $true }
            $first = Read-Utf8 $path
            Invoke-Installer $script:Target @{ Force = $true }
            $second = Read-Utf8 $path
            $second | Should -Be $first
            ([regex]::Matches($second, 'openspec-kit:begin')).Count | Should -Be 1
            $second | Should -Match '## 追記セクション'
        }

        It '既存 config.yaml は上書きせず config.kit.yaml を出力する' {
            $config = Join-Path $script:Target 'openspec/config.yaml'
            Set-Content -LiteralPath $config -Value 'schema: spec-driven' -Encoding utf8
            Invoke-Installer $script:Target
            (Get-Content $config -Raw).Trim() | Should -Be 'schema: spec-driven'
            Join-Path $script:Target 'openspec/config.kit.yaml' | Should -Exist
        }

        It '-OverwriteConfig はバックアップを作成して上書きする' {
            $config = Join-Path $script:Target 'openspec/config.yaml'
            Set-Content -LiteralPath $config -Value 'schema: spec-driven' -Encoding utf8
            Invoke-Installer $script:Target @{ OverwriteConfig = $true }
            Get-ChildItem (Join-Path $script:Target 'openspec') -Filter 'config.yaml.bak-*' | Should -HaveCount 1
            Read-Utf8 $config | Should -Match 'reviews:'
        }

        It '-SkipConfig は config を一切出力しない' {
            Invoke-Installer $script:Target @{ SkipConfig = $true }
            Join-Path $script:Target 'openspec/config.yaml' | Should -Not -Exist
            Join-Path $script:Target 'openspec/config.kit.yaml' | Should -Not -Exist
        }

        It '既存テンプレートは -Force なしではスキップする' {
            $tpl = Join-Path $script:Target 'openspec/templates/review_record.md'
            New-Item -ItemType Directory -Path (Split-Path $tpl) -Force | Out-Null
            Set-Content -LiteralPath $tpl -Value 'custom' -Encoding utf8
            Invoke-Installer $script:Target
            (Get-Content $tpl -Raw).Trim() | Should -Be 'custom'
        }

        It '.gitignore に登録済みなら重複追記しない' {
            Invoke-Installer $script:Target
            Invoke-Installer $script:Target
            @(Get-Content (Join-Path $script:Target '.gitignore') | Where-Object { $_ -eq 'test/TestResults/' }) | Should -HaveCount 1
        }
    }

    It '-WhatIf では何も書き込まない' {
        & $script:Installer -TargetPath $script:Target -WhatIf 6>$null | Out-Null
        @(Get-ChildItem -LiteralPath $script:Target -Recurse -File) | Should -HaveCount 0
    }
}
