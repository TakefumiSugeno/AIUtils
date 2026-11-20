# AGENTS

## プロジェクト概要

本リポジトリは特定アプリのリポジトリではなく、**AI駆動開発で使うツール群**（スキル・ワークフロー・プロンプト・テンプレート・スクリプト）を管理し、他プロジェクトへ配布するためのリポジトリです。

### 構成

| パス                                                                | 内容                                                                                                                   |
| ------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `openspec-kit/`                                                     | OpenSpec 拡張キット（レビュー機構・運用ルール・テンプレート・導入スクリプト）。詳細は [README](openspec-kit/README.md) |
| `skills/`                                                           | 自作スキルの配置ディレクトリ                                                                                           |
| `openspec/`                                                         | 本リポジトリ自身の OpenSpec（`openspec-kit` を導入済み）                                                               |
| `.agents/` `.claude/` `.gemini/` `.github/` `.hermes/` `.opencode/` | `openspec init` / `openspec update` が生成する各エージェント用スキル・コマンド                                         |

## プロジェクト固有ルール

- **汎用性の担保**: 配布物（`openspec-kit/`、`skills/` 等）に特定アプリ・特定技術スタック固有の記述を持ち込まない。プロジェクト依存箇所はプレースホルダ（`{{...}}`）または `TODO` として明示する。
- **生成ファイルを手で編集しない**: `openspec-*` スキル・`opsx` コマンド（`.agents/` 等の配下）は `openspec update` で再生成される。OpenSpec のカスタマイズは `openspec/config.yaml`・`AGENTS.md`・`openspec/templates/` で行う。
- **キットと自リポジトリの同期**: `openspec-kit/` を変更した場合は、`pwsh ./openspec-kit/install.ps1 -TargetPath . -BaseBranch main -EvidenceDir test-results/ -AgentTargets all -Force -SkipConfig` で本リポジトリへ再同期する（`openspec/config.yaml` は上書きされないため手動で反映する）。
- **言語**: ドキュメント・成果物・コメントは日本語で記述する。

### 自動フォーマット

| ファイル種別               | 対象                   | ツール           | コマンド                                                  |
| -------------------------- | ---------------------- | ---------------- | --------------------------------------------------------- |
| Markdown / OpenSpec 成果物 | `**/*.md`              | Prettier         | `npx prettier --write "**/*.md"`                          |
| JSON / YAML                | `**/*.{json,yaml,yml}` | Prettier         | `npx prettier --write "**/*.{json,yaml,yml}"`             |
| PowerShell                 | `**/*.ps1`             | PSScriptAnalyzer | `Invoke-Formatter` / `Invoke-ScriptAnalyzer -Path <file>` |
| Bash                       | `**/*.sh`              | bash -n          | `bash -n <file>`（LF 改行・UTF-8 BOM なし）               |

> [!NOTE]
> `openspec init` / `openspec update` による生成ファイルはフォーマット対象外とする（再生成で差分が出るため）。

### 実装ガイドライン

- PowerShell スクリプトは PowerShell 7 を前提とし、日本語を含む場合は UTF-8（BOM 付き）で保存する（Windows PowerShell 5.1 互換のため）。
- 破壊的操作を行うスクリプトは `SupportsShouldProcess`（`-WhatIf` 対応）とし、既存ファイルは上書き前にスキップまたはバックアップする。
- スクリプトのテストは Pester で `tests/` 配下に作成する。

---

<!-- openspec-kit:begin (install.ps1 により管理。手動編集は再同期で上書きされます) -->

## OpenSpec 運用ルール（openspec-kit）

本プロジェクトは **OpenSpec** による仕様駆動開発 (SDD) × テスト駆動開発 (TDD) を採用しています。

- **Single Source of Truth**: システム仕様の正本は `openspec/specs/`。OpenSpec 管理外に仕様書・タスクを新規作成・二重管理しない。
- **フェーズゲート駆動**: すべての変更は **Explore → [Gate 0] → Propose (`sdd-propose`) → [Gate 1] → Apply (`sdd-apply`) → [Gate 2] → Archive (`sdd-archive` / [Gate 3])** のゲートを通過して進める。
- **サブエージェント6ロール分業（TDD 3権分立）**: テスト作成（`qa-tester`）・実装（`pg-implementer`）・批判的レビュー（`user/se/pg/qa-reviewer`）のコンテキストを分離し、甘いテスト・テスト改ざん・追認レビューを構造的に防ぐ。
- **詳細手順とリファレンス**: 各フェーズ実行時は `.agents/skills/sdd-{propose,apply,archive}/SKILL.md`（および同ディレクトリ配下の `references/sdd-reference.md`・`references/antigravity-orchestration.md`）を必ず参照すること。

