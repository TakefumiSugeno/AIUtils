#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# openspec-kit/agents ロール定義のテスト（Pester 5+）
#   実行: Import-Module Pester -MinimumVersion 5.0; Invoke-Pester ./tests/openspec-kit.agents-skills.Tests.ps1 -Output Detailed

BeforeDiscovery {
    $script:AllAgents = @(
        'user-reviewer',
        'se-reviewer',
        'pg-reviewer',
        'qa-reviewer',
        'qa-tester',
        'pg-implementer'
    )
    $script:ReadOnlyReviewers = @(
        'user-reviewer',
        'se-reviewer',
        'pg-reviewer'
    )
    $script:HydrogenRoles = @(
        @{ Role = 'qa-tester'; Thinking = 'high' },
        @{ Role = 'pg-implementer'; Thinking = 'medium' }
    )
}

BeforeAll {
    $script:KitRoot = Join-Path $PSScriptRoot '..\openspec-kit' | Resolve-Path
    $script:KitAgents = Join-Path $script:KitRoot 'agents' | Resolve-Path

    function Read-Utf8([string]$Path) {
        return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
    }

    function ConvertFrom-AgentMarkdown([string]$Raw, [string]$Path = '') {
        $match = [regex]::Match($Raw, '(?s)\A---\r?\n(.*?)\r?\n---(?:\r?\n(.*))?\z')
        if (-not $match.Success) {
            return @{
                Path           = $Path
                HasFrontmatter = $false
                RawFrontmatter = ''
                Frontmatter    = @{}
                Body           = $Raw
                Raw            = $Raw
            }
        }

        $rawFrontmatter = $match.Groups[1].Value
        $body = if ($match.Groups[2].Success) { $match.Groups[2].Value } else { '' }

        $meta = @{}
        foreach ($line in ($rawFrontmatter -split '\r?\n')) {
            # インデントされたネスト行・複数行ブロック継続行・空行・コメント行はトップレベルキーから除外
            if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^\s' -or $line.StartsWith('#')) {
                continue
            }

            $kv = [regex]::Match($line, '^([A-Za-z0-9_-]+)\s*:\s*(.*)$')
            if (-not $kv.Success) {
                continue
            }

            $key = $kv.Groups[1].Value
            $rawVal = $kv.Groups[2].Value.Trim()

            if ($rawVal -match '^"((?:[^"\\]|\\.)*)"(?:\s+#.*)?$') {
                $val = $Matches[1] -replace '\\"', '"' -replace '\\\\', '\'
            }
            elseif ($rawVal -match "^'((?:[^']|'')*)'(?:\s+#.*)?$") {
                $val = $Matches[1] -replace "''", "'"
            }
            else {
                $val = ($rawVal -replace '\s+#.*$', '').Trim()
            }

            $meta[$key] = $val
        }

        return @{
            Path           = $Path
            HasFrontmatter = $true
            RawFrontmatter = $rawFrontmatter
            Frontmatter    = $meta
            Body           = $body
            Raw            = $Raw
        }
    }

    function Get-ParsedAgent([string]$RoleName) {
        $path = Join-Path $script:KitAgents "$RoleName.md"
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "エージェント定義ファイルが見つかりません: $path"
        }

        return ConvertFrom-AgentMarkdown -Raw (Read-Utf8 $path) -Path $path
    }

    function Get-MarkdownLogicalBlocks([string]$Body) {
        $blocks = [System.Collections.Generic.List[string]]::new()
        $current = [System.Collections.Generic.List[string]]::new()

        foreach ($line in ($Body -split '\r?\n')) {
            $isBoundary = [string]::IsNullOrWhiteSpace($line) -or ($line -match '^(?:#|[-*]\s+)')
            if ($isBoundary -and $current.Count -gt 0) {
                $blocks.Add(($current -join "`n"))
                $current.Clear()
            }
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                $current.Add($line)
            }
        }
        if ($current.Count -gt 0) {
            $blocks.Add(($current -join "`n"))
        }

        return $blocks
    }

    function Test-HasSingleWriterReturnContract {
        param(
            [Parameter(Mandatory)][string]$Body,
            [Parameter(Mandatory)][string[]]$ForbiddenFiles,
            [switch]$RequireReviewRecordFormat
        )

        # 否定反転・直接書き込み肯定表現が含まれる場合は不正とみなす
        $forbiddenPattern = ($ForbiddenFiles | ForEach-Object { [regex]::Escape($_) }) -join '|'
        if ($Body -match "(読み取り専用では?ない|直接(?:編集|書き込み|書き換え)(?:を?行(?:う|います)|する)|親(?:エージェント)?(?:へ|に)(?:は)?返却しない|(?:$forbiddenPattern).{0,25}(?:直接)?(?:編集|書き込|書き換)(?:む|みます|んで|う))") {
            return $false
        }

        foreach ($block in (Get-MarkdownLogicalBlocks $Body)) {
            $sentences = $block -split '[。\r\n]+'
            $allFilesDeniedInSentence = $true
            foreach ($file in $ForbiddenFiles) {
                $esc = [regex]::Escape($file)
                $deniedInSameSentence = $false
                foreach ($sentence in $sentences) {
                    if ($sentence -match $esc -and $sentence -match '(?:編集|書き込|書き換).*?(?:一切)?(?:行わない|行わず|しない|せず|禁止|不可)') {
                        $deniedInSameSentence = $true
                        break
                    }
                }
                if (-not $deniedInSameSentence) {
                    $allFilesDeniedInSentence = $false
                    break
                }
            }
            if (-not $allFilesDeniedInSentence) {
                continue
            }

            $hasParentReturn = $block -match '(?:親エージェント|司令塔|Orchestrator).{0,25}(?:返却(?!しない|せず)|返す(?!ことはない))'
            if (-not $hasParentReturn) {
                continue
            }

            if ($RequireReviewRecordFormat) {
                if ($block -match 'review_record\.md' -and $block -match '(?:レビュー|結果|記録).{0,15}テキスト') {
                    return $true
                }
            }
            elseif ($block -match '(?:サマリ|結果)') {
                return $true
            }
        }

        return $false
    }

    function Get-DeprecatedGemini38Violations([hashtable]$Agent, [string]$Label) {
        $violations = [System.Collections.Generic.List[string]]::new()

        foreach ($entry in $Agent.Frontmatter.GetEnumerator()) {
            if ($entry.Value -match '(?i)(3\.8|gemini[-_\s]*3\.8)') {
                $violations.Add("$Label frontmatter [$($entry.Key)=$($entry.Value)]")
            }
        }

        foreach ($line in ($Agent.RawFrontmatter -split '\r?\n')) {
            $trimmed = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) {
                continue
            }
            if ($line -match '(?i)(gemini[-_\s]*3\.8|3\.8[-_\s]*flash)') {
                $violations.Add("$Label raw-frontmatter: $trimmed")
            }
        }

        foreach ($line in ($Agent.Body -split '\r?\n')) {
            if ($line -match '(?i)(gemini[-_\s]*3\.8|3\.8[-_\s]*flash)') {
                $hasAffirmativeAdoption = $line -match '(?<!非)(?:推奨(?!しない|せず|されない)|採用(?!しない|せず|されない)|使用(?!しない|せず|されない)|利用(?!しない|せず|されない)|指定(?!しない|せず|されない)|割り当て(?!ない|ず|られない)|model_tier)'
                $hasDeprecationOrExclusion = $line -match '(非推奨|deprecated|廃止|利用しない|使用しない|採用しない|推奨しない|指定しない|割り当てない|除外|比較)'
                if ($hasAffirmativeAdoption -or -not $hasDeprecationOrExclusion) {
                    $violations.Add("$Label body: $line")
                }
            }
        }

        return $violations
    }
}

