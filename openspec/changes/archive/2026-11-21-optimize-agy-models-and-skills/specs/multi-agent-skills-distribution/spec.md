# Spec Delta: multi-agent-skills-distribution

## Purpose

Antigravity CLI・Claude Code・GitHub Copilot CLI・OpenCode CLI・Hermes Agent の 5 エージェントすべてで共通利用できる Agent Skills（`SKILL.md`）パッケージングおよび多面展開インストールを提供し、あわせてレガシーワークフロー移行とルールファイルサイズ上限（24,000 バイト未満）の維持を実現する。

## ADDED Requirements

### Requirement: 5エージェント共通の Agent Skills パッケージ構造

システムは、SDD 各フェーズ（`sdd-propose`, `sdd-apply`, `sdd-archive`）の手順を、5 エージェントすべてが解釈可能な Agent Skills 標準形式（YAML frontmatter に `name` と `description` を持つ `SKILL.md`、および自己完結した `references/`・`scripts/` サブディレクトリ）として `openspec-kit/skills/` 配下に保持しなければならない（SHALL）。

#### Scenario: スキル定義の必須構造と自己完結性

- **WHEN** `openspec-kit/skills/<skill-name>/SKILL.md` を検証する
- **THEN** 各スキルのディレクトリ名と YAML frontmatter の `name` が一致し、発動条件を含む `description` が定義され、必要な `references/`（フェーズ別 `sdd-reference.md`, `antigravity-orchestration.md`）および `scripts/` が親ディレクトリ外参照なしで自己完結して配置されていなければならない。

#### Scenario: openspec 生成スキルとの非衝突

- **WHEN** `openspec-kit/skills/` を導入先プロジェクトへ配置する
- **THEN** スキル名は `sdd-propose`, `sdd-apply`, `sdd-archive` の `sdd-*` 名前空間を使用し、`openspec init` / `openspec update` が生成・上書きする `openspec-*` スキルや `.gemini/commands/opsx/*` と名前衝突してはならない。

### Requirement: インストーラによるマルチエージェント向けスキル多面展開

`install.ps1` および `install.sh` は、既定値 `auto`（`.agents/skills/` を必須配置した上で導入先に存在する `.claude/`, `.github/`, `.opencode/`, `.hermes/` を自動検出）または明示パラメータ（`-AgentTargets` / `--agent-targets`: `all` または `antigravity,claude,copilot,opencode,hermes` のカンマ区切り）に従って対象エージェントの `skills/` 配下へスキル一式を展開し、既存の `.claude/agents/` 配置処理も維持しなければならない（SHALL）。

#### Scenario: 自動検出による多面展開（Happy Path）

- **WHEN** `.claude/` と `.github/` のみが存在するプロジェクトに対して `-AgentTargets auto`（既定）で `install.ps1` または `install.sh` を実行する
- **THEN** `.agents/skills/sdd-*`, `.claude/skills/sdd-*`, `.github/skills/sdd-*`（および `.claude/agents/*.md`）に展開され、存在しない `.opencode/skills/` や `.hermes/skills/` は作成されてはならない。

#### Scenario: 他エージェント未検出時の Zero-State 案内

- **WHEN** `.claude/`, `.github/`, `.opencode/`, `.hermes/` のいずれも存在しない新規プロジェクトへ `-AgentTargets auto` で導入する
- **THEN** `.agents/skills/sdd-*` のみへ正常配置し、後から他エージェントを追加する際の再実行オプション（`-AgentTargets` / `--agent-targets`）を案内しなければならない。

#### Scenario: 明示指定（all / カンマ区切り）と異常入力の拒否