### ディレクトリ構成

| パス                               | 内容                                                                                                     |
| ---------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `openspec/config.yaml`             | OpenSpec 設定（スキーマ・規模レベル・6ロール定義・TDD/カバレッジ基準・運用ルール）                       |
| `openspec/specs/`                  | メイン仕様（システムの恒久的な仕様）                                                                     |
| `openspec/changes/<name>/`         | 変更単位の成果物（`proposal`, `specs`, `design`, `test_plan`, `tasks`, `mockup`, `reviews`, `handover`） |
| `openspec/agents/`                 | サブエージェント6ロール定義（`qa-tester`, `pg-implementer`, `user/se/pg/qa-reviewer`）                   |
| `openspec/templates/`              | `test_plan.md`, `review_record.md`, `checklist_*.md`, `handover.md`, `pr_body.md`                        |
| `openspec/scripts/verify-gate.ps1` | フェーズゲート（Gate 0〜3 / DoD）の機械的検証スクリプト（Bash 版: `verify-gate.sh`）                     |
| `.agents/skills/sdd-*/SKILL.md`    | SDD 実行スキル（`sdd-propose`, `sdd-apply`, `sdd-archive`。`.claude/skills/` 等にも同内容展開）          |
| `test-results/`                 | テストエビデンス・カバレッジレポート出力先（Git 管理外）                                                 |

### 適用規模レベル（L1 / L2 / L3）

変更開始時に規模レベルを決定し、`.openspec.yaml`（`level: L2` 等）と `proposal.md` に明記する。

| 項目                 | L1（軽微: typo・設定・局所修正） | L2（通常: 機能追加・仕様変更・通常バグ）                                        | L3（大規模: アーキテクチャ・破壊的変更・DB変更） |
| -------------------- | -------------------------------- | ------------------------------------------------------------------------------- | ------------------------------------------------ |
| 必須成果物           | `proposal`, `tasks`              | `proposal`, `specs`, `design`, `test_plan`, `tasks`（UI変更時は `mockup.html`） | L2 全成果物 ＋ 移行計画・ロールバック手順        |
| Propose レビュー     | `se-reviewer` のみ可             | `user-reviewer` + `se-reviewer`                                                 | `user-reviewer` + `se-reviewer`                  |
| Apply 分業           | メイン兼任可 ＋ PG/QA レビュー   | **`qa-tester` → `pg-implementer` → PG/QAレビュー**                              | L2 ＋ 設計変更時は `se-reviewer` 必須            |
| Archive 総括レビュー | 全4ロール ＋ `handover.md`       | 全4ロール ＋ `handover.md`                                                      | 全4ロール ＋ `handover.md`                       |

### サブエージェント6ロール分業とモデルティア・権限契約

同一エージェントによる自作自演 TDD を防ぐため、以下の 6 ロールを独立コンテキストで起動する（Gemini 3.8 Flash は非推奨のため使用しない）。

| ロール             | 定義ファイル                        | `model_tier` / `thinking` / `write_tools` | 担当フェーズ      | 責務・ガードレール                                                                |
| ------------------ | ----------------------------------- | ----------------------------------------- | ----------------- | --------------------------------------------------------------------------------- |
| **QA Tester**      | `openspec/agents/qa-tester.md`      | `flash` / `high` / `true`                 | Propose / Apply   | `specs/` と `test_plan.md` から先行 Red テスト・結合/E2E を実装（本実装編集禁止） |
| **PG Implementer** | `openspec/agents/pg-implementer.md` | `flash` / `medium` / `true`               | Apply             | Red テストを改ざんせず Green 実装＆Refactor（skip化・TODO残し・空catch禁止）      |
| **User Reviewer**  | `openspec/agents/user-reviewer.md`  | `pro` / `high` / `false`                  | Propose / Archive | ブラインド仕様比較・Zero-State/Error-State 体験・Why 欠落告発（Read-only）        |
| **SE Reviewer**    | `openspec/agents/se-reviewer.md`    | `pro` / `high` / `false`                  | 全フェーズ        | 外部依存ハング等の故障シミュレーション・状態不整合・隠された負債告発（Read-only） |
| **PG Reviewer**    | `openspec/agents/pg-reviewer.md`    | `pro` / `high` / `false`                  | Apply / Archive   | 暗黙の仮定・例外握りつぶし告発・30%コード削減リファクタ提案（Read-only）          |
| **QA Reviewer**    | `openspec/agents/qa-reviewer.md`    | `pro` / `high` / `true`                   | Apply / Archive   | 破壊テスト作成・実行（Adversarial QA）・トートロジーと甘いアサーション告発        |

