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

# =============================================================================
# Group 2: 5エージェント共通 Skills 化・Antigravity オーケストレーション・AGENTS.openspec.md スリム化
#   正本: openspec/changes/optimize-agy-models-and-skills/{specs,design.md,test_plan.md}
#   対象: UT-01, UT-02, UT-12, UT-16, UT-17, UT-18, UT-19, UT-20, UT-21, UT-26, IT-05
# =============================================================================

BeforeDiscovery {
    $script:SddSkillCases = @(
        @{ Skill = 'sdd-propose' },
        @{ Skill = 'sdd-apply' },
        @{ Skill = 'sdd-archive' }
    )
    $script:ReviewScriptCases = @(
        @{
            Skill  = 'sdd-propose'
            Script = 'run_propose_review.py'
            Roles  = @('user-reviewer', 'se-reviewer')
            Phase  = 'Propose Review'
        },
        @{
            Skill  = 'sdd-archive'
            Script = 'run_archive_review.py'
            Roles  = @('user-reviewer', 'se-reviewer', 'pg-reviewer', 'qa-reviewer')
            Phase  = 'Archive Review'
        }
    )
    $script:ReferencedAssetCases = @(
        @{
            Skill      = 'sdd-propose'
            Agents     = @('user-reviewer', 'se-reviewer')
            Checklists = @('checklist_propose')
        },
        @{
            Skill      = 'sdd-apply'
            Agents     = @('qa-tester', 'pg-implementer', 'pg-reviewer', 'qa-reviewer')
            Checklists = @('checklist_apply_impl', 'checklist_apply_test')
        },
        @{
            Skill      = 'sdd-archive'
            Agents     = @('user-reviewer', 'se-reviewer', 'pg-reviewer', 'qa-reviewer')
            Checklists = @('checklist_archive')
        }
    )
}

