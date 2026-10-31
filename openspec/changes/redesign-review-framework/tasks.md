# Tasks: redesign-review-framework

## 1. レビューテンプレートの刷新

- [ ] 1.1 `openspec-kit/templates/checklist_propose.md` を表形式から「ブラインド比較・故障シミュレーション・テスト死角・せっかち初心者ペルソナ」の成果物別挑戦的設問へ刷新し、Markdown構文を確認する
- [ ] 1.2 `openspec-kit/templates/checklist_apply_impl.md` を表形式から「Adversarial QA（破壊テスト実行）」および「30%コード削減・過剰抽象化告発」の設問へ刷新し、Markdown構文を確認する
- [ ] 1.3 `openspec-kit/templates/checklist_apply_test.md` を表形式から「トートロジー（実装式コピペ）告発」および「甘いアサーション・無意味なモックの告発」へ刷新し、Markdown構文を確認する
- [ ] 1.4 `openspec-kit/templates/checklist_archive.md` を表形式から「隠された技術的負債・妥協点の自白」および「初見エンジニア視点のWhy欠落告発」へ刷新し、Markdown構文を確認する
- [ ] 1.5 `openspec-kit/templates/review_record.md` を新設問回答形式および破壊テスト実行ログ記録形式へ刷新し、Markdown構文を確認する

## 2. レビュアーサブエージェントプロンプトの改修

- [ ] 2.1 `openspec-kit/agents/qa-reviewer.md` を単なるカバレッジ確認から「対象コードを例外終了・失敗させる破壊テストを作成・実行して客観評価するエージェント」へ改修し、役割定義を確認する
- [ ] 2.2 `openspec-kit/agents/pg-reviewer.md` を「暗黙の仮定・手抜き実装の告発および30%コード削減を提案するエージェント」へ改修し、役割定義を確認する
- [ ] 2.3 `openspec-kit/agents/se-reviewer.md` を「外部依存ハング・通信瞬断時の連鎖崩壊をシミュレートするエージェント」へ改修し、役割定義を確認する
- [ ] 2.4 `openspec-kit/agents/user-reviewer.md` を「せっかち初心者視点でデータ0件・エラー時の手抜きUIを告発するエージェント」へ改修し、役割定義を確認する

## 3. フェーズゲート検証スクリプトの改修と検証

- [ ] 3.1 `tests/` 配下に新レビュー形式（設問回答・破壊テストログ・LGTM）を検証する Pester テスト（先行Redテスト）を作成し、現行スクリプトで失敗することを確認する
- [ ] 3.2 `openspec-kit/scripts/verify-gate.ps1` の `Assert-ReviewsValid` を改修し、旧表形式チェックを廃止して新形式を検証可能にし、Pester テストが Pass（Green）することを確認する
- [ ] 3.3 `openspec-kit/scripts/verify-gate.sh` の `assert_reviews_valid` を改修し、`bash -n` 構文検査および動作確認を実行する

## 4. 設定・ワークフローの同期と総合検証

- [ ] 4.1 `openspec-kit/config.yaml`、`openspec/config.yaml`、`AGENTS.md`、`.agents/workflows/sdd-*.md` のレビュー運用ガイダンスを改定し、機械判定項目のLLMレビュー分離を明記する
- [ ] 4.2 `pwsh ./openspec-kit/install.ps1 -TargetPath . -BaseBranch main -EvidenceDir test-results/ -Force -SkipConfig` を実行して `openspec/` 側へ再同期し、差分がないことを確認する
- [ ] 4.3 `pwsh ./openspec/scripts/verify-gate.ps1 -Gate propose -ChangeName redesign-review-framework` および Pester テスト全件を実行し、エラー0件で通過することを確認する

## Workflow follow-up

- Archive the change after the project's review requirements are satisfied.
- Push the branch and create a pull request with `gh pr create`.
