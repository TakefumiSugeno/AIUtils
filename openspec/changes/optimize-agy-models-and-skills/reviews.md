# レビュー記録一覧: optimize-agy-models-and-skills

---

## Cycle 1: Propose レビュー (User Reviewer)

- **日時**: 2026-11-20
- **フェーズ**: propose
- **タスク**: Proposeフェーズ計画成果物レビュー（User Reviewer / Cycle 1）
- **レビュアー**: user (`openspec/agents/user-reviewer.md`)
- **使用プロトコル**: `openspec/templates/checklist_propose.md`
- **対象成果物**: `openspec/changes/optimize-agy-models-and-skills/{proposal.md,specs/**/spec.md,design.md,test_plan.md,tasks.md}`

### 1. 挑戦的設問への回答（ブラインド突合・初心者ペルソナ検証）

- **設問1（ブラインド比較突合）**: `proposal.md` から異常系・境界条件5点を先出し予測し、`specs/`・`design.md` と突合した結果、以下を指摘した。
  1. `--agent-targets` に `antigravity` を含まない明示指定時の `.agents/skills/` 扱いと退避実行可否の曖昧さ、Zero-State 案内欠落。
  2. レガシー退避後の `.bak` 確認・整理案内およびリネーム失敗時のエラーハンドリング欠落。
  3. 既存 `AGENTS.md` の管理区間外肥大化で 24,000B 超過時の振る舞い・警告欠落。
  4. `-Force` 未指定スキップ時の `AGENTS.md` とのバージョン不整合警告欠落、`sdd-reference.md` 配置先の未確定、`.claude/agents/` 維持方針の欠落。
  5. `run_workflow` 用 Python スクリプト直叩きガード欠落、Read-only レビュアーの `reviews.md` 転記契約の曖昧さ、並列実行エラー時の回復導線欠落。
- **設問2（都合の良い前提）**: 既存ユーザー記述が小さい前提、正しいフラグ・起動手順で使う前提、並列呼び出しが常に成功する前提を告発。
- **設問3（UIモック検証）**: 対象外（CLI・ドキュメント・導入スクリプト配布キット変更のため）。

### 2. Adversarial QA（破壊テスト実行結果）

対象外（Propose フェーズのため）

### 3. 指摘事項（Cycle 1）

- **指摘1 [Major]**: `--agent-targets` に `antigravity` を含まない明示指定時の `.agents/skills/` 配置・退避仕様矛盾 → **採用（対応済み: `spec.md`, `design.md`, `test_plan.md` で指定ターゲットのみ配置・`.agents/skills/` 有効時のみ退避に統一）**
- **指摘2 [Major]**: 既存 `AGENTS.md` 肥大化による 24,000 バイト超過時の異常系・回復導線欠落 → **採用（対応済み: `spec.md`, `design.md`, `test_plan.md` `UT-23` に超過警告と分割案内を追加）**
- **指摘3 [Major]**: `-Force` 未指定スキップ時の不整合警告と `.bak` 整理導線欠落 → **採用（対応済み: `spec.md`, `design.md`, `test_plan.md` `UT-22` に `-Force` 再実行促し警告と `.bak` 確認/削除案内を追加）**
- **指摘4 [Major]**: `run_workflow` スクリプト直接実行ガード、`write_tools: false` ロールの結果返却契約、並列失敗時の回復導線欠落 → **採用（対応済み: `antigravity-model-orchestration/spec.md`, `design.md`, `test_plan.md` `UT-21` に追記）**
- **指摘5 [Major]**: `sdd-reference.md` 配置方式の未確定と `.claude/agents/` 維持方針の欠落 → **採用（対応済み: 各スキル内 `references/sdd-reference.md` 自己完結配置と `.claude/agents/` 維持を確定）**
- **指摘6 [Minor]**: Zero-State 案内およびリネーム失敗時復旧案内 → **採用（対応済み: `spec.md`, `design.md`, `test_plan.md` `DT-02`, `IT-08`, `E2E-02` へ組み込み）**

### 4. 判定