BeforeAll {
    # NOTE: ここで例外を投げると Group 1 まで巻き込んで失敗するため、未実装リソースの解決は It 内で行う
    $script:KitRootPath = [string]$script:KitRoot
    $script:KitSkills = Join-Path $script:KitRootPath 'skills'

    # UT-17: run_workflow 組み込み関数（phase / agent / parallel / log / args）のスタブを注入して実行するハーネス
    $script:HarnessSource = @'
import json
import runpy
import sys
import traceback

script_path = sys.argv[1]
raw_arg = sys.argv[2]
if raw_arg.startswith("JSON:"):
    injected_args = json.loads(raw_arg[5:])
else:
    injected_args = {"change_name": raw_arg}

calls = {"phase": [], "agent": [], "parallel": 0, "log": []}
state = {"in_parallel": 0, "in_phase": 0}


class _Ctx:
    def __enter__(self):
        state["in_phase"] += 1
        return self

    def __exit__(self, *exc):
        state["in_phase"] -= 1
        return False


def phase(name=None, *a, **k):
    calls["phase"].append(str(name))
    return _Ctx()


def log(*a, **k):
    calls["log"].append(" ".join(str(x) for x in a))


def agent(prompt=None, schema=None, role=None, model=None, **kw):
    calls["agent"].append({
        "prompt": prompt,
        "schema": schema,
        "role": role,
        "model": model,
        "in_parallel": state["in_parallel"] > 0,
        "in_phase": state["in_phase"] > 0,
    })
    return "stub-result-" + str(role)


def parallel(*a, **k):
    calls["parallel"] += 1
    state["in_parallel"] += 1
    try:
        first = a[0] if a else next(iter(k.values()), [])
        items = list(first)
        if len(a) > 1 and callable(a[1]):
            return [a[1](i) for i in items]
        return [i() if callable(i) else i for i in items]
    finally:
        state["in_parallel"] -= 1


result = {"error": None, "exit": None}
try:
    runpy.run_path(
        script_path,
        init_globals={
            "phase": phase,
            "agent": agent,
            "parallel": parallel,
            "log": log,
            "args": injected_args,
        },
        run_name="__main__",
    )
except SystemExit as e:
    result["exit"] = e.code
except BaseException:
    result["error"] = traceback.format_exc()

print("HARNESS_RESULT:" + json.dumps({"calls": calls, "result": result}, ensure_ascii=False, default=str))
'@
    $script:HarnessPath = Join-Path ([IO.Path]::GetTempPath()) ("sdd-stub-harness-{0}.py" -f [guid]::NewGuid().ToString('N'))
    [IO.File]::WriteAllText($script:HarnessPath, $script:HarnessSource, (New-Object System.Text.UTF8Encoding($false)))

    function Get-SkillDir([string]$Skill) {
        return (Join-Path $script:KitSkills $Skill)
    }

    function Get-SkillFiles([string]$Skill, [string]$Filter = '*') {
        $dir = Get-SkillDir $Skill
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
            throw "スキルディレクトリが存在しません: $dir"
        }
        return @(Get-ChildItem -LiteralPath $dir -Recurse -File -Filter $Filter)
    }

    function Get-FrontmatterValue([hashtable]$Parsed, [string]$Key) {
        $lines = $Parsed.RawFrontmatter -split '\r?\n'
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $m = [regex]::Match($lines[$i], "^$([regex]::Escape($Key))\s*:\s*(.*)$")
            if (-not $m.Success) { continue }
            $v = $m.Groups[1].Value.Trim()
            if ($v -match '^[>|][+-]?\s*$') {
                $parts = [System.Collections.Generic.List[string]]::new()
                for ($j = $i + 1; $j -lt $lines.Count; $j++) {
                    if ($lines[$j] -match '^\s+\S') { $parts.Add($lines[$j].Trim()) }
                    elseif ([string]::IsNullOrWhiteSpace($lines[$j])) { continue }
                    else { break }
                }
                return ($parts -join ' ')
            }
            return [string]$Parsed.Frontmatter[$Key]
        }
        return ''
    }

    function Get-MarkdownLinkTargets([string]$Raw) {
        $noCode = [regex]::Replace($Raw, '(?s)```.*?```', '')
        $targets = [System.Collections.Generic.List[string]]::new()
        foreach ($m in [regex]::Matches($noCode, '!?\[[^\]]*\]\(\s*([^)\s]+)(?:\s+"[^"]*")?\s*\)')) {
            $t = $m.Groups[1].Value.Trim('<', '>')
            if ($t -match '^[A-Za-z][A-Za-z0-9+.-]*:' -or $t.StartsWith('#')) { continue }
            $t = ($t -split '[#?]')[0]
            if ([string]::IsNullOrWhiteSpace($t)) { continue }
            $targets.Add($t)
        }
        return $targets
    }

    # 相対リンクがスキルディレクトリ内に実在し、親ディレクトリ外を参照していないことを検査する
    function Get-SkillLinkViolations([string]$Skill, [System.IO.FileInfo]$MarkdownFile) {
        $skillDir = [IO.Path]::GetFullPath((Get-SkillDir $Skill)).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        $violations = [System.Collections.Generic.List[string]]::new()
        foreach ($t in (Get-MarkdownLinkTargets (Read-Utf8 $MarkdownFile.FullName))) {
            if ($t -match '(^|[\\/])\.\.([\\/]|$)') {
                $violations.Add("$($MarkdownFile.Name): 親ディレクトリセグメント(..)を含む相対リンク禁止 [$t]")
                continue
            }
            $resolved = [IO.Path]::GetFullPath((Join-Path $MarkdownFile.DirectoryName $t))
            if (-not $resolved.StartsWith($skillDir, [StringComparison]::OrdinalIgnoreCase)) {
                $violations.Add("$($MarkdownFile.Name): スキル外参照 [$t]")
            }
            elseif (-not (Test-Path -LiteralPath $resolved)) {
                $violations.Add("$($MarkdownFile.Name): リンク先不在 [$t]")
            }
        }
        return $violations
    }

    function Invoke-PythonProcess([string[]]$Arguments, [int]$TimeoutSec = 60) {
        # python3 は WindowsApps エイリアスで失敗するため python を使用する
        $py = (Get-Command python -ErrorAction Stop).Source
        $psi = [System.Diagnostics.ProcessStartInfo]::new($py)
        foreach ($a in $Arguments) { $psi.ArgumentList.Add($a) }
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
        $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
        $psi.Environment['PYTHONUTF8'] = '1'
        $psi.Environment['PYTHONIOENCODING'] = 'utf-8'
        $proc = [System.Diagnostics.Process]::Start($psi)
        $proc.StandardInput.Close()
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()
        if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
            $proc.Kill($true)
            throw "python 実行がタイムアウトしました: $($Arguments -join ' ')"
        }
        $proc.WaitForExit()
        return [pscustomobject]@{
            ExitCode = $proc.ExitCode
            StdOut   = $outTask.Result
            StdErr   = $errTask.Result
        }
    }

    function Get-ReviewScriptPath([string]$Skill, [string]$Script) {
        $path = Join-Path (Join-Path (Get-SkillDir $Skill) 'scripts') $Script
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "run_workflow 用スクリプトが存在しません: $path"
        }
        return $path
    }

    function Invoke-ReviewHarness([string]$ScriptPath, [string]$ChangeName = 'sample-change', [string]$ArgsJson = '') {
        $argSpec = if ([string]::IsNullOrEmpty($ArgsJson)) { $ChangeName } else { "JSON:$ArgsJson" }
        $r = Invoke-PythonProcess @($script:HarnessPath, $ScriptPath, $argSpec)
        $line = ($r.StdOut -split '\r?\n' | Where-Object { $_ -like 'HARNESS_RESULT:*' } | Select-Object -Last 1)
        if (-not $line) {
            throw "ハーネス出力が得られませんでした。ExitCode=$($r.ExitCode) StdErr=$($r.StdErr)"
        }
        return ($line.Substring('HARNESS_RESULT:'.Length) | ConvertFrom-Json)
    }

    function Test-HasOrchestrationSingleWriterPrinciple([string]$Raw) {
        # 否定・反転文脈（「親エージェントのみではなく」「サブエージェントも直接編集する」等）が含まれる場合は無条件で拒否
        if ($Raw -match '(?:親エージェント|司令塔|Orchestrator)(?:\([^)]*\)|（[^）]*）)?\s*(?:のみ|だけ)\s*(?:では?なく|では?ない)' -or
            $Raw -match 'サブエージェント(?:も|が).{0,25}(?:直接)?(?:編集|書き込|書き換)(?:む|みます|んで|う|する)' -or
            $Raw -match '(?:reviews\.md|tasks\.md).{0,25}サブエージェント.{0,15}(?:編集|書き込|書き換)(?:む|みます|んで|う|する)' -or
            $Raw -match '(?:親エージェント|司令塔|Orchestrator)(?:へ|に)(?:は)?返却(?:しない|せず)') {
            return $false
        }

        foreach ($block in (Get-MarkdownLogicalBlocks $Raw)) {
            $hasTargetFiles = ($block -match 'reviews\.md' -and $block -match 'tasks\.md')
            $hasParentOnlyWrite = $block -match '(?:親エージェント|司令塔|Orchestrator)(?:\([^)]*\)|（[^）]*）)?(?:のみ|だけ)(?!では?なく|では?ない).{0,25}(?:行い|行う|書き込|編集|更新)|(?:書き込|編集|更新).{0,25}(?:親エージェント|司令塔|Orchestrator)(?:\([^)]*\)|（[^）]*）)?(?:のみ|だけ)(?!では?なく|では?ない)'
            $hasSubagentNoDirectWrite = $block -match 'サブエージェント.{0,35}(?:編集|書き込|書き換)(?:まず|まない|せず|しない|禁止|行わない|行わず)'
            $hasReturnToParent = $block -match '(?:レビュー結果|テキスト|サマリ).{0,35}(?:親エージェント|司令塔|Orchestrator).{0,15}(?:返却(?!しない|せず)|返す(?!ことはない))'
            if ($hasTargetFiles -and $hasParentOnlyWrite -and $hasSubagentNoDirectWrite -and $hasReturnToParent) {
                return $true
            }
        }
        return $false
    }

    function Get-LegacyWorkflowReferenceViolations([string]$FileName, [string]$Raw) {
        $violations = [System.Collections.Generic.List[string]]::new()
        $isYaml = ($FileName -match '\.ya?ml$')
        foreach ($line in ($Raw -split '\r?\n')) {
            if ($line -notmatch 'workflows/sdd-') { continue }

            if ($isYaml) {
                # YAML 設定ファイルでは、非コメント部分（# 以前のキー・値）に workflows/sdd- が含まれていれば無条件で違反
                $nonComment = $line -replace '#.*$', ''
                if ($nonComment -match 'workflows/sdd-') {
                    $violations.Add("$FileName (YAML設定値): $($line.Trim())")
                    continue
                }
            }

            # 肯定的な利用文脈（「移行後の標準手順として workflows/sdd- を使う」等）が含まれる場合は違反
            $hasAffirmativeUse = $line -match '(?:移行後|標準(?:手順)?|現行|推奨|通常)[^\r\n]{0,40}workflows/sdd-|workflows/sdd-[^\r\n]{0,30}(?:を使(?:う|い|用)|を実行|を参照|で実行)'
            # 単なる「移行」1語では免除せず、「旧/レガシー + 退避/.bak/廃止/削除/非推奨」の退避説明文脈のみ許容
            $isRetirementNote = ($line -match '(?:旧|レガシー|legacy)[^\r\n]{0,45}workflows/sdd-' -and
                $line -match '(?:退避|\.bak|廃止|削除|非推奨|deprecated)')
            if ($hasAffirmativeUse -or -not $isRetirementNote) {
                $violations.Add("${FileName}: $($line.Trim())")
            }
        }
        return $violations
    }
}

