# 申し送り事項 (Handover): redesign-review-framework

- **変更名**: `redesign-review-framework`
- **日付**: 2026-11-01
- **ブランチ**: `feature/OpenSpec`
- **関連 Issue / PR**: なし

---

## 1. 変更サマリ

OpenSpecフレームワークにおいて運用上「レビュー指摘がほとんど発生しない（形骸化・オールグリーン化）」問題に対処するため、レビューフレームワークを根本再設計しました。
「成果物の種類（7種）」×「4つのアプローチ案（Adversarial QA・悪魔の代弁者・ブラインド仕様比較・特化ペルソナ）」のマトリックス検討を経て、各成果物に最適な批判的レビュープロトコルを配置しました。
従来の表形式記号埋め（`?/?/??`）を廃止し、挑戦的設問回答・Adversarial QA（破壊テスト実行型判定）へ移行するとともに、リンター・フォーマット・テスト合否・カバレッジ等の機械的チェックを `verify-gate.ps1` / `verify-gate.sh` へ完全委譲しました。

---

## 2. 品質・テストエビデンス

- **単体テスト / ゲート自動テスト**: `Invoke-Pester -Output Detailed` → 42 件 Pass（失敗 0 / スキップ 0）
  - `tests/openspec-kit.install.Tests.ps1`: 17 テスト PASS
  - `tests/openspec-kit.sh.Tests.ps1`: 9 テスト PASS
  - `tests/openspec-kit.verify-gate.Tests.ps1`: 16 テスト PASS
- **ゲート検証**:
  - Gate 1 (propose): PASS
  - Gate 2 (apply): PASS
  - Gate 3 (archive): PASS
- **エビデンス出力先**: `test-results/` (Git 管理外)

---

## 3. 保留指摘・技術的負債

| 指摘元（フェーズ/タスク/役割） | 内容 | 保留理由                        | 推奨対応時期 |
| ------------------------------ | ---- | ------------------------------- | ------------ |
| 全フェーズ・全役割             | なし | 全観点 LGTM（指摘全件解消済み） | なし         |

---

## 4. 将来の改善・リファクタ候補

- **多言語対応**: 現在の `verify-gate` スクリプト（PowerShell 7 / Bash）に加え、Python や Node.js プロジェクト向けに言語組み込み型のゲート検証スクリプトや GitHub Actions / CI テンプレートの拡充。
- **Adversarial QA の自動足場生成**: テストコード生成時に、破壊テスト用の入力パターン（異常値・極端値）を半自動で提案するアシスタントツールの検討。

---

## 5. 運用上の注意事項

- **正本同期ルール**: `openspec-kit/` が配布用の正本です。キットのテンプレートやスクリプトを更新した場合は、必ず `pwsh ./openspec-kit/install.ps1 -TargetPath . -BaseBranch main -EvidenceDir test-results/ -Force -SkipConfig` を実行して自リポジトリ側へ同期してください。
- **破壊テストのクリーンアップ**: Adversarial QA で作成された破壊テストは、正式な回帰テストとしてテストスイートに追加するか、レビュー完了後に破棄してください（テストスイートを汚染しないこと）。