- **LGTM**: false
- **次のアクション**: 計画成果物修正後、Cycle 2 再レビューへ

---

## Cycle 1: Propose レビュー (SE Reviewer)

- **日時**: 2026-11-20
- **フェーズ**: propose
- **タスク**: Proposeフェーズ計画成果物レビュー（SE Reviewer / Cycle 1）
- **レビュアー**: se (`openspec/agents/se-reviewer.md`)
- **使用プロトコル**: `openspec/templates/checklist_propose.md` (§2, §3, §5)
- **対象成果物**: `openspec/changes/optimize-agy-models-and-skills/{proposal.md,specs/**/spec.md,design.md,test_plan.md,tasks.md}`

### 1. 挑戦的設問への回答（故障シミュレーション・テスト死角・手戻り検証）

- **設問1（故障シミュレーション）**: 多面展開・`AGENTS.md` 更新の非アトミック性（退避先行による全滅リスク、片側マーカー破損時の二重追記、`install.sh` `sed` の `&`/`\`/`|` 破壊）、および並列 `run_workflow` / `swarm` のタイムアウト・競合対策欠落を指摘。
- **設問2（可観測性）**: 実導入時の 24KB 超過警告欠落、`.bak-<timestamp>` の同秒衝突、ターゲット解決・スキップ・退避診断サマリ不足を指摘。
- **設問3（テスト計画の死角トップ2）**: `config.yaml`/`README.md` の旧参照検査漏れ、`install.sh` 置換特殊文字テスト漏れ、および `IT-*` の実障害注入不足と C2 表条件抜けを指摘。
- **設問4（モックの嘘）**: `UT-17` の AST＋部分文字列検査の甘さと `UT-12` の現実余裕度不足を指摘。
- **設問5・6（タスク手戻り・完了基準）**: Task 2.2 での `workflows/` 削除による既存テスト破壊、C0/C1/Bash カバレッジ計測手段の不在、Task 1.2/2.3/4.1 完了基準および L2 レビュー/Gate 2 記載漏れを指摘。

### 2. Adversarial QA（破壊テスト実行結果）

対象外（Propose フェーズのため）

### 3. 指摘事項（Cycle 1）

- **指摘1 [Critical]**: インストーラの実行順序・アトミック書き換え・片側マーカー破損防止・`sed` エスケープ安全性不足 → **採用（対応済み: `spec.md`, `design.md`, `test_plan.md` `UT-24`, `UT-25`, `IT-06`, `IT-07` へ反映）**
- **指摘2 [Major]**: `run_workflow` API 契約および並列失敗・`swarm` 競合回避方針の欠落 → **採用（対応済み: `design.md`, `antigravity-model-orchestration/spec.md`, `test_plan.md` `UT-17`, `UT-18`, `IT-05` へ反映）**
- **指摘3 [Major]**: 可観測性サマリ・24KB 超過警告・`.bak` 同秒衝突回避・整理方針の明確化 → **採用（対応済み: `design.md`, `spec.md`, `test_plan.md` `UT-10`, `UT-23`, `tasks.md` 4.1 へ反映）**
- **指摘4 [Major]**: Fault Injection・C2 表補完・`config.yaml`/`README.md` 旧参照検査・Python スタブ実行検証の拡充 → **採用（対応済み: `test_plan.md` `UT-17`, `UT-21`, `UT-26`, `DT-01`〜`DT-10`, `IT-05`〜`IT-08` へ反映）**
- **指摘5 [Major]**: `tasks.md` の依存逆転（`workflows/` 削除タイミング）解消・カバレッジ計測定義・L2 レビュー/Gate 2 明記 → **採用（対応済み: `tasks.md` Group 1〜4 再編、`test_plan.md` §1 計測手段明確化）**
- **指摘6 [Minor]**: `.openspec.yaml` の `x-level: L2` と `verify-gate` の `level:` キー差異 → **保留（申し送り: `proposal.md` L5 の `L2` 表記により `verify-gate` は正しく `L2` 判定されるため機能影響なし。Archive 時 `handover.md` に転記）**

### 4. 判定

- **LGTM**: false
- **保留指摘（申し送り）**: SE 指摘6（Minor）
- **次のアクション**: 計画成果物修正後、Cycle 2 再レビューへ

---

## Cycle 2: Propose 再レビュー (User Reviewer)

- **日時**: 2026-11-20
- **フェーズ**: propose
- **タスク**: Proposeフェーズ計画成果物再レビュー（User Reviewer / Cycle 2）
- **レビュアー**: user (`openspec/agents/user-reviewer.md`)
- **使用プロトコル**: `openspec/templates/checklist_propose.md`
- **対象成果物**: `openspec/changes/optimize-agy-models-and-skills/{proposal.md,specs/**/spec.md,design.md,test_plan.md,tasks.md}`

### 1. 挑戦的設問への回答（Cycle 1 指摘の再検証・ブラインド突合確認）

- **設問1（ブラインド比較突合）**: Cycle 1 で指摘した 5 点の異常系・境界条件および仕様間の不整合（明示ターゲット指定時の `.agents/skills/` 扱いと Zero-State 案内、後段退避と衝突回避・失敗復旧、`AGENTS.md` 24KB 超過警告・破損検知、`-Force` スキップ警告・`sdd-reference.md` 自己完結・`.claude/agents/` 維持、`run_workflow` 直叩きガード・Read-only 返却契約・単一ライター原則・並列失敗回復）がすべて `specs/`・`design.md`・`test_plan.md`・`tasks.md` へ反映・統一されたことを確認した。
- **設問2（都合の良い前提）**: 暗黙の仮定はすべて異常系要件・警告・回復導線として解消された。
- **設問3（UIモック検証）**: 対象外（CLI・ドキュメント・導入スクリプト配布キット変更のため）。

### 2. Adversarial QA（破壊テスト実行結果）

対象外（Propose フェーズのため）

### 3. 指摘事項（Cycle 2）

なし（理由: Cycle 1 の Major 指摘 5 件・Minor 指摘 1 件がすべて整合性を保って反映されたことを確認済み）

### 4. 判定

- **LGTM**: true
- **保留指摘（申し送り）**: なし
- **次のアクション**: SE Reviewer 承認および Gate 1 通過後に Apply 開始

---

## Cycle 2: Propose 再レビュー (SE Reviewer)

- **日時**: 2026-11-20
- **フェーズ**: propose
- **タスク**: Propose フェーズ再レビュー（SE Reviewer / Cycle 2）
- **レビュアー**: se (`openspec/agents/se-reviewer.md`)
- **使用プロトコル**: `openspec/templates/checklist_propose.md` (§2, §3, §5)
- **対象成果物**: `openspec/changes/optimize-agy-models-and-skills/{proposal.md,specs/**/spec.md,design.md,test_plan.md,tasks.md}`

### 1. 挑戦的設問への回答（故障シミュレーション・テスト死角・手戻り検証）

- **設問1（故障シミュレーション）**: 事前検証と「新スキル展開全成功後の後段退避」順序、`install.sh` の `awk` 純粋リテラル置換、`AGENTS.md` 一時ファイル経由アトミック置換・片側マーカー破損検知、および `run_workflow` API 契約・直接実行ガード・並列失敗時単体再実行・`swarm` 1ワーカー1ファイル群分離が設計されたことを確認した。
- **設問2（可観測性）**: 展開サマリ、`-Force` 推奨警告、Zero-State 案内、`.bak-<timestamp>-<counter>` 衝突回避、24KB 超過警告が補完された。
- **設問3・4（テスト計画の死角・モックの嘘）**: `UT-21`〜`UT-26`、`DT-01`〜`DT-10`、Fault Injection `IT-06`〜`IT-08`、Python 直叩き `exit 2`＋スタブ注入実行検証が追加され、18 シナリオ 100% トレーサビリティを確認した。
- **設問5・6（タスク手戻り・完了基準）**: Group 2 で `workflows/` を維持し Group 3（テスト先行更新後）で廃止する順序に是正され、カバレッジ計測手段と L2 レビュー／Gate 2 タスクが明確化された。

### 2. Adversarial QA（破壊テスト実行結果）

対象外（Propose フェーズのため）

### 3. 指摘事項（Cycle 2）

- **指摘1 [Minor]**: Cycle 1 指摘 1〜5 解消確認済み。
- **指摘2 [Minor / 保留]**: (1) `UT-12` / `UT-26` の本リポジトリ側ファイル検査は Task 4.1 (`E2E-01`) で実施し、Group 2 テストは `openspec-kit/` と新規生成結果のみを対象とすること。(2) `AGENTS.md` 一時ファイルはアトミック性維持のため必ず `AGENTS.md` と同一ディレクトリに作成すること。

### 4. 判定

- **LGTM**: true
- **保留指摘（申し送り）**: Cycle 1 指摘 6（`.openspec.yaml` の `x-level: L2` と `verify-gate` の `level:` キー差異）、および本 Cycle 2 指摘 2（`UT-12`/`UT-26` 対象分離、一時ファイル同一ディレクトリ配置）を Apply 時留意および Archive 時 `handover.md` へ転記
- **次のアクション**: Gate 1 検証・ユーザー合意後に Apply へ進む

---

## Group 1 Apply レビュー Cycle 1: Task 1.3 (PG Reviewer / QA Reviewer)

- **日時**: 2026-11-20
- **フェーズ**: apply
- **タスク**: Task 1.3（Group 1: `openspec-kit/agents/*.md` & `tests/openspec-kit.agents-skills.Tests.ps1`）
- **レビュアー**: pg (`openspec/agents/pg-reviewer.md`) & qa (`openspec/agents/qa-reviewer.md`)
- **使用プロトコル**: `openspec/templates/checklist_apply_impl.md`, `openspec/templates/checklist_apply_test.md`
- **対象成果物**: `openspec-kit/agents/*.md`, `tests/openspec-kit.agents-skills.Tests.ps1`

### 1. 挑戦的設問・Adversarial QA 要約

- **PG Reviewer**: `openspec-kit/agents/*.md` の frontmatter と単一ライター返却契約の整合を確認しつつ、末尾契約セクションの重複（frontmatter 値再掲・Gemini 4/3.8 Flash 設計メモコピペ）・`qa-reviewer.md` の破壊テスト一時ファイル後始末/非コード例外規定・`pg-implementer.md` L30 用語不統一を改善提案（Minor）。
- **QA Reviewer（破壊テスト実行）**: 一時スクラッチハーネス（ミューテーション `M1`〜`M5`・敵対的入力 `A1`〜`A9`・パーサ境界 `P1`〜`P5`）を実行し、`UT-19` の YAML リスト/`3.8-flash`/ホワイトリストすり抜け・`Get-ParsedAgent` のネストキー上書き/EOF閉じ/クォートコメント分離バグ・`UT-13`〜`UT-15` の契約チェック穴を検出（**バグ検出 / Red**）。

### 2. 指摘事項・対応（Cycle 1）

- **PG 指摘1〜3 [Minor / Suggestion]**: 重複50%削減、破壊テスト後始末＆非コード例外明記、`pg-implementer.md` 用語統一 → **採用（`pg-implementer` により修正済み）**
- **QA 指摘1〜3 [Major] & 指摘4 [Minor]**: `UT-19` の `RawFrontmatter` 検査・`3.8-flash`・肯定採用文脈判定、`ConvertFrom-AgentMarkdown` パーサ堅牢化、`UT-13`〜`UT-15` 同一論理項目・同一文契約検査、`Pester >= 5.0.0` 明示 → **採用（`qa-tester` により修正済み）**

### 3. 判定

- **LGTM**: false
- **次のアクション**: 修正後 Cycle 2 再レビューへ

---

## Group 1 Apply 再レビュー Cycle 2: Task 1.3 (PG Reviewer / QA Reviewer)

- **日時**: 2026-11-20
- **フェーズ**: apply
- **タスク**: Task 1.3（Group 1 Cycle 2 再レビュー）
- **レビュアー**: pg & qa
- **使用プロトコル**: `openspec/templates/checklist_apply_impl.md`, `openspec/templates/checklist_apply_test.md`
- **対象成果物**: `openspec-kit/agents/*.md`, `tests/openspec-kit.agents-skills.Tests.ps1`

### 1. 挑戦的設問への回答

- **PG Reviewer**: 重複50%削減・`qa-reviewer.md` の一時ファイル後始末＆非コード例外明記・`pg-implementer.md` 用語統一・Read-only 単一ライター契約順守をすべて確認。
- **QA Reviewer**: 修正後の全ヘルパー関数に対する敵対的スクラッチ検証で、`A1`〜`A9`, `P1`〜`P5`, `C2-1`, `C2-2`, `C2-4` すべて期待通り検出/通過し、実ファイル Baseline 失敗 0 件を確認。

### 2. Adversarial QA（破壊テスト実行結果）

- **対象関数/モジュール**: `tests/openspec-kit.agents-skills.Tests.ps1`（`ConvertFrom-AgentMarkdown`, `Get-ParsedAgent`, `Get-MarkdownLogicalBlocks`, `Test-HasSingleWriterReturnContract`, `Get-DeprecatedGemini38Violations`）および `openspec-kit/agents/*.md`
- **破壊テストコード名**: 一時スクラッチハーネス（`verify_cycle2.ps1`、テスト完了後に削除済み）
- **実行コマンド**: `pwsh -NoProfile -File "<scratch>/verify_cycle2.ps1"` および `pwsh -Command "Import-Module Pester -MinimumVersion 5.0; Invoke-Pester ./tests -Output Normal"`
- **実行判定**: 堅牢性確認（全破壊・ミューテーション入力を期待通り検出し、実ファイル全 56 テスト Pass / Skip 0 件）
- **実行ログ要約**:

```text
Baseline failures: 0
A1/A2/A3 (UT-19 bypass): [FAIL] detected | A4 (legit deprecation): [PASS]
A5/P1/A6/P2/P5 (YAML parser edge): [PASS] | A8/A9/C2-1/C2-2 (contract bypass): [FAIL] detected
Invoke-Pester ./tests: Tests Passed: 56, Failed: 0, Skipped: 0
```

### 3. 指摘事項

- **QA 指摘1 [Suggestion / 任意]**: 英語肯定文脈併用ケース（`C2-3`）の検出余地（日本語規約のため実害なし）。Critical / Major 指摘 0 件。

### 4. 判定

- **LGTM**: true
- **保留指摘（申し送り）**: なし
- **次のアクション**: Gate 2 通過後、Task 1.1〜1.3 を完了とし Group 2 へ進む

---

## Group 2 Apply レビュー Cycle 1: Task 2.4 (PG Reviewer / QA Reviewer)

- **日時**: 2026-11-20
- **フェーズ**: apply
- **タスク**: Task 2.4（Group 2: `openspec-kit/skills/**`, `AGENTS.openspec.md`, `config.yaml`, `README.md`, `tests/openspec-kit.agents-skills.Tests.ps1`）
- **レビュアー**: pg (`openspec/agents/pg-reviewer.md`) & qa (`openspec/agents/qa-reviewer.md`)
- **使用プロトコル**: `openspec/templates/checklist_apply_impl.md`, `openspec/templates/checklist_apply_test.md`
- **対象成果物**: `openspec-kit/skills/**`, `openspec-kit/AGENTS.openspec.md`, `openspec-kit/config.yaml`, `openspec-kit/README.md`, `tests/openspec-kit.agents-skills.Tests.ps1`

### 1. 挑戦的設問・Adversarial QA 要約

- **PG Reviewer**: `run_propose_review.py` / `run_archive_review.py` にて `args` 未指定・空文字時に `"<change-name>"` へサイレントフォールバックする欠陥および空白/パストラバーサル（`"../foo"`）無検証を指摘（Major）。また冗長な辞書定義と `phase` 分岐を `ROLES` タプル＋定数＋`contextlib.nullcontext` に整理して約35%削減するリファクタ案（Minor）および `sdd-propose/SKILL.md` ステップ 4 の L1 条件明記（Suggestion）を提示。
- **QA Reviewer（破壊テスト実行）**: `adv_test_scripts.py` と `mut_test.ps1` により、`{"change_name": "   "}` や `{"change_name": "../evil"}` で不正パスのプロンプトが生成されてサブエージェントが起動してしまうバグを実証（**バグ検出 / Red**）。また `UT-17` の `in_parallel` / `in_phase` 未アサート、`UT-16` の否定文（「のみではなく」）すり抜け、`UT-26` の「移行」1語による免除穴、`UT-12` の BOM 不在アサーション欠落を指摘。

### 2. 指摘事項・対応（Cycle 1）

- **PG 指摘1 & QA 指摘1 [Major]**: `run_*_review.py` の `callable` ガード強化、`_resolve_change_name()` の `"<change-name>"` サイレントフォールバック廃止、`^[A-Za-z0-9][A-Za-z0-9._-]*$` ホワイトリストによる `ValueError` 即時拒否 → **採用（`pg-implementer` により修正済み）**
- **PG 指摘2 [Minor] & 指摘3 [Suggestion]**: `run_*_review.py` の約35〜41%コード削減リファクタおよび `sdd-propose/SKILL.md` L1 条件明記 → **採用（`pg-implementer` により修正済み）**
- **QA 指摘2 & 3 [Major] & 指摘4 [Minor]**: `UT-17` の `in_parallel` / `in_phase` アサートおよび不正 `args` 7パターン `ValueError` 拒否テスト追加、`UT-16` の否定反転拒否、`UT-26` の `config.yaml` 非コメント無条件禁止・`README.md` 肯定文脈拒否、`UT-12` の UTF-8 BOM 不在アサート、`UT-01` の相対リンク `..` 禁止 → **採用（`qa-tester` により修正済み）**

### 3. 判定

- **LGTM**: false
- **次のアクション**: 修正後 Cycle 2 再レビューへ

---

## Group 2 Apply 再レビュー Cycle 2: Task 2.4 (PG Reviewer / QA Reviewer)

- **日時**: 2026-11-20
- **フェーズ**: apply
- **タスク**: Task 2.4（Group 2 Cycle 2 再レビュー）
- **レビュアー**: pg & qa
- **使用プロトコル**: `openspec/templates/checklist_apply_impl.md`, `openspec/templates/checklist_apply_test.md`
- **対象成果物**: `openspec-kit/skills/**`, `openspec-kit/AGENTS.openspec.md`, `openspec-kit/config.yaml`, `openspec-kit/README.md`, `tests/openspec-kit.agents-skills.Tests.ps1`

### 1. 挑戦的設問への回答

- **PG Reviewer**: `run_propose_review.py`（91行→65行）および `run_archive_review.py`（103行→67行）の `callable` ガード、`fullmatch` による Fail-Fast `ValueError` 送出、`nullcontext` による重複排除、および `sdd-propose/SKILL.md` の L1/L2/L3 条件整合を確認。
- **QA Reviewer**: 2スクリプト×16ケース＝32ケースの敵対的破壊テストおよび `UT-16` / `UT-26` ミューテーション再注入テストを実行し、全異常入力が `agents=0` で拒否され、全ミューテーションが確実に検出されることを確認。

### 2. Adversarial QA（破壊テスト実行結果）

- **対象関数/モジュール**: `run_propose_review.py`, `run_archive_review.py`, `tests/openspec-kit.agents-skills.Tests.ps1`
- **破壊テストコード名**: 一時スクラッチ `adv_test_cycle2.py`（32ケース）および `mut_test_cycle2.ps1`（検証後に削除済み）
- **実行コマンド**: `python "<scratch>/adv_test_cycle2.py"`、`pwsh -NoProfile -File "<scratch>/mut_test_cycle2.ps1"`、および `Invoke-Pester ./tests/openspec-kit.agents-skills.Tests.ps1`
- **実行判定**: 堅牢性確認（Green / 落とせず、全 54 テスト Pass / 全体 96 テスト Pass）
- **実行ログ要約**:

```text
propose/archive 16 adversarial cases each (missing, none, empty, whitespace, ../evil, .hidden, -flag, foo/bar, foo\bar, newline, int, non-callable): all rejected with ValueError or exit 2 (agents=0)
UT-26 Mut1/Mut2: violations=1 (detected) | Valid retirement note: violations=0
UT-16 Mut1/Mut2: pass=False (detected) | Valid single writer: pass=True
Invoke-Pester ./tests/openspec-kit.agents-skills.Tests.ps1: Tests Passed: 54, Failed: 0, Skipped: 0
```

### 3. 指摘事項

なし（理由: Cycle 1 の全指摘が解消され、破壊テスト32ケースおよびミューテーション検証で堅牢性を確認済み）

### 4. 判定

- **LGTM**: true
- **保留指摘（申し送り）**: なし
- **次のアクション**: Gate 2 通過後、Task 2.1〜2.4 を完了とし Group 3 へ進む

---

## Group 3 Apply レビュー Cycle 1: Task 3.4 (PG Reviewer / QA Reviewer)

- **日時**: 2026-11-21
- **フェーズ**: apply
- **タスク**: Task 3.4（Group 3: `openspec-kit/install.ps1`, `install.sh`, `sdd-reference.md` L94, `workflows/` 削除, `tests/openspec-kit.{install,sh}.Tests.ps1`）
- **レビュアー**: pg (`openspec/agents/pg-reviewer.md`) & qa (`openspec/agents/qa-reviewer.md`)
- **使用プロトコル**: `openspec/templates/checklist_apply_impl.md`, `openspec/templates/checklist_apply_test.md`
- **対象成果物**: `openspec-kit/install.ps1`, `openspec-kit/install.sh`, `openspec-kit/skills/sdd-propose/references/sdd-reference.md`, `tests/openspec-kit.{install,sh}.Tests.ps1`

### 1. 挑戦的設問・Adversarial QA 要約

- **PG Reviewer**: `install.ps1` のマーカー多重破損検知抜け、`install.ps1` と `install.sh` の `end` 後空行・同一行テキスト保持不整合、`install.sh` の `TMP_AGENTS` に `trap` クリーンアップ欠如（Major 3件）、および `mv 2>/dev/null`・`chmod` 握りつぶし・`grep --` 欠如・重複削減リファクタ（Minor/Suggestion 3件）を指摘。
- **QA Reviewer（破壊テスト実行）**: `advqa_test.ps1` / `advqa_test2.ps1` を実実行し、① `BaseBranch = '{{EVIDENCE_DIR}}'` の二重置換（`Test E`）、② `two_begins_one_end` 破損 `AGENTS.md` の通過（`Test B`）、③ `SKILL.md` / `CLAUDE.md` ファイル位置の既存ディレクトリ衝突時の途中失敗（`Test F` / `Test H1`）、④ `BaseBranch = "feat/it's-broken"` 展開による `verify-gate.ps1` 構文エラー 15 件（`Test [3]`）を実測実証（**バグ検出 / Red**）。あわせて `install.sh` 同一行逆転・改行混入等（指摘5）およびテストのミューテーション死角・アサーション漏れ（`[DT-07]` の `[skip]` 誤マッチ、`[IT-01]` 改行正規化、`[UT-23]`/`[UT-24]`/`[IT-07]` 不足：指摘6）を指摘。

### 2. 指摘事項・対応（Cycle 1）

- **PG 指摘1〜3 & QA 指摘1〜5 [Major]**: 1 パス同時置換、`.ps1` `'`→`''` エスケープ、改行/NUL 事前拒否、マーカー回数・位置検証統一、`AGENTS.md` 文字位置切り出し＆空行保持の PS/Bash 完全パリティ、`install.sh` `mktemp` + `trap`、ファイル位置ディレクトリ衝突事前検証、診断出力・重複削減リファクタ → **採用（`pg-implementer` により修正済み）**
- **QA 指摘6 [Major] & 指摘7 [Minor]**: `[DT-07]` 行単位厳格マッチング、`[IT-01]` 生バイト比較＋空行再同期パリティ、`[UT-23]` 23,999B/24,000B 境界、`[UT-24]` 6 パターン、`[UT-25]` 二重置換・`'`・`\n`、`[IT-06]`/`[IT-07]`/`[DT-01]`/`[DT-10]` 補完、`Invoke-Bash` の `MSYS=noglob`＋クォート修正 → **採用（`qa-tester` により修正済み）**

### 3. 判定

- **LGTM**: false
- **次のアクション**: 修正後 Cycle 2 再レビューへ

---

## Group 3 Apply 再レビュー Cycle 2: Task 3.4 (PG Reviewer / QA Reviewer)

- **日時**: 2026-11-21
- **フェーズ**: apply
- **タスク**: Task 3.4（Group 3 Cycle 2 再レビュー）
- **レビュアー**: pg & qa
- **使用プロトコル**: `openspec/templates/checklist_apply_impl.md`, `openspec/templates/checklist_apply_test.md`
- **対象成果物**: `openspec-kit/install.ps1`, `openspec-kit/install.sh`, `openspec-kit/skills/sdd-propose/references/sdd-reference.md`, `tests/openspec-kit.{install,sh}.Tests.ps1`

### 1. 挑戦的設問への回答

- **PG Reviewer**: マーカー回数・位置検証の統一、`render_agents_md` と PS 版の切り出し・空行保持パリティ、`mktemp`+`trap`、1 パス置換・エスケープ・全ファイル位置衝突事前チェック・エラー診断出力・共通化リファクタを確認し、テスト改ざんなしを確認。
- **QA Reviewer**: Cycle 1 でバグ検出した全攻撃ケースを再実行し、すべて適切にエラー拒否・無変更・構文エラー 0 件で防がれること、および `[DT-07]` 警告行アサーションや `[IT-01]` バイト一致テストの強化を確認。

### 2. Adversarial QA（破壊テスト実行結果）

- **対象関数/モジュール**: `openspec-kit/install.ps1`（および `install.sh` 静的精査＋親環境 `sh.Tests.ps1` 全 38 件 Pass）
- **破壊テストコード名**: 一時スクラッチ `advqa_cycle2.ps1`（検証終了後に削除済み）
- **実行コマンド**: `pwsh -NoProfile -File "<scratch>\advqa_cycle2.ps1"` および `Import-Module Pester -MinimumVersion 5.0; Invoke-Pester ./tests -Output Normal`
- **実行判定**: 堅牢性確認（Green / 落とせず、全 4 スイート 151/151 テスト Pass / Skip 0 件）
- **実行ログ要約**:

```text
[Test B/B2: duplicate/same-line-rev markers] THREW (Expected, no partial writes)
[Test E: BaseBranch={{EVIDENCE_DIR}}] literal preserved?: True, no double-sub?: True
[Test F/H1: SKILL.md or CLAUDE.md as Dir] THREW before writes (Partial templates created?: False)
[Test 3: BaseBranch="feat/it's-broken"] verify-gate.ps1 parseErrors=0
[Test 4: BaseBranch with newline] THREW before writes (Partial templates created?: False)
[Test 5: DT-07 warning regex match] matchCount=1 (matched warning line only)
Invoke-Pester ./tests: Tests Passed: 151, Failed: 0, Skipped: 0 (agents-skills:54, install:46, sh:38, verify-gate:13)
```

### 3. 指摘事項

- **PG 指摘1 [Suggestion / 任意]**: `install.sh` 内の `awk` ブロック間の小規模重複（動作・安全性問題なしのため現状維持）。Critical / Major / Minor 指摘 0 件。

### 4. 判定

- **LGTM**: true
- **保留指摘（申し送り）**: なし
- **次のアクション**: Gate 2 通過後、Task 3.1〜3.4 を完了とし Group 4（本リポジトリ再同期と最終検証）へ進む
