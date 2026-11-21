# Design: optimize-agy-models-and-skills

## Context

背景・動機および影響範囲は [proposal.md](./proposal.md) を参照。
現在の `openspec-kit` は 6 ロール定義（`openspec-kit/agents/*.md`）、レガシーワークフロー（`openspec-kit/workflows/sdd-*.md`）、テンプレート（`openspec-kit/templates/`）、ゲート検証スクリプト（`verify-gate.ps1` / `.sh`）、および導入スクリプト（`install.ps1` / `install.sh`）で構成されている。
本設計では、5 エージェント（Antigravity CLI / Claude Code / GitHub Copilot CLI / OpenCode CLI / Hermes Agent）間のスキル配置互換性と、Antigravity CLI における Gemini 4 世代のモデル使い分け・障害回復・ルールサイズ制限（24,000 バイト未満）を解決する。

## Goals / Non-Goals

**Goals:**
- `openspec-kit/workflows/sdd-*.md` を `openspec-kit/skills/sdd-{propose,apply,archive}/` へ移行し、5 エージェントの標準パスへ一貫配置する。
- 既存の `.claude/agents/` への 6 ロール展開処理は維持しつつ、全ロールへモデルティア・権限メタデータを拡張する。
- 既存の `.agents/workflows/sdd-*.md` を安全に `.bak` 退避し、ユーザー編集や `opsx-*.md` を破壊しない。
- `openspec-kit/agents/*.md` の定義を Antigravity スキルの `define_subagent` / `invoke_subagent` / `run_workflow` / `swarm` へ連携し、単一ライター原則と部分失敗回復導線を規定する。
- `AGENTS.openspec.md` を 12,000 バイト未満へスリム化し、生成される `AGENTS.md` 全体の安全性（アトミック書き換え・マーカー破損検知・24,000 バイト超過警告）を担保する。
- `install.ps1` と `install.sh` の挙動（引数・展開先・特殊文字安全性・冪等性・`-WhatIf`/`--dry-run`）を完全に一致させる。

**Non-Goals:**
- `openspec init` / `openspec update` が生成するファイル群の改変。
- `.claude-plugin` / `.opencode/plugins` / Hermes `plugin.yaml` 等の Plugin パッケージ生成。
- `verify-gate.ps1` / `verify-gate.sh` の Gate 0〜3 判定基準の破壊的変更。

## Decisions

### 1. 配布アーキテクチャ: 自己完結型 Agent Skills の多面展開

```text
openspec-kit/skills/sdd-{propose,apply,archive}/
  |-- SKILL.md                          (5エージェント共通手順・フォールバック規定)
  |-- references/
  |     |-- antigravity-orchestration.md (Antigravity固有モデル・権限・並列・障害回復)
  |     +-- sdd-reference.md             (当該フェーズで必要なリファレンス・詳細基準)
  +-- scripts/                           (propose/archive: run_workflow 用 Python スクリプト)
          |
          v install.ps1 / install.sh (-AgentTargets auto|all|<csv>)
  +-------+---------------+---------------+---------------+---------------+
  | .agents/skills/       | .claude/skills/ | .github/skills/ | .opencode/skills/ | .hermes/skills/ |
  | (auto/all/antigravity)| (検出/指定時)  | (検出/指定時)  | (検出/指定時)     | (検出/指定時)   |
```

- **自己完結性の確定**: 親ディレクトリ外参照やスキル間参照の不安定性を排除するため、`sdd-reference.md` は各スキル配下の `references/sdd-reference.md` としてフェーズ別に自己完結配置する。
- **既存 `.claude/agents/` 維持**: 現行 `install.ps1` / `install.sh` の `.claude/agents/*.md` コピーは維持し（`claude` ターゲット resolved 時または `.claude/` 既存時に展開して初回未生成を防止）、`model_tier` 等を追加した 6 ロール定義をそのまま同期する。

#### 採用案とボツ案のトレードオフ比較

| 候補方式                                           | 5エージェント互換性 | コンテキスト効率・運用コスト             | 採用可否・理由                                                                         |
| -------------------------------------------------- | ------------------- | ---------------------------------------- | -------------------------------------------------------------------------------------- |
| 旧 `.agents/workflows/*.md` 継続                   | 不可（Agy 非推奨）  | 中（単一 `.md`）                         | **ボツ**: Antigravity 2.0 以降非推奨であり他 4 エージェントが参照できないため廃止      |
| Plugin バンドル（`.claude-plugin` / `.opencode` 等）| 不可（3仕様分裂）   | 高（環境ごとに形式・更新契機が分裂）     | **ボツ**: `.claude-plugin`・`.opencode/plugins`・Hermes `plugin.yaml` で非互換のため不採用 |
| **Agent Skills（`SKILL.md`＋`references/`・`scripts/`）** | **全5種対応**       | **高（Progressive Disclosure＋自己完結）** | **採用**: 5 エージェント標準互換と肥大化防止・`install` 多面展開を両立可能             |

