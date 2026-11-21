# Proposal: optimize-agy-models-and-skills

## Meta

- **Level**: L2
- **Type**: feat

## Why

現在の `openspec-kit` は Claude Code 寄りの構成（`.claude/agents/` への配置）と Antigravity CLI で非推奨（Deprecated）となった `.agents/workflows/sdd-*.md` に依存しており、GitHub Copilot CLI / OpenCode CLI / Hermes Agent 等を含む 5 エージェントでの共通利用や、Antigravity CLI における Gemini 4 世代のモデル差異（**Gemini 4 Neon**＝司令塔・設計・深い推論、**Gemini 4 Hydrogen**＝高速実装・テスト・並列サブエージェント、**Orchestrator (Neon)**＝連携モード、**Gemini 3.8 Flash**＝非推奨）を活かせていない。さらに、現在の `AGENTS.md`（24,958 バイト）は Antigravity CLI の 1 ファイル上限（24,000 バイト）を超過し末尾のコマンドリファレンスが切り捨てられている。

## What Changes

- **`.agents/workflows/` の廃止と 5 エージェント共通 Skills 化**:
  - `openspec-kit/workflows/sdd-*.md` を廃止し、5 エージェントすべてが対応する Agent Skills 規格の `openspec-kit/skills/sdd-{propose,apply,archive}/SKILL.md` へ移行する。
  - `install.ps1` / `install.sh` を拡張し、`.agents/skills/` への必須配置に加え、導入先に存在する（または `-AgentTargets` / `--agent-targets` で指定された）`.claude/skills/`, `.github/skills/`, `.opencode/skills/`, `.hermes/skills/` へ一括展開する。
- **6 ロール定義のモデル差異・権限拡張**:
  - `openspec-kit/agents/*.md` に推奨モデルティア（`model_tier: pro | flash`）、推論強度指針（`thinking: high | medium`）、書き込み権限（`write_tools: true | false`）を追加する。
  - 設計・批判的レビュー（`user/se/pg/qa-reviewer`）を Neon 級（`pro`、うちコード編集不要な 3 ロールは `write_tools: false`）、Red テスト作成・Green 実装（`qa-tester`, `pg-implementer`）を Hydrogen 級（`flash`、`write_tools: true`）に割り当てる。
- **Antigravity CLI オーケストレーション最適化**:
  - 各スキル配下に `references/antigravity-orchestration.md`（および `run_workflow` 用スクリプト雛形 `scripts/`）を同梱し、`define_subagent` による物理的な書き込み分離、`invoke_subagent` / `run_workflow` の並列実行（Propose 2 ロール並列・Archive 4 ロール並列）、L3 大規模時の `swarm` 運用指針を提供する。
- **`AGENTS.md` の 24KB 上限超過解消**:
  - `openspec-kit/AGENTS.openspec.md` の詳細テーブルや CLI リファレンスをスキル側 `references/` へ移動し、`AGENTS.md` 全体が 24,000 バイト未満に収まるようスリム化する。

## Capabilities

### New Capabilities

- `multi-agent-skills-distribution`: 5 エージェント（Antigravity CLI / Claude Code / GitHub Copilot CLI / OpenCode CLI / Hermes Agent）共通の SDD Agent Skills 管理・多面展開インストール、およびルールファイルサイズ上限（24,000 バイト未満）の維持。
- `antigravity-model-orchestration`: Gemini 4 モデルティア（Neon / Hydrogen）と書き込み権限分離に基づく 6 ロール定義、ならびに Antigravity CLI の `define_subagent` / `run_workflow` / `swarm` を用いたフェーズ別オーケストレーション。

### Modified Capabilities

<!-- 既存 spec (review-framework) の要件自体は変更しない -->

## Non-goals

- `openspec init` / `openspec update` が生成するファイル（`.agents/skills/openspec-*`, `.gemini/commands/opsx/*` 等）の編集。
- 5 エージェント間で非互換な独自 Plugin バンドル（`.claude-plugin`, `.opencode/plugins`, Hermes Python plugin）の同時生成。
- 素の Gemini CLI 固有機能（`.gemini/commands/*.toml` 独自拡張等）への最適化。

## Acceptance Criteria

### Given/When/Then

1. **Given**: 5 エージェントのいずれかのディレクトリ（`.claude/`, `.github/`, `.opencode/`, `.hermes/`）が存在するプロジェクト
   **When**: `install.ps1` または `install.sh` を実行した時
   **Then**: `.agents/skills/sdd-*` および対象エージェントの `skills/sdd-*` に `SKILL.md`・`references/`・`scripts/` が展開され、既存レガシー `.agents/workflows/sdd-*.md` があれば安全に整理され、`AGENTS.md` は 24,000 バイト未満に保たれること。
2. **Given**: `openspec-kit/agents/*.md` が配置された状態
   **When**: Antigravity CLI で `sdd-propose` / `sdd-apply` / `sdd-archive` スキルを起動した時
   **Then**: 6 ロールが推奨モデルティア（設計/レビュー=`pro`、テスト/実装=`flash`）と権限（レビュー3ロール=`EnableWriteTools: false`）で使い分けられ、レビュー並列実行の指示・スクリプトを参照できること。

## Impact

- `openspec-kit/`（`skills/`, `agents/`, `AGENTS.openspec.md`, `config.yaml`, `install.ps1`, `install.sh`, `README.md`, `workflows/` 廃止）
- 本リポジトリの `.agents/skills/`, `.claude/`, `.github/`, `.opencode/`, `.hermes/`, `openspec/`, `AGENTS.md`（再同期反映）
- `tests/` 配下の Pester テスト（`install.ps1`, `install.sh`, `verify-gate` 整合テスト）
