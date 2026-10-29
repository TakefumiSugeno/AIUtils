---
description: 全ロール総括レビュー・DoD（完了基準）検証・Gate 3検証・PR自動作成を伴うSDD Archiveワークフロー
---

# SDD Archive ワークフロー（Definition of Done & Gate 3）

すべての実装・テストタスク完了後、**完了基準（Definition of Done）の最終確認・4ロール総括レビュー・`handover.md` 作成・機械的ゲート検証（Gate 3）・ユーザー最終合意・PR作成** を経て変更を完了させるワークフローです。

## ステップ 1: 完了基準（Definition of Done）の最終検証

1. 自動フォーマットおよび静的解析（リンター）・ビルドを実行し、差分 0・エラー 0・新規警告 0 を確認する。
2. 全テスト（単体・結合・E2E）を実行し、最新のテストレポート・カバレッジレポート・画面キャプチャを `{{EVIDENCE_DIR}}` に出力する:
   - 全テスト **100% Pass**（`Skip` / `Ignore` 放置 0 件）
   - **C0（命令網羅）**: 全体 80%以上 / 変更差分 90%以上
   - **C1（分岐網羅）**: 全体 80%以上 / 変更差分 85%以上
   - **C2（条件網羅）**: 複合条件デシジョンテーブル 100%
   - **Scenario 網羅率**: `specs/**/spec.md` の全 Scenario 100%
3. `README.md` や関連ドキュメントに変更内容の同期が必要であれば更新する。

## ステップ 2: `handover.md` の作成

`openspec/templates/handover.md` をもとに `openspec/changes/<change-name>/handover.md` を作成し、以下を漏れなく記録する:

- 変更サマリ（What & Why、バグ修正時は根本原因と対応）
- テスト結果サマリ（単体/結合/E2E 件数、C0/C1/C2 カバレッジ率、エビデンス出力先パス）
- Apply フェーズで「保留」とした全指摘事項の転記（ない場合は「なし」）
- 将来の改善・リファクタ候補および運用上の注意事項

## ステップ 3: 全 4 ロールによる Archive 総括レビュー

`openspec/templates/checklist_archive.md` を用い、4つのレビュアーサブエージェント（`user-reviewer`, `se-reviewer`, `pg-reviewer`, `qa-reviewer`）による総括レビューを実施し、`openspec/changes/<change-name>/reviews.md` に記録する。

- 指摘があれば修正し、全ロールが `LGTM: true` になるまで繰り返す（最大 3 サイクル）。

## ステップ 4: ユーザー最終合意と Gate 3 検証

1. 変更サマリ・テスト＆カバレッジ結果・`handover.md`・総括レビュー結果をユーザーに提示し、**Archive 実行および PR 作成の最終合意**を得る。
2. 合意を得たら、`reviews.md` の「ユーザー最終合意」セクションに `- **合意**: あり`・合意者・合意日時を記録する。
3. **Gate 3 検証スクリプトを実行する**:
   ```powershell
   pwsh ./openspec/scripts/verify-gate.ps1 -Gate archive -ChangeName "<change-name>"
   ```
   ※ `PASSED` であることを確認してから次へ進む。

## ステップ 5: OpenSpec Archive 実行・コミット・PR 作成

1. アーカイブを実行する（デルタ仕様が `openspec/specs/` に同期され、`openspec/changes/archive/` へ移動される）:
   ```bash
   openspec archive "<change-name>"
   ```
2. 自動フォーマットを実行し、アーカイブ結果をコミット＆プッシュする（ユーザー合意済み）:
   ```bash
   npx prettier --write "openspec/**/*.md"
   git add openspec/ README.md
   git commit -m "chore(<change-name>): archive change and sync specs"
   git push -u origin <current-branch>
   ```
3. `openspec/templates/pr_body.md` に従って PR 本文を作成し、GitHub CLI で `{{BASE_BRANCH}}` 向け Pull Request を作成する:
   ```bash
   gh pr create --base {{BASE_BRANCH}} --head <current-branch> --title "<type>(<change-name>): <subject>" --body-file <pr-body-file>
   ```
4. ユーザーのマージ合意後、**Merge commit**（`--merge`）で統合し、ローカルブランチをクリーンアップする:
   ```bash
   gh pr merge <PR番号> --merge --delete-branch
   git checkout {{BASE_BRANCH}}
   git pull origin {{BASE_BRANCH}}
   git branch -d <current-branch>
   ```