### 2. `install.ps1` / `install.sh` のターゲット解決・処理順序・安全性

- **パラメータ仕様**: `-AgentTargets`（Bash: `--agent-targets` / `-AgentTargets`）。
  - 許容値: `auto`（既定）、`all`、または `antigravity`, `claude`, `copilot`, `opencode`, `hermes` のカンマ区切り（大小文字不問・前後空白トリム・重複排除）。
  - **厳格バリデーション**: 空文字・空白のみ・空トークン（`"claude,"` 等）・未知のターゲット名、あるいは展開先パスがディレクトリではなく通常ファイルとして存在する場合は、ファイル書き込みの前に即座に非ゼロ終了する。
- **ターゲット別配置先マッピング**:
  - `antigravity` → `.agents/skills`（`auto` 時は必須配置）
  - `claude` → `.claude/skills`（`auto` 時は `.claude/` 存在時のみ）
  - `copilot` → `.github/skills`（`auto` 時は `.github/` 存在時のみ）
  - `opencode` → `.opencode/skills`（`auto` 時は `.opencode/` 存在時のみ）
  - `hermes` → `.hermes/skills`（`auto` 時は `.hermes/` 存在時のみ）
  - ※ 明示指定時に `antigravity` を含めない場合（例: `claude,copilot`）は指定されたターゲットのみに展開し、`.agents/skills/` は作成しない。
- **安全な実行順序（半壊防止）**:
  1. パラメータ・前提（`openspec/` 存在・展開先パス種別）検証
  2. `templates/`・`agents/`（`openspec/agents/`＋`claude` ターゲット resolved 時または `.claude/` 既存時 `.claude/agents/`）・`scripts/`・`skills/`（再帰コピー、スキップ件数カウント）配置
  3. **`.agents/skills` がターゲットに含まれ、かつスキル配置が全成功した後にのみ**、既存の `.agents/workflows/sdd-{propose,apply,archive}.md` を退避
     - 衝突回避: `<file>.bak` が既にあれば `<file>.bak-<yyyyMMddHHmmss>-<counter>`（存在しない番号までインクリメント）へリネーム。リネーム失敗時はパスと復旧案内を出して非ゼロ終了。`opsx-*.md` 等には触れない。
  4. `config.yaml` / `AGENTS.md` / `.gitignore` / `CLAUDE.md`・`GEMINI.md` 更新
  5. **可観測性サマリ出力**:
     - 配置ターゲット・展開パス・スキップ件数・退避件数・`AGENTS.md` 実バイト数を表示。
     - `-Force` なしで既存スキルをスキップした場合は `-Force` 再実行推奨警告を出力。
     - `auto` で他エージェント未検出時（Zero-State）は再実行方法（`-AgentTargets claude` 等）を案内。
     - 退避実施時はカスタム記述確認と不要時削除の案内を出力。
