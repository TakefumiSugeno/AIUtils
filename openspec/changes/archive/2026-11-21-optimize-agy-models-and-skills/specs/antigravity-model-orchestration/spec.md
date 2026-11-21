# Spec Delta: antigravity-model-orchestration

## Purpose

Antigravity CLI における Gemini 4 世代のモデル差異（Gemini 4 Neon / Gemini 4 Hydrogen / Orchestrator (Neon)、および Gemini 3.8 Flash 非推奨）とツール権限分離（`EnableWriteTools`）を活かした 6 ロール定義およびフェーズ別オーケストレーション手順を提供する。

## ADDED Requirements

### Requirement: ロール別モデルティアおよび書き込み権限の定義

`openspec-kit/agents/` 配下の 6 ロール定義ファイルは、YAML frontmatter として `model_tier`（`pro` | `flash` | `flash_lite`）、`thinking`（`high` | `medium` | `low`）、および `write_tools`（`true` | `false`）を宣言し、本文内にモデル運用上の振る舞い（Read-only ロールの結果返却契約等）を記載しなければならない（SHALL）。

#### Scenario: 高推論・設計レビュー系ロールの Neon 級割り当てと権限分離

- **WHEN** `user-reviewer.md`, `se-reviewer.md`, `pg-reviewer.md` を検査する
- **THEN** それぞれ `model_tier: pro`（Gemini 4 Neon 相当）、`thinking: high`、`write_tools: false`（読み取り専用）が宣言され、ファイル編集を行わずレビュー記録テキストを親エージェントへ返却する契約が明記されていなければならない。

#### Scenario: 破壊テスト実行権を持つ QA レビュアーの定義

- **WHEN** `qa-reviewer.md` を検査する
- **THEN** 死角看破と敵対的破壊テスト作成・実行を両立するため、`model_tier: pro`、`thinking: high`、および `write_tools: true` が宣言されていなければならない。

#### Scenario: 高速実装・テスト生成ロールの Hydrogen 級割り当て

- **WHEN** `qa-tester.md` および `pg-implementer.md` を検査する
- **THEN** 確定仕様・設計に基づく高速・低コスト実行のため、`model_tier: flash`（Gemini 4 Hydrogen 相当）および `write_tools: true` が宣言されていなければならない。

### Requirement: フェーズ別の Antigravity オーケストレーション手順とスクリプトの提供

`sdd-propose`, `sdd-apply`, `sdd-archive` の各スキルは、Antigravity CLI 実行時に参照する専用ガイド（`references/antigravity-orchestration.md`）および `run_workflow` 用スクリプト（`scripts/run_propose_review.py`, `scripts/run_archive_review.py`）を備え、権限分離・モデル指定・並列実行・障害回復・単一ライター原則を規定しなければならない（SHALL）。

#### Scenario: define_subagent による物理的書き込み分離と単一ライター転記

- **WHEN** Antigravity CLI で SDD スキルを開始する
- **THEN** 手順書は `openspec/agents/<role>.md` の `write_tools` に従って `define_subagent` の `EnableWriteTools` を設定し、呼び出し時に `model_tier` に対応する `Model`（`pro` / `flash`）を明示指定し、`reviews.md` および `tasks.md` への書き込みは親エージェント（司令塔）のみが行う単一ライター原則を指示しなければならない。

#### Scenario: Propose・Archive 並列実行スクリプトと誤実行ガード

- **WHEN** `sdd-propose` / `sdd-archive` の `run_workflow` 用スクリプトを `run_workflow` 経由または誤って直接 `python3` CLI で実行する
- **THEN** `run_workflow` 実行時は `phase`・`agent(..., model="pro")`・`parallel` を用いて対象レビューを並列起動し、通常 `python3` で直接実行された場合は `NameError` でクラッシュせず「`run_workflow` ツール専用スクリプトである旨と代替手順」を標準エラーへ出力して終了コード 2 で安全停止しなければならない。

#### Scenario: 並列失敗時のフォールバックおよび L3 swarm 連携

- **WHEN** `run_workflow` 並列実行中に一部サブエージェントが失敗・タイムアウトする、または L3 規模で複数ファイルの並列実装を行う
- **THEN** 手順書は失敗した未完了ロールのみ `invoke_subagent`（`Model: "pro"`）で単体再実行する回復導線と、L3 並列実装時に Neon 司令塔が複数の Hydrogen ワーカーを `workspace: "share"`（1 ワーカー 1 担当ファイル群で競合回避）で起動する `swarm` 運用パターンを提示しなければならない。

### Requirement: 非推奨モデルの排除と他エージェント実行時のフォールバック

システムは、新規採用非推奨である Gemini 3.8 Flash を推奨モデルとして指定してはならず、かつ Antigravity CLI 以外の 4 エージェントでスキルが実行された場合でも手順が破綻しないフォールバック規定を持たなければならない（SHALL）。

#### Scenario: Gemini 3.8 Flash の非採用確認

- **WHEN** `openspec-kit` 配下のエージェント定義、スキル、設定ファイル、ドキュメントを検査する
- **THEN** アクティブな推奨モデルや設定値として `3.8` / `gemini-3.8-flash` が割り当てられていてはならない（比較・非推奨注記を除く）。

#### Scenario: Antigravity CLI 以外のエージェントでの実行

- **WHEN** Claude Code・GitHub Copilot CLI・OpenCode CLI・Hermes Agent のいずれかで `SKILL.md` を読み込む
- **THEN** `SKILL.md` 本体の手順は特定 CLI 専用ツール（`define_subagent` / `run_workflow` / `swarm`）を必須前提とせず、各エージェント標準のサブエージェント機構（`.claude/agents/` 等）または独立コンテキストでの直列実行へフォールバックする指示を含まなければならない。