Describe 'openspec-kit/agents ロール定義' {
    It '全6ロール定義ファイルのみが存在する' {
        $actual = Get-ChildItem -LiteralPath $script:KitAgents -File |
            ForEach-Object { $_.BaseName } |
            Sort-Object
        $expected = @('pg-implementer', 'pg-reviewer', 'qa-reviewer', 'qa-tester', 'se-reviewer', 'user-reviewer')
        $actual | Should -Be $expected
    }

    It '<_> は有効な YAML frontmatter と既存キー (name, description, role) およびモデル・権限メタデータを保持している' -ForEach $script:AllAgents {
        $agent = Get-ParsedAgent $_
        $agent.HasFrontmatter | Should -BeTrue
        $agent.Frontmatter['name'] | Should -Be $_
        [string]::IsNullOrWhiteSpace($agent.Frontmatter['description']) | Should -BeFalse
        [string]::IsNullOrWhiteSpace($agent.Frontmatter['role']) | Should -BeFalse
        $agent.Frontmatter['model_tier'] | Should -BeIn @('pro', 'flash', 'flash_lite')
        $agent.Frontmatter['thinking'] | Should -BeIn @('high', 'medium', 'low')
        $agent.Frontmatter['write_tools'] | Should -BeIn @('true', 'false')
    }

    It '[UT-13] <_> は model_tier: pro, thinking: high, write_tools: false を宣言し、ファイル非編集と親への review_record.md 形式テキスト返却契約を明記している' -ForEach $script:ReadOnlyReviewers {
        $agent = Get-ParsedAgent $_
        $agent.Frontmatter['model_tier'] | Should -Be 'pro'
        $agent.Frontmatter['thinking'] | Should -Be 'high'
        $agent.Frontmatter['write_tools'] | Should -Be 'false'

        $hasReadOnlyMarker = ($agent.Body -match '(読み取り専用|Read-only)') -and ($agent.Body -notmatch '読み取り専用では?ない')
        $hasReadOnlyMarker | Should -BeTrue -Because "$_ の本文に読み取り専用（Read-only）の明記が必要です"

        $hasContract = Test-HasSingleWriterReturnContract -Body $agent.Body -ForbiddenFiles @('reviews.md') -RequireReviewRecordFormat
        $hasContract | Should -BeTrue -Because "$_ の本文同一項目内にファイル/reviews.md 非編集と親エージェントへの review_record.md 形式テキスト返却契約が必要です"
    }

    It '[UT-14] qa-reviewer は model_tier: pro, thinking: high, write_tools: true と単一ライター・既存コード非改変契約を宣言している' {
        $agent = Get-ParsedAgent 'qa-reviewer'
        $agent.Frontmatter['model_tier'] | Should -Be 'pro'
        $agent.Frontmatter['thinking'] | Should -Be 'high'
        $agent.Frontmatter['write_tools'] | Should -Be 'true'

        $hasNoCodeTamper = $agent.Body -match '(?:既存テスト|プロダクションコード).{0,30}(?:改変|変更|編集).{0,20}(?:行わない|行わず|しない|せず|禁止|不可)'
        $hasNoCodeTamper | Should -BeTrue -Because 'qa-reviewer の本文に既存テスト・プロダクションコードの非改変契約が必要です'

        $hasContract = Test-HasSingleWriterReturnContract -Body $agent.Body -ForbiddenFiles @('reviews.md') -RequireReviewRecordFormat
        $hasContract | Should -BeTrue -Because 'qa-reviewer の本文同一項目内に reviews.md 非書き込みと親エージェントへの review_record.md 形式テキスト返却契約が必要です'
    }

    It '[UT-15] <Role> は model_tier: flash, thinking: <Thinking>, write_tools: true と単一ライター契約を宣言している' -ForEach $script:HydrogenRoles {
        $agent = Get-ParsedAgent $Role
        $agent.Frontmatter['model_tier'] | Should -Be 'flash'
        $agent.Frontmatter['thinking'] | Should -Be $Thinking
        $agent.Frontmatter['write_tools'] | Should -Be 'true'

        $hasContract = Test-HasSingleWriterReturnContract -Body $agent.Body -ForbiddenFiles @('tasks.md', 'reviews.md')
        $hasContract | Should -BeTrue -Because "$Role の本文同一項目内に tasks.md / reviews.md 非書き込みと親エージェントへの結果サマリ返却契約が必要です"
    }

    It '[UT-19] openspec-kit/agents/ 配下でアクティブな推奨・設定値として Gemini 3.8 Flash が割り当てられていない' {
        $files = Get-ChildItem -LiteralPath $script:KitAgents -Filter '*.md' -File
        $violations = @()
        foreach ($file in $files) {
            $agent = Get-ParsedAgent $file.BaseName
            $violations += Get-DeprecatedGemini38Violations -Agent $agent -Label $file.Name
        }
        $violations | Should -BeNullOrEmpty
    }
}