- **単一ライター原則**: `reviews.md` および `tasks.md` への書き込みは親エージェント（司令塔）のみが行い、サブエージェントは `review_record.md` 形式のテキストまたは作業サマリを親へ返却する。
- **最大3サイクルとエスカレーション**: `Critical` / `Major` 指摘が 0 件（`LGTM: true`）になるまで修正・再レビューを繰り返す（最大 3 サイクルで未解消ならユーザーへエスカレーション）。保留とした `Minor` / `Suggestion` は Archive 時に `handover.md` へ全件転記する。

### テスト網羅性基準（C0 / C1 / C2・結合・E2E）要約

- **単体テスト (Unit)**: **C0（命令）** 全体 80%+ / 差分 90%+、**C1（分岐）** 全体 80%+ / 差分 85%+、**C2（複合条件デシジョンテーブル）** 100%。同値分割・境界値（`min-1`, `min`, `max`, `max+1`, 空/0件/1件/上限, 日時境界）必須。外部 I/O 以外のモックとトートロジー禁止。
- **結合テスト (Integration)**: 全外部/DB境界 100%（正常往復＋4xx/5xx/Timeout/切断/制約違反の Fault Injection）、状態遷移 100%（0-switch 正常＋1-switch 不正拒否・冪等性）。
- **E2Eテスト (End-to-End)**: `specs/` 全 Scenario 100%（① Happy Path、② Zero-State、③ Negative/Recovery Path、UI は実画面 PNG キャプチャ検証）。
- **不具合修正 (`fix/*`)**: ① Root Cause 特定 → ② `qa-tester` による再現 Red テスト先行作成 → ③ `pg-implementer` 最小修正＆横展開確認。

### 完了基準（DoD）と機械的フェーズゲート

各フェーズ末尾で **`openspec/scripts/verify-gate.ps1`**（または `verify-gate.sh`）を実行し、`PASSED` を確認してから次へ進む。

| ゲート     | タイミング                           | 検証コマンド                                                                        | 通過条件（要約）                                                                               |
| :--------- | :----------------------------------- | :---------------------------------------------------------------------------------- | :--------------------------------------------------------------------------------------------- |
| **Gate 0** | `openspec new change` 直前           | `pwsh ./openspec/scripts/verify-gate.ps1 -Gate pre-propose`                         | 未コミット変更退避済み、最新 `main` から切ったトピックブランチ上                    |
| **Gate 1** | Propose 合意・commit 前              | `openspec validate "<name>"` & `verify-gate.ps1 -Gate propose -ChangeName "<name>"` | 規模別必須成果物完備、`reviews.md` 未判定 0 件かつ Propose レビュー `LGTM: true`               |
| **Gate 2** | Apply 各タスク `[x]` 更新・commit 前 | `pwsh ./openspec/scripts/verify-gate.ps1 -Gate apply -ChangeName "<name>"`          | フォーマット/静的解析エラー0、全テストPass、C0/C1/C2達成、skip放置0、最新レビュー `LGTM: true` |
| **Gate 3** | `openspec archive` 実行前            | `pwsh ./openspec/scripts/verify-gate.ps1 -Gate archive -ChangeName "<name>"`        | 未完了タスク 0 件、`handover.md` 記入済み、全4ロール総括レビュー `LGTM: true`、DoD達成         |

### Git 操作ルールと禁止事項（ハードガードレール）

- **Gate 0 ブランチ作成**: 未コミット変更を `git stash` 退避後、`git checkout main && git pull origin main && git fetch --prune` を実行し、マージ済みブランチを整理してから `git checkout -b feature/<change-name>`（または `fix/`・`refactor/`・`chore/`）を作成する。
- **Commit / Push / PR**: Gate 1・Gate 2（タスク単位）・Gate 3（Archive 後）の各ゲート通過後に Conventional Commits（`<type>(<change-name>): <subject>`）で commit する。Archive 後は `git push` と `gh pr create --base main`（`pr_body.md` 準拠）まで自動実行し、人間承認後に **Merge commit**（`gh pr merge --merge --delete-branch`）で統合する。
- **自動フォーマット**: ファイル更新時・コミット前・テスト実行前に、本ファイル管理区間外の「自動フォーマット」表のコマンドを実行する。
- **禁止事項**:
  - `main` および `main` への直接コミット・直接 push
  - `verify-gate.ps1` を実行・通過せずに行うフェーズ移行・`[x]` 更新・Archive 実行
  - 既存テストの期待値改ざん・アサーション削除・`skip` 化による見せかけの Green 化
  - **ユーザー承認なしでの PR マージ（ベースブランチへの統合）**
  - テストエビデンス（`test-results/`）・カバレッジレポート・秘密情報（`.env` 等）の commit

<!-- openspec-kit:end -->