- **WHEN** `-AgentTargets all` または `-AgentTargets " Claude , copilot "`（`antigravity` を含まない指定）を指定して実行する
- **THEN** `all` では 5 エージェントすべての `skills/` を作成して展開し、`claude,copilot` 指定時は `.claude/skills/` と `.github/skills/` のみを作成して展開する（`.agents/skills/` は作成しない）。空文字・空白のみ・未知ターゲット名・重複カンマ等の不正入力、または展開先パスがディレクトリではなく通常ファイルとして存在する場合は、ファイル書き込み前に非ゼロ終了コードで停止しなければならない。

#### Scenario: 既存スキルの保護・半端更新警告・-WhatIf 抑止

- **WHEN** 既に配置済みのスキルに対して `-Force`（`--force`）なしで再実行する、または `-WhatIf`（`--dry-run`）付きで実行する
- **THEN** `-Force` なしでは既存ファイルを上書きスキップした上で「`AGENTS.md` との不整合を防ぐため `-Force`（`--force`）での再実行を推奨する」警告を出力し、`-WhatIf` / `--dry-run` 時にはファイル作成や退避を一切行わずに予定内容のみ出力しなければならない。

### Requirement: レガシーワークフロー（.agents/workflows/sdd-*.md）の安全移行

`install.ps1` および `install.sh` は、`.agents/skills/` への配置が有効な実行において全スキル配置が成功した後に限り、導入先に残存する旧形式の `.agents/workflows/sdd-{propose,apply,archive}.md` をバックアップ退避しなければならない（SHALL）。

#### Scenario: 旧 SDD ワークフロー残存時の安全な後段退避

- **WHEN** `.agents/skills/` への展開が成功し、導入先に `.agents/workflows/sdd-propose.md` と `opsx-propose.md` が存在する（`-WhatIf` 除く）
- **THEN** `sdd-propose.md` は `.agents/workflows/sdd-propose.md.bak`（既に `.bak` が存在する場合は `.bak-<timestamp>-<counter>` で衝突回避）へリネームされ、退避ファイル確認・不要時削除の案内が出力され、`opsx-propose.md` は無変更で維持されなければならない。

#### Scenario: リネーム失敗時のエラー案内および非対象時の非実行

- **WHEN** ロックや権限不足によりリネームに失敗する、または `-AgentTargets claude` のように `.agents/skills/` へ配置しない実行を行う、あるいは旧ファイルが存在しない
- **THEN** リネーム失敗時は対象パスと復旧案内を出して非ゼロ終了し、`.agents/skills/` 非対象時および旧ファイル不在時は退避処理や空ディレクトリ作成を行ってはならない。

### Requirement: ルールファイル（AGENTS.md）の安全更新とサイズ上限遵守

`openspec-kit/AGENTS.openspec.md` は詳細リファレンスをスキル側 `references/` へ分離することで自身を 12,000 バイト未満に抑え、かつ `install.ps1` / `install.sh` は置換処理の特殊文字安全性・アトミック書き込み・片側マーカー破損検知・24,000 バイト超過警告を備えなければならない（SHALL）。

#### Scenario: 生成後 AGENTS.md のサイズ上限検証と超過警告

- **WHEN** `install.ps1` / `install.sh` が `AGENTS.md`（UTF-8 BOM なし）を生成または再同期する
- **THEN** 新規生成時および本リポジトリ適用時の `AGENTS.md` は 24,000 バイト未満（推奨 16,000 バイト以下）であり、もし導入先の既存ユーザー記述肥大化により合計が 24,000 バイト以上となった場合は実バイト数・超過バイト数・分割案内を警告出力しなければならない。

#### Scenario: マーカー破損防止・特殊文字置換安全性・アトミック書き換え

- **WHEN** 片側マーカーのみ残存した破損 `AGENTS.md` に対して実行する、または `BaseBranch` / `EvidenceDir` に `&`・`\`・`|` を含む値で置換を実行する
- **THEN** 片側マーカー破損時は二重追記せずエラー終了して復旧手順を提示し、特殊文字を含むプレースホルダ置換はリテラル置換として破損なく展開され、`AGENTS.md` への書き換えは一時ファイル経由のアトミック置換で行われなければならない。
