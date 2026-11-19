# Tasks: optimize-agy-models-and-skills

## 1. エージェント定義のモデル差異・権限拡張 (`openspec-kit/agents/`)

- [x] 1.1 `qa-tester` による先行 Red テスト作成: `openspec-kit/agents/*.md` の `model_tier`・`thinking`・`write_tools` メタデータ、Read-only ロールの親へのテキスト返却契約、および Gemini 3.8 Flash 非採用を検証するテスト（`UT-13`〜`UT-15`, `UT-19`）を `tests/` に追加し、`Invoke-Pester` で失敗（Red）を確認する
- [x] 1.2 `pg-implementer` による Green 実装・Refactor: `openspec-kit/agents/{user-reviewer,se-reviewer,pg-reviewer,qa-reviewer,qa-tester,pg-implementer}.md` に frontmatter（`model_tier`, `thinking`, `write_tools`）と本文の権限・返却契約を追加し、Task 1.1 のテストが全件 Pass（Green）することを確認する
- [x] 1.3 Group 1 レビュー & Gate 2 検証: `pg-reviewer` / `qa-reviewer` によるレビューを実施して `reviews.md` に記録（`LGTM: true`）し、`pwsh ./openspec/scripts/verify-gate.ps1 -Gate apply -ChangeName "optimize-agy-models-and-skills"` が `PASSED` になることを確認する

## 2. 5エージェント共通 Skills 化と `AGENTS.openspec.md` スリム化（`workflows/` は Group 3 まで維持）

- [ ] 2.1 `qa-tester` による先行 Red テスト作成: `openspec-kit/skills/sdd-{propose,apply,archive}` の自己完結構造・`sdd-*` 名前空間非衝突（`UT-01`, `UT-02`）、`references/` 要件・障害回復手順（`UT-16`, `UT-18`, `UT-20`, `IT-05`）、`scripts/*.py` AST・スタブ実行・直接 `python3` ガード `exit 2`（`UT-17`, `UT-21`）、`AGENTS.openspec.md` < 12,000B・合算 `<= 16,000B`（`UT-12`）、および `config.yaml`/`README.md` 旧参照除去（`UT-26`）のテストを追加し、失敗（Red）を確認する
- [ ] 2.2 `pg-implementer` によるスキル群作成: `openspec-kit/skills/sdd-{propose,apply,archive}/SKILL.md`、各スキル自己完結 `references/{antigravity-orchestration.md,sdd-reference.md}`、および `scripts/run_{propose,archive}_review.py`（直接実行ガード付き）を作成し、スキル構造・Python スクリプトテスト（`UT-01`, `UT-02`, `UT-16`〜`UT-21`, `IT-05`）の Green を確認する
- [ ] 2.3 `pg-implementer` による `AGENTS.openspec.md` スリム化・設定更新: `openspec-kit/AGENTS.openspec.md` を 12,000 バイト未満へ圧縮し、`openspec-kit/config.yaml` および `openspec-kit/README.md` のワークフロー参照を `.agents/skills/sdd-*` へ更新して、`UT-12`・`UT-26` を含む Group 2 テスト全件の Green を確認する
- [ ] 2.4 Group 2 レビュー & Gate 2 検証: `pg-reviewer` / `qa-reviewer` によるレビューを実施して `reviews.md` に記録（`LGTM: true`）し、`verify-gate.ps1 -Gate apply` が `PASSED` になることを確認する（この時点では既存 `workflows/` テストも維持される）

## 3. インストーラ（`install.ps1` / `install.sh`）多面展開・安全移行と旧 `workflows/` 廃止

- [ ] 3.1 `qa-tester` による先行 Red テスト作成: `tests/openspec-kit.install.Tests.ps1` および `tests/openspec-kit.sh.Tests.ps1` を新仕様へ更新し、境界値（`UT-03`〜`UT-11`, `UT-22`〜`UT-25`）・C2 デシジョンテーブル（`DT-01`〜`DT-10`）・状態遷移（`ST-01`〜`ST-04`）・結合テスト/Fault Injection（`IT-01`〜`IT-08`）・Zero-State/Recovery E2E（`E2E-02`, `E2E-03`）を実装して失敗（Red）を確認する
- [ ] 3.2 `pg-implementer` による PowerShell 版実装 & 旧 `workflows/` 廃止: `openspec-kit/install.ps1` に `-AgentTargets` 検証・5エージェント再帰展開（`.claude/agents/` 維持）・後段レガシー退避（衝突回避）・アトミック `AGENTS.md` 更新（破損検知・24KB 超過警告）・Zero-State/`-Force` 促し出力を実装し、`openspec-kit/workflows/` を削除して `Invoke-Pester ./tests/openspec-kit.install.Tests.ps1` 全件 Pass と `Invoke-ScriptAnalyzer` 警告ゼロを確認する
- [ ] 3.3 `pg-implementer` による Bash 版実装・Refactor: `openspec-kit/install.sh` に `--agent-targets` 検証・再帰展開・`awk` ベースリテラル置換・後段レガシー退避・アトミック `AGENTS.md` 更新を実装し、LF 改行・`bash -n` 構文チェックおよび `Invoke-Pester ./tests/openspec-kit.sh.Tests.ps1`（`IT-01` パリティ含む）全件 Pass を確認する
- [ ] 3.4 Group 3 レビュー & Gate 2 検証: `pg-reviewer` / `qa-reviewer`（L3 設計変更時は `se-reviewer`）によるレビューを実施して `reviews.md` に記録（`LGTM: true`）し、`verify-gate.ps1 -Gate apply` が `PASSED` になることを確認する

## 4. 本リポジトリ再同期と結合・E2E・カバレッジ最終検証

- [ ] 4.1 本リポジトリ再同期と後処理（`E2E-01`）: `pwsh ./openspec-kit/install.ps1 -TargetPath . -BaseBranch main -EvidenceDir test-results/ -AgentTargets all -Force -SkipConfig` を実行し、`openspec/config.yaml` の参照先を `.agents/skills/sdd-*` へ同期した上で、退避された旧 `.agents/workflows/sdd-*.md.bak*`（カスタム差分なし）を削除し、`AGENTS.md` < 24,000 バイトおよび 5 エージェントスキル展開を確認する
- [ ] 4.2 全体品質・カバレッジ・フェーズゲート最終検証: `npx prettier --write` / `Invoke-ScriptAnalyzer` / `bash -n` を通過させた後、`Invoke-Pester ./tests -CodeCoverage ./openspec-kit/install.ps1` を実行して全件 Pass（skip 0 件）・C0 90%+（C1/C2 テスト全通過）・`test-results/` エビデンス出力を確認し、`verify-gate.ps1 -Gate apply` / `verify-gate.sh` が `PASSED` になることを確認する

## Workflow follow-up

- 全タスク完了後、4 ロール総括レビュー・`handover.md` 作成・Gate 3 検証（`verify-gate.ps1 -Gate archive`）を経て `openspec archive "optimize-agy-models-and-skills"` を実行し、PR を作成する。