AfterAll {
    if ($script:HarnessPath -and (Test-Path -LiteralPath $script:HarnessPath)) {
        Remove-Item -LiteralPath $script:HarnessPath -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Group 2-A: openspec-kit/skills スキル構造・自己完結・非衝突' {
    It '[UT-02] openspec-kit/skills/ には sdd-propose, sdd-apply, sdd-archive のみが存在し、openspec-* / opsx-* を含まない' {
        $dirs = @(Get-ChildItem -LiteralPath $script:KitSkills -Directory | ForEach-Object { $_.Name } | Sort-Object)
        $dirs | Should -Be @('sdd-apply', 'sdd-archive', 'sdd-propose')
        $files = @(Get-ChildItem -LiteralPath $script:KitSkills -File)
        $files.Count | Should -Be 0 -Because 'skills/ 直下にスキル以外のファイルを置かない'
        foreach ($d in $dirs) {
            $d | Should -Not -Match '(?i)openspec|opsx' -Because "$d は openspec init/update 生成物と名前衝突してはならない"
            $d | Should -Match '^sdd-'
        }
    }

    It '[UT-01] <Skill> の SKILL.md は frontmatter name がディレクトリ名と一致し、description が非空である' -ForEach $script:SddSkillCases {
        $path = Join-Path (Get-SkillDir $Skill) 'SKILL.md'
        Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue -Because "$path が必要です"
        $parsed = ConvertFrom-AgentMarkdown -Raw (Read-Utf8 $path) -Path $path
        $parsed.HasFrontmatter | Should -BeTrue
        $parsed.Frontmatter['name'] | Should -Be $Skill
        [string]::IsNullOrWhiteSpace((Get-FrontmatterValue $parsed 'description')) | Should -BeFalse -Because 'description（発動条件）が必要です'
    }

    It '[UT-01] <Skill> は references/sdd-reference.md と references/antigravity-orchestration.md を自己完結で保持し、SKILL.md からリンクされている' -ForEach $script:SddSkillCases {
        $dir = Get-SkillDir $Skill
        foreach ($ref in @('sdd-reference.md', 'antigravity-orchestration.md')) {
            $p = Join-Path (Join-Path $dir 'references') $ref
            Test-Path -LiteralPath $p -PathType Leaf | Should -BeTrue -Because "$p が必要です"
            (Get-Item -LiteralPath $p).Length | Should -BeGreaterThan 0
        }
        $skillMd = Join-Path $dir 'SKILL.md'
        Test-Path -LiteralPath $skillMd -PathType Leaf | Should -BeTrue
        $targets = @(Get-MarkdownLinkTargets (Read-Utf8 $skillMd) | ForEach-Object { $_ -replace '^\./', '' })
        $targets | Should -Contain 'references/sdd-reference.md'
        $targets | Should -Contain 'references/antigravity-orchestration.md'
    }

    It '[UT-01][IT-05] <Skill> 配下の全 Markdown の相対リンク先がすべてスキルディレクトリ内に実在し、親ディレクトリ外を参照していない' -ForEach $script:SddSkillCases {
        $mdFiles = @(Get-SkillFiles $Skill '*.md')
        ($mdFiles | Where-Object { $_.Name -eq 'SKILL.md' }).Count | Should -Be 1
        $violations = @()
        foreach ($f in $mdFiles) {
            $violations += Get-SkillLinkViolations -Skill $Skill -MarkdownFile $f
        }
        $violations | Should -BeNullOrEmpty
    }

    It '[UT-20] <Skill> の SKILL.md は非 Antigravity 環境（Claude Code 等）向けの標準サブエージェント/直列実行フォールバック手順を含む' -ForEach $script:SddSkillCases {
        $path = Join-Path (Get-SkillDir $Skill) 'SKILL.md'
        Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue
        $raw = Read-Utf8 $path
        $raw | Should -Match '(フォールバック|(?i:fallback))' -Because 'フォールバック手順の明記が必要です'
        $raw | Should -Match '(Claude Code|Copilot|OpenCode|Hermes)' -Because '非 Antigravity エージェントの明示が必要です'
        $raw | Should -Match '(直列|独立(した)?コンテキスト)' -Because '独立コンテキストでの直列実行フォールバックが必要です'
        $raw | Should -Match '(サブエージェント|\.claude/agents)' -Because '各エージェント標準のサブエージェント機構への言及が必要です'
    }
}

Describe 'Group 2-B: Antigravity オーケストレーションガイドと run_workflow 用 Python スクリプト' {
    It '[UT-16] <Skill> の antigravity-orchestration.md は define_subagent(EnableWriteTools)・invoke_subagent(Model 明示)・単一ライター原則を規定している' -ForEach $script:SddSkillCases {
        $path = Join-Path (Join-Path (Get-SkillDir $Skill) 'references') 'antigravity-orchestration.md'
        Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue -Because "$path が必要です"
        $raw = Read-Utf8 $path
        $raw | Should -Match 'define_subagent'
        $raw | Should -Match 'EnableWriteTools'
        $raw | Should -Match 'write_tools' -Because 'ロール定義 write_tools から EnableWriteTools を決定する旨が必要です'
        $raw | Should -Match 'invoke_subagent'
        $raw | Should -Match 'Model\W{1,5}pro\b' -Because 'Model: "pro" の明示指定が必要です'
        $raw | Should -Match 'Model\W{1,5}flash\b' -Because 'Model: "flash" の明示指定が必要です'

        $hasSingleWriter = Test-HasOrchestrationSingleWriterPrinciple -Raw $raw
        $hasSingleWriter | Should -BeTrue -Because '同一項目内に reviews.md / tasks.md を親エージェント（司令塔）のみが書き込み、サブエージェントは直接書き込まず親へ返却する単一ライター原則（否定・反転表現なし）が必要です'
    }

    It '[UT-18] <Skill> の antigravity-orchestration.md は parallel 部分失敗時の invoke_subagent 単体再実行による回復導線を含む' -ForEach $script:SddSkillCases {
        $path = Join-Path (Join-Path (Get-SkillDir $Skill) 'references') 'antigravity-orchestration.md'
        Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue
        $recovered = $false
        foreach ($block in (Get-MarkdownLogicalBlocks (Read-Utf8 $path))) {
            if ($block -match 'parallel' -and $block -match '(失敗|タイムアウト|timeout)' -and
                $block -match 'invoke_subagent' -and $block -match '(単体|個別|のみ).{0,10}再実行|再実行.{0,15}(単体|個別|のみ)') {
                $recovered = $true
                break
            }
        }
        $recovered | Should -BeTrue -Because '同一項目内に parallel 部分失敗・invoke_subagent・単体再実行が必要です'
    }

    It '[UT-18] sdd-apply の antigravity-orchestration.md は L3 swarm（workspace="share"・1ワーカー1担当ファイル群）を含む' {
        $path = Join-Path (Join-Path (Get-SkillDir 'sdd-apply') 'references') 'antigravity-orchestration.md'
        Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue -Because "$path が必要です"
        $raw = Read-Utf8 $path
        $raw | Should -Match 'swarm'
        $raw | Should -Match 'L3'
        $raw | Should -Match 'workspace\W{1,4}share\b'
        $raw | Should -Match '1\s*ワーカー\s*1\s*担当' -Because '競合回避のため 1 ワーカー 1 担当ファイル群の指示が必要です'
    }

    It '[UT-16] <Skill> は <Script> を antigravity-orchestration.md から参照している' -ForEach $script:ReviewScriptCases {
        $path = Join-Path (Join-Path (Get-SkillDir $Skill) 'references') 'antigravity-orchestration.md'
        Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue
        (Read-Utf8 $path) | Should -Match ([regex]::Escape($Script)) -Because 'run_workflow 用スクリプトの案内が必要です'
        (Read-Utf8 $path) | Should -Match 'run_workflow'
    }

    It '[UT-17] <Skill>/scripts/<Script> は ast.parse でエラーなく構文解析できる' -ForEach $script:ReviewScriptCases {
        $scriptPath = Get-ReviewScriptPath $Skill $Script
        $r = Invoke-PythonProcess @('-c', 'import ast,sys; ast.parse(open(sys.argv[1], encoding="utf-8").read(), filename=sys.argv[1])', $scriptPath)
        $r.ExitCode | Should -Be 0 -Because $r.StdErr
    }

    It '[UT-21] <Skill>/scripts/<Script> をスタブなしで python 直接実行すると NameError にならず終了コード 2 で run_workflow 専用メッセージを stderr に出す' -ForEach $script:ReviewScriptCases {
        $scriptPath = Get-ReviewScriptPath $Skill $Script
        $r = Invoke-PythonProcess @($scriptPath)
        $r.ExitCode | Should -Be 2 -Because "StdErr=$($r.StdErr)"
        $r.StdErr | Should -Not -Match 'NameError'
        $r.StdErr | Should -Not -Match 'Traceback'
        $r.StdErr | Should -Match 'run_workflow'
        $r.StdErr | Should -Match '(SKILL\.md|references/|invoke_subagent|代替|手順)' -Because '代替手順の案内が必要です'
    }

    It '[UT-17] <Skill>/scripts/<Script> はスタブ注入実行で全ロールを model="pro"・非空 schema/prompt で phase 内かつ parallel 内に起動する' -ForEach $script:ReviewScriptCases {
        $scriptPath = Get-ReviewScriptPath $Skill $Script
        $h = Invoke-ReviewHarness -ScriptPath $scriptPath -ChangeName 'sample-change'

        $h.result.error | Should -BeNullOrEmpty -Because "$($h.result.error)"
        $h.result.exit | Should -BeNullOrEmpty -Because 'スタブ注入時にガードで安全停止してはならない'

        @($h.calls.phase) | Should -Not -BeNullOrEmpty
        (@($h.calls.phase) -join '|') | Should -Match ([regex]::Escape($Phase))
        $h.calls.parallel | Should -BeGreaterOrEqual 1

        $agentCalls = @($h.calls.agent)
        $agentCalls.Count | Should -Be $Roles.Count -Because "各ロール 1 回ずつ起動（期待: $($Roles -join ', ')）"
        (@($agentCalls | ForEach-Object { $_.role } | Sort-Object)) | Should -Be (@($Roles | Sort-Object))
        foreach ($c in $agentCalls) {
            $c.model | Should -Be 'pro' -Because "$($c.role) は Neon 級 (pro) で起動する"
            $c.in_parallel | Should -BeTrue -Because "$($c.role) は parallel の内部で起動される必要があります"
            $c.in_phase | Should -BeTrue -Because "$($c.role) は phase コンテキストの内部で起動される必要があります"
            [string]::IsNullOrWhiteSpace([string]$c.prompt) | Should -BeFalse -Because "$($c.role) の prompt が空です"
            $c.schema | Should -Not -BeNullOrEmpty -Because "$($c.role) の schema が空です"
            [string]$c.prompt | Should -Match 'sample-change' -Because 'args["change_name"] がプロンプトに反映される必要があります'
        }
    }

    It '[UT-17] <Skill>/scripts/<Script> は不正な args / change_name に対してサイレントフォールバックせず ValueError で拒否する' -ForEach $script:ReviewScriptCases {
        $scriptPath = Get-ReviewScriptPath $Skill $Script
        $invalidArgsJsonList = @(
            'null',
            '{}',
            '{"change_name": ""}',
            '{"change_name": "   "}',
            '{"change_name": "../evil"}',
            '{"change_name": "foo/bar"}',
            '{"change_name": "foo\nbar"}'
        )
        foreach ($invalidJson in $invalidArgsJsonList) {
            $h = Invoke-ReviewHarness -ScriptPath $scriptPath -ArgsJson $invalidJson
            $h.result.error | Should -Match 'ValueError' -Because "不正な args ($invalidJson) は ValueError で拒否する必要があります"
            @($h.calls.agent).Count | Should -Be 0 -Because "不正な args ($invalidJson) でサブエージェントを起動してはなりません"
        }
    }

    It '[IT-05] <Skill>/scripts/<Script> は openspec/agents/ と checklist を参照し、各参照先に対応する openspec-kit 側ファイルが実在する' -ForEach $script:ReviewScriptCases {
        $scriptPath = Get-ReviewScriptPath $Skill $Script
        $raw = Read-Utf8 $scriptPath
        $raw | Should -Match 'openspec/agents/'
        $raw | Should -Match 'checklist_'
        foreach ($m in [regex]::Matches($raw, 'openspec/agents/([A-Za-z0-9_-]+)\.md')) {
            Test-Path -LiteralPath (Join-Path (Join-Path $script:KitRootPath 'agents') "$($m.Groups[1].Value).md") -PathType Leaf |
                Should -BeTrue -Because "$($m.Value) に対応する openspec-kit/agents/$($m.Groups[1].Value).md が必要です"
        }
        foreach ($m in [regex]::Matches($raw, 'openspec/templates/([A-Za-z0-9_-]+)\.md')) {
            Test-Path -LiteralPath (Join-Path (Join-Path $script:KitRootPath 'templates') "$($m.Groups[1].Value).md") -PathType Leaf |
                Should -BeTrue -Because "$($m.Value) に対応する openspec-kit/templates/$($m.Groups[1].Value).md が必要です"
        }
    }

    It '[IT-05] <Skill> のスキル一式が参照する openspec/agents/*.md・openspec/templates/checklist_*.md は openspec-kit に実在し、期待ロール・チェックリストを網羅する' -ForEach $script:ReferencedAssetCases {
        $files = @(Get-SkillFiles $Skill | Where-Object { $_.Extension -in '.md', '.py' })
        $files.Count | Should -BeGreaterThan 0
        $all = ($files | ForEach-Object { Read-Utf8 $_.FullName }) -join "`n"

        $agentRefs = @([regex]::Matches($all, 'openspec/agents/([A-Za-z0-9_-]+)\.md') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        $tplRefs = @([regex]::Matches($all, 'openspec/templates/(checklist_[A-Za-z0-9_-]+)\.md') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)

        foreach ($a in $Agents) {
            $agentRefs | Should -Contain $a -Because "$Skill が openspec/agents/$a.md を案内する必要があります"
        }
        foreach ($c in $Checklists) {
            $tplRefs | Should -Contain $c -Because "$Skill が openspec/templates/$c.md を案内する必要があります"
        }
        foreach ($a in $agentRefs) {
            Test-Path -LiteralPath (Join-Path (Join-Path $script:KitRootPath 'agents') "$a.md") -PathType Leaf |
                Should -BeTrue -Because "openspec/agents/$a.md に対応する openspec-kit/agents/$a.md が必要です"
        }
        foreach ($c in $tplRefs) {
            Test-Path -LiteralPath (Join-Path (Join-Path $script:KitRootPath 'templates') "$c.md") -PathType Leaf |
                Should -BeTrue -Because "openspec/templates/$c.md に対応する openspec-kit/templates/$c.md が必要です"
        }
    }
}

Describe 'Group 2-C: AGENTS.openspec.md スリム化・非推奨モデル排除・設定旧参照除去' {
    It '[UT-12] AGENTS.openspec.md 単体は UTF-8（BOM なし）で 12,000 バイト未満である' {
        $path = Join-Path $script:KitRootPath 'AGENTS.openspec.md'
        $bytes = [IO.File]::ReadAllBytes($path)
        $hasUtf8Bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        $hasUtf8Bom | Should -BeFalse -Because 'AGENTS.openspec.md は UTF-8 (BOM なし) である必要があります'
        $bytes.Length | Should -BeLessThan 12000 -Because "実バイト数 $($bytes.Length)。詳細は各スキルの references/sdd-reference.md へ分離する"
    }

    It '[UT-12] AGENTS.project.md とマーカー結合した新規生成相当の AGENTS.md（UTF-8 BOM なし）は 16,000 バイト以下かつ 24,000 バイト未満である' {
        $openspecPath = Join-Path $script:KitRootPath 'AGENTS.openspec.md'
        $projectPath = Join-Path $script:KitRootPath 'AGENTS.project.md'
        foreach ($p in @($openspecPath, $projectPath)) {
            $b = [IO.File]::ReadAllBytes($p)
            $hasBom = ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
            $hasBom | Should -BeFalse -Because "$([IO.Path]::GetFileName($p)) は UTF-8 (BOM なし) である必要があります"
        }
        $openspec = Read-Utf8 $openspecPath
        $project = Read-Utf8 $projectPath
        $markerBegin = '<!-- openspec-kit:begin (install.ps1 により管理。手動編集は再同期で上書きされます) -->'
        $markerEnd = '<!-- openspec-kit:end -->'
        $block = $markerBegin + "`n" + $openspec.TrimEnd() + "`n" + $markerEnd
        $generated = $project.TrimEnd() + "`n`n---`n`n" + $block + "`n"
        $size = (New-Object System.Text.UTF8Encoding($false)).GetByteCount($generated)
        $size | Should -BeLessThan 24000 -Because "実バイト数 $size"
        $size | Should -BeLessOrEqual 16000 -Because "実バイト数 $size（推奨上限）"
    }

    It '[UT-19] openspec-kit/skills/, config.yaml, AGENTS.openspec.md にアクティブな Gemini 3.8 Flash 割り当てがない' {
        $targets = [System.Collections.Generic.List[string]]::new()
        $skillFiles = @(Get-ChildItem -LiteralPath $script:KitSkills -Recurse -File)
        @($skillFiles | Where-Object { $_.Name -eq 'SKILL.md' }).Count | Should -Be 3 -Because 'skills/ 配下に 3 スキルが存在する必要があります'
        foreach ($f in $skillFiles) { $targets.Add($f.FullName) }
        $targets.Add((Join-Path $script:KitRootPath 'config.yaml'))
        $targets.Add((Join-Path $script:KitRootPath 'AGENTS.openspec.md'))

        $violations = @()
        foreach ($t in $targets) {
            $raw = Read-Utf8 $t
            $label = $t.Substring($script:KitRootPath.Length).TrimStart('\', '/')
            if ($t -like '*.md') {
                $agent = ConvertFrom-AgentMarkdown -Raw $raw -Path $t
            }
            else {
                $agent = @{ Path = $t; HasFrontmatter = $false; RawFrontmatter = ''; Frontmatter = @{}; Body = $raw; Raw = $raw }
            }
            $violations += Get-DeprecatedGemini38Violations -Agent $agent -Label $label
        }
        $violations | Should -BeNullOrEmpty
    }

    It '[UT-26] openspec-kit/<File> は旧パス workflows/sdd-* へのアクティブ参照を持たず、skills/sdd-* を参照している' -ForEach @(
        @{ File = 'config.yaml' },
        @{ File = 'README.md' }
    ) {
        $raw = Read-Utf8 (Join-Path $script:KitRootPath $File)
        $active = @(Get-LegacyWorkflowReferenceViolations -FileName $File -Raw $raw)
        $active | Should -BeNullOrEmpty -Because '旧 workflows/sdd-* へのアクティブ参照を skills/sdd-* へ更新する必要があります（YAML設定値での参照は全面禁止、文書内でも旧ファイルの退避・廃止注記のみ可）'
        $raw | Should -Match 'skills/sdd-(propose|apply|archive)' -Because '新パス skills/sdd-* への参照が必要です'
    }

    It '[E2E-01] 本リポジトリ実体の AGENTS.md (<24KB・BOMなし)・openspec/config.yaml・5エージェント skills/sdd-*・.claude/agents がキットと同期している' {
        $repoRoot = (Join-Path $script:KitRootPath '..' | Resolve-Path).Path
        $agentsPath = Join-Path $repoRoot 'AGENTS.md'
        $agentsBytes = [IO.File]::ReadAllBytes($agentsPath)
        $hasBom = ($agentsBytes.Length -ge 3 -and $agentsBytes[0] -eq 0xEF -and $agentsBytes[1] -eq 0xBB -and $agentsBytes[2] -eq 0xBF)
        $hasBom | Should -BeFalse -Because 'リポジトリの AGENTS.md は UTF-8 (BOM なし) である必要があります'
        $agentsBytes.Length | Should -BeLessThan 24000 -Because "Antigravity CLI 24,000B 上限未満が必要です（実測: $($agentsBytes.Length)B）"

        $repoCfg = Read-Utf8 (Join-Path $repoRoot 'openspec/config.yaml')
        @(Get-LegacyWorkflowReferenceViolations -FileName 'openspec/config.yaml' -Raw $repoCfg) | Should -BeNullOrEmpty

        $legacySdd = @()
        $legacyWfDir = Join-Path $repoRoot '.agents/workflows'
        if (Test-Path -LiteralPath $legacyWfDir -PathType Container) {
            $legacySdd = @(Get-ChildItem -LiteralPath $legacyWfDir -Filter 'sdd-*' -File)
        }
        $legacySdd.Count | Should -Be 0 -Because '旧 .agents/workflows/sdd-* は残存してはなりません'

        $expectedSkills = @(Get-ChildItem -LiteralPath $script:KitSkills -Recurse -File | ForEach-Object {
                $_.FullName.Substring($script:KitSkills.Length).TrimStart('\', '/').Replace('\', '/')
            } | Sort-Object)
        foreach ($agentRoot in @('.agents', '.claude', '.github', '.opencode', '.hermes')) {
            $skillsDir = Join-Path $repoRoot "$agentRoot/skills"
            foreach ($rel in $expectedSkills) {
                $dstFile = Join-Path $skillsDir $rel
                Test-Path -LiteralPath $dstFile -PathType Leaf | Should -BeTrue -Because "$agentRoot/skills/$rel が同期されている必要があります"
                $srcRaw = (Read-Utf8 (Join-Path $script:KitSkills $rel)).Replace("`r`n", "`n").Replace('{{BASE_BRANCH}}', 'main').Replace('{{EVIDENCE_DIR}}', 'test-results/')
                $dstRaw = (Read-Utf8 $dstFile).Replace("`r`n", "`n")
                $dstRaw | Should -Be $srcRaw -Because "$agentRoot/skills/$rel の内容が openspec-kit/skills/ と一致する必要があります"
            }
        }
    }
}