- **文字列置換と `AGENTS.md` アトミック更新**:
  - `install.sh` は `sed` による特殊文字破壊（`&`, `\`, `|`）を防ぐため、`awk` の `index()` / `substr()` を用いた純粋リテラル置換関数（`expand_placeholders`）を使用する。
  - `AGENTS.md` は UTF-8（BOM なし）で書き込み、一時ファイルへ出力後にアトミック置換（`Move-Item -Force` / `mv -f`）する。
  - 片側マーカーのみ残存する破損 `AGENTS.md` は二重追記せずエラー停止（復旧案内出力）する。
  - 生成後の `AGENTS.md` 実バイト数が `24,000` バイト以上の場合は警告ログ（実バイト数・超過数・分割案内）を出力する。

### 3. 6ロール定義と Antigravity `run_workflow` / `swarm` 契約

`openspec-kit/agents/*.md` の YAML frontmatter に `model_tier` (`pro` | `flash` | `flash_lite`), `thinking` (`high` | `medium` | `low`), `write_tools` (`true` | `false`) を追加する。

| ロール | `model_tier` | `thinking` | `write_tools` | 担当・契約 |
| :--- | :--- | :--- | :--- | :--- |
| `user-reviewer` | `pro` | `high` | `false` | Neon 級推論＋Read-only。結果は親へテキスト返却 |
| `se-reviewer` | `pro` | `high` | `false` | 故障シミュレーション＋Read-only。結果は親へ返却 |
| `pg-reviewer` | `pro` | `high` | `false` | 暗黙仮定・30%削減提案＋Read-only。結果は親へ返却 |
| `qa-reviewer` | `pro` | `high` | `true` | トートロジー看破＋破壊テスト作成・実行 |
| `qa-tester` | `flash` | `high` | `true` | `specs/`・`test_plan` からの高速 Red テスト生成 |
| `pg-implementer` | `flash` | `medium` | `true` | Red テストを通す高速 Green 実装・Refactor |

- **メタデータ契約とロール間差異の根拠**: `model_tier`・`thinking`・`write_tools` は CLI 自動解釈構文ではなく親エージェントが読み取る運用規約メタデータである。`qa-tester` を `flash` / `thinking: high` とするのは境界値・異常系の漏れを防ぐため、`pg-implementer` を `flash` / `thinking: medium` とするのは先行 Red テストに沿った高速実装反復のため、`qa-reviewer` のみ `write_tools: true` とするのは Adversarial QA で破壊テストを作成・実行するため（ただし既存コード・`reviews.md` 編集禁止）である。
- **単一ライター原則**: `reviews.md` および `tasks.md` への書き込みは親エージェント（司令塔）のみが行い、サブエージェントは `review_record.md` 準拠のテキストまたは作業サマリを返却する。
- **`run_workflow` スクリプト契約**（`scripts/run_propose_review.py`, `scripts/run_archive_review.py`）:
  - 実行開始時に `'agent' not in globals() or 'parallel' not in globals()` を検査し、通常 `python3` CLI 直叩き時は案内メッセージを標準エラーに出力して `sys.exit(2)` で安全停止する。
  - `run_workflow` 内では `args["change_name"]` 等を受け取り、`phase("Propose Review")` / `phase("Archive Review")` のもと、`agent(prompt=..., schema={"type": "string"}, role=..., model="pro")` を `parallel(roles, ...)` で並列起動し、ロール別結果テキストを返す。
- **部分失敗・タイムアウト回復と `swarm` 競合回避**:
  - `run_workflow` の `parallel` は 1 ロール失敗時に全体をキャンセルする特性を持つため、失敗・タイムアウト時は親エージェントが未完了ロールのみを `invoke_subagent(Model="pro")` で単体再実行する。
  - L3 で `swarm`（`workspace: "share"`）を使う場合は、1 ワーカー 1 担当ファイル群（重複編集禁止）＋ `qa-reviewer` / `pg-reviewer`（Verifier）構成とする。
- **非 Antigravity フォールバック**: `SKILL.md` 本体は汎用 Markdown 手順とし、他 4 エージェントでは各エージェント標準のサブエージェント機構または独立コンテキスト直列実行へフォールバックする。

### 4. `AGENTS.openspec.md` スリム化（24,000 バイト上限対策）

- Antigravity CLI には 1 ルールファイル **24,000 バイト上限（超過すると末尾が切り捨てられ後続ルールが欠落する実害）** があるため、長大な C0/C1/C2 網羅表・ブランチ作成詳細コマンド・OpenSpec CLI リファレンス・レビュープロトコル詳細表を各スキル配下の `references/sdd-reference.md` へ分離する。
- `AGENTS.openspec.md` 単体は **12,000 バイト未満**（目標 8〜10KB）に圧縮し、`AGENTS.project.md` との合算を 16,000 バイト以下（上限 24,000 バイトに対して十分な余裕）に保つ。

## Risks / Trade-offs

- **[Risk]** Antigravity `run_workflow` 用 Python スクリプトは通常の `python3` CLI 単体ではそのまま実行できない → **[Mitigation]** 先頭ガードにより `NameError` を防ぎ `exit 2` で案内終了させるとともに、テスト時は Python AST 検査＋スタブ（`agent`, `parallel`, `phase`, `log`, `args`）注入実行で論理検証する。
- **[Risk]** `openspec-kit/workflows/` 削除を先に行うと既存 `openspec-kit.install.Tests.ps1` が途中で失敗し Gate 2 を通過できない → **[Mitigation]** タスク順を「Group 2 で新スキル作成（`workflows/` 残存）→ Group 3 でテスト先行更新後に `install.ps1/.sh` 更新と `workflows/` 削除」に構成し、常に全テスト整合を維持する。

## Migration Plan

1. `openspec-kit/agents/*.md` をモデル・権限メタデータ対応へ更新する。
2. `openspec-kit/skills/` を新設し、`AGENTS.openspec.md`・`config.yaml`・`README.md` を更新する。
3. テストを先行更新（Red）した上で `install.ps1` / `install.sh` を更新し、`openspec-kit/workflows/` を削除する。
4. `pwsh ./openspec-kit/install.ps1 -TargetPath . -BaseBranch main -EvidenceDir test-results/ -AgentTargets all -Force -SkipConfig` を実行し、`openspec/config.yaml` の参照更新と退避された `.agents/workflows/sdd-*.md.bak*` の削除（本リポジトリではカスタム変更なしのため）を行う。
5. Pester 全テスト・カバレッジ（PowerShell `-CodeCoverage` および Bash 出力パリティ）・`verify-gate.ps1` / `.sh` を検証する。
