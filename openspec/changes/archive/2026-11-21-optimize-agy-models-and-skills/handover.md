# 申し送り事項 (Handover): optimize-agy-models-and-skills

- **変更名**: `optimize-agy-models-and-skills`
- **日付**: 2026-11-21
- **ブランチ**: `feature/optimize-agy-models-and-skills`
- **関連 Issue / PR**: GitHub Issue #2（`[機能改善]OpenSpecのAntigravity CLI(Gemini CLI)用の改善` / `https://github.com/TakefumiSugeno/AIUtils/issues/2`）

---

## 1. 変更サマリ

OpenSpec 拡張キット（`openspec-kit`）および本リポジトリの OpenSpec 運用基盤について、以下の 2 点を実現するためにワークフロー資産・エージェント定義・配布スクリプト・ドキュメント・自動テストを刷新した（設計背景と却下案トレードオフの詳細は `design.md` および `openspec-kit/README.md` を参照）。

1. **Antigravity CLI における Gemini 4 モデル役割分担と権限制御の最適化**:
   - `openspec-kit/agents/*.md` の YAML frontmatter に `model_tier`（`pro` / `flash`）・`thinking`（`high` / `medium`）・`write_tools`（`false` / `true`）および単一ライター返却契約を追加した（これら frontmatter は CLI ネイティブ自動解釈構文ではなく、親エージェント／オーケストレータが読み取り `define_subagent` / `invoke_subagent` / プロンプト指示へ反映する運用規約メタデータ）。
   - 計画検証・設計・批判的レビュー 4 ロール（`user/se/pg/qa-reviewer`）を推論重視の **`pro`（Gemini 4 Neon 級）**、高速反復が必要な開発系（`qa-tester` は境界値網羅のため `flash` / `thinking: high`、`pg-implementer` は高速 Green 反復のため `flash` / `thinking: medium`）を **`flash`（Gemini 4 Hydrogen 級）** へ分離し、非推奨の **Gemini 3.8 Flash** 指定を全面排除した。また `qa-reviewer` のみ Adversarial QA の破壊テスト実行のため `write_tools: true`（ただし既存テスト・実装・`reviews.md` 編集禁止）、他レビュアー 3 ロールは `write_tools: false` で物理分離した。
   - Antigravity 専用オーケストレーション手順（`references/antigravity-orchestration.md`）および `run_workflow` 用並列レビュー起動スクリプト（`scripts/run_propose_review.py`, `scripts/run_archive_review.py`）を追加した。
2. **5 エージェント横断対応の Agent Skills 化と配布スクリプト刷新**:
   - Antigravity CLI・Claude Code・GitHub Copilot CLI・OpenCode CLI・Hermes Agent の 5 エージェント横断配布を実現するため、非推奨の旧 `.agents/workflows/sdd-*.md` を廃止し、Plugin 方式（`.claude-plugin` / `.opencode/plugins` / Hermes `plugin.yaml` で仕様が 3 分裂し保守不能）を不採用として、5 エージェント共通で機能する **Agent Skills（`SKILL.md`＋`references/`・`scripts/` の Progressive Disclosure 構成）** へ統一した。
   - `openspec-kit/install.ps1` / `openspec-kit/install.sh` に `-AgentTargets` / `--agent-targets`（**既定値 `auto`**、`all`、または `antigravity,claude,copilot,opencode,hermes` の CSV）を追加し、5 ターゲット（`.agents/skills/`, `.claude/skills/`, `.github/skills/`, `.opencode/skills/`, `.hermes/skills/`）への展開、`claude` 指定・検出時または `.claude/` 既存時の `.claude/agents/` 展開（初回未生成バグを修正済み）、旧 `.agents/workflows/sdd-*.md` の衝突回避付き `.bak` 退避、およびマーカー領域のアトミック更新を実装した。
   - Antigravity CLI のルール 1 ファイル **24,000 バイト上限（超過時は末尾切り捨てにより後続ルールが欠落する実害）** を回避するため、`openspec-kit/AGENTS.openspec.md` を `11,502` バイトへスリム化し、生成 `AGENTS.md` を約 15.7 KB に抑えた。

---

## 2. 品質・テストエビデンス

- **単体・結合・E2E テスト（Pester 5+）**: `Import-Module Pester -MinimumVersion 5.0; Invoke-Pester ./tests` → **155 件 Pass（失敗 0 件 / スキップ 0 件 / Inconclusive 0 / NotRun 0）**
  - `tests/openspec-kit.agents-skills.Tests.ps1`: **55 件 Pass**（リポジトリ実体同期・24KB 未満検証 `E2E-01` を含む）
  - `tests/openspec-kit.install.Tests.ps1`: **47 件 Pass**（`.claude/` 未存在時の初回 `-AgentTargets claude` 冪等性テストを含む）
  - `tests/openspec-kit.sh.Tests.ps1`: **40 件 Pass**（Git Bash 経由の `install.sh` 検証、`--overwrite-config` / 既存 `config.yaml` 保護 / `NONE` マーカー追記 / 警告テストを含む）
  - `tests/openspec-kit.verify-gate.Tests.ps1`: **13 件 Pass**
- **構文検査（PowerShell AST / Bash / Python `ast.parse`）**:
  - `Parser::ParseFile` による `openspec-kit/install.ps1`・`openspec-kit/scripts/verify-gate.ps1`・`openspec/scripts/verify-gate.ps1` の構文エラー: **0 件**
  - Git Bash `bash -n` による `openspec-kit/install.sh`・`openspec-kit/scripts/verify-gate.sh`・`openspec/scripts/verify-gate.sh` の構文エラー: **0 件**
  - **ツール制約と代替限界**: 本環境はオフラインかつ `PSScriptAnalyzer` 未導入のため、`npx prettier`（HTTP 403）および `Invoke-ScriptAnalyzer` は未実行。`Parser::ParseFile` と `bash -n` は構文エラー不在のみを確認するものであり、Prettier の改行・整形統一や `PSScriptAnalyzer` 固有ルールを代替するものではない（詳細は §3 技術的負債を参照）。
- **カバレッジ（JaCoCo XML / 実測）**:
  - `openspec-kit/install.ps1`: 命令（Instruction / C0 相当）**98.22%（387 / 394）**、行（Line）**98.25%（280 / 285）**
  - 補足: JaCoCo XML 出力仕様上 PowerShell の分岐カウンタ（`BRANCH`）は自動計測されないこと（全 0 表示）、`verify-gate.ps1` は別プロセス起動のため `0 / 172` 表示となること（`openspec-kit.verify-gate.Tests.ps1` 13 件および Gate 0〜3 実実行で確認済み）、および `install.ps1` の一部境界行（不在 `TargetPath`・一時ファイル失敗時削除・`AGENTS.md` インラインマーカー極端境界等）は 7 行未踏であることを記録する。
- **リポジトリ同期・ゲート検証**:
  - `install.ps1 -TargetPath . -BaseBranch main -EvidenceDir test-results/ -AgentTargets all -Force -SkipConfig` 実行後に 55 ファイル全同期、`AGENTS.md` 実測 **`15,680` バイト（BOM なし、24,000B 上限未満）**、`openspec-kit/AGENTS.openspec.md` **`11,502` バイト（BOM なし）**、旧 `.agents/workflows/sdd-*.md` 残存 0 件。
- **エビデンス出力先**: `test-results/pester-results.xml`, `test-results/coverage.xml`（Git 管理外）

---

## 3. 保留指摘・技術的負債

`reviews.md` の Propose〜Archive 全サイクルの保留指摘および本変更で認識した技術的負債・暗黙前提をすべて以下に記録する。

| 指摘元 / 種別                            | 内容                                                                                                                                                                                             | 保留理由・現状                                                                                                              | 推奨対応時期                          |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------- | ------------------------------------- |
| Propose Cycle 1 / SE 指摘6 [Minor]       | `.openspec.yaml` は `openspec` CLI 未知キー警告回避のため `x-level: L2` を使用しているが、`verify-gate` は `level:` を優先し、不在時に `proposal.md` 本文先頭の `\b(L[123])\b` へフォールバックする | 現在も `AGENTS.md` / `SKILL.md` は `level:` が正本表記。フォールバック先頭一致により `proposal.md` 前半の語句で規模誤判定し得る罠がある | 次期 `verify-gate` 改修時             |
| Propose Cycle 2 / SE 指摘2 [Minor]       | (1) `UT-12` / `UT-26` リポジトリ側検査と `E2E-01` の分離、(2) `AGENTS.md` 更新用一時ファイルをアトミック置換のため必ず `AGENTS.md` と同一ディレクトリに作成する設計制約                          | (1) は `E2E-01` として `tests/openspec-kit.agents-skills.Tests.ps1` に自動化済み。(2) はリファクタ時に `$env:TEMP`/`/tmp` へ移すとクロスデバイス置換で破損するため制約として継承 | 恒久設計制約（変更時厳守）            |
| Group 1 Cycle 2 / QA 指摘1 [Suggestion]  | `UT-19` の `3.8-flash` 非推奨検査における英語肯定文脈併用ケース（`C2-3`）の検出余地                                                                                                              | ドキュメント言語が日本語規約のため実害なし                                                                                  | 英語ドキュメント導入時                |
| Group 3 Cycle 2 / PG 指摘1 + Archive Cycle 1 PG 指摘3 [Suggestion] | `install.sh` 内 `awk` ブロック（`expand_line` / `read_file` 等約 170 行）の重複と置換キー長マジックナンバー（`plen = 15 / 16`）                                                                  | Pester Bash スイート 40 件および `IT-01` バイト完全一致を通過済みのため直前全面改修を回避                                   | `install.sh` 大幅改修時（`plen=length(...)` 統一） |
| DoD 環境制約負債（Archive SE/QA 指摘）   | オフライン・ツール未導入により `npx prettier`（HTTP 403）および `PSScriptAnalyzer`（`Invoke-ScriptAnalyzer`）が未実行                                                                           | AST・`bash -n`・Pester 155 件で代替検証したが、静的解析固有ルールや一部 CRLF 整形は未検査                                   | CI 環境またはオンライン整備後         |
| `run_*_review.py` 実機未検証・構造重複負債（Archive SE/PG 指摘） | (1) Antigravity CLI 実 `run_workflow` ランタイム上での実機起動は未検証（Python スタブ検証のみ）、(2) スクリプト内にタイムアウト・部分結果保持がなく親エージェントの目視復旧（`antigravity-orchestration.md` §6）依存、(3) `run_propose_review.py` と `run_archive_review.py` は自己完結のため約 80% 構造重複、(4) トップレベル `main()` 実行（`import` すると `exit 2`）とリポジトリルート CWD 前提 | `run_workflow` の単一ファイル実行互換を優先した設計上の妥協。権限分離（`write_tools: false`）はランタイム/事前 `define_subagent` 連携に依存する | `run_workflow` 仕様安定後・機能追加時 |
| インストーラ・`verify-gate.sh` 境界負債（Archive PG/SE 指摘） | (1) `Copy-KitDirectory` / `copy_kit_directory` は加算・上書きのみでファイル削除同期を行わない（スキル改名・廃止時に旧ファイルが残存する）、(2) `AGENTS.md` 24,000B 超過時は `[warn]` 出力のみで終了コード 0、`<!-- openspec-kit:begin` プレフィックスを独自本文に書くと `CORRUPT` 停止する、(3) `skills/` 配下は NUL なし UTF-8 テキスト前提（バイナリ/`__pycache__` 混入不可、`skills/` 内 `.ps1` に BOM 非付与）、(4) `install.sh` は既存 `AGENTS.md` の BOM を除去せず、`verify-gate.sh` の `BASE_BRANCH` は `"`/`$`/バッククォート非エスケープ、また既存 `verify-gate.sh` L161 に GNU `sed` 固有 `\L\1`（macOS BSD sed 非互換）が存在する、(5) `pwsh` 非 Windows 実行時に `*.sh` へ `+x` が付与されず、途中書き込み失敗時の前段コピーはロールバックされない | 影響が特定境界条件に限られること、既存設計のスコープ維持のため現状引き継ぎ                                                   | 次期インストーラ／クロスプラットフォーム改善時 |

---

## 4. 将来の改善・リファクタ候補

- **`.openspec.yaml` の `x-level:` 直接解釈対応**: `verify-gate.ps1` / `verify-gate.sh` が `level:` に加えて `x-level:` も直接読み取るようにし、`proposal.md` 本文先頭マッチへの依存（誤判定罠）を解消する。
- **`openspec-kit/install.sh` の `awk` 共通化**: PG Reviewer 提案の共通 AWK ライブラリ＋`plen = length(...)` 化により約 25〜30% 削減とプレースホルダ追加時の同期漏れ防止を図る。
- **スキル改名・削除時の旧ファイルクリーンアップ対応**: `-Force` 再同期時に管理対象スキル配下の孤立ファイル（廃止ファイル）を検知・警告または整理する仕組みの検討。
- **CI での `Prettier` / `PSScriptAnalyzer` / `Pester` / `verify-gate.sh` 自動化**: macOS/Linux/Windows の複数 OS 上で書式差分・静的解析・BSD `sed` 互換を継続検証する。

---

## 5. 運用・トラブルシューティング・ロールバック上の注意事項

- **本リポジトリへの再同期コマンド**: 今後 `openspec-kit/` を変更した場合は、必ず `-AgentTargets all` を付けて再同期し、`-SkipConfig` 使用時は `openspec-kit/config.yaml` と `openspec/config.yaml` の差分を手動反映する（`-AgentTargets` 省略時は既定 `auto` のため注意）。
  ```powershell
  pwsh ./openspec-kit/install.ps1 -TargetPath . -BaseBranch main -EvidenceDir test-results/ -AgentTargets all -Force -SkipConfig
  ```
- **管理対象ファイル（直接編集禁止）**: `.agents/skills/sdd-*`, `.claude/skills/sdd-*`, `.github/skills/sdd-*`, `.opencode/skills/sdd-*`, `.hermes/skills/sdd-*` および `AGENTS.md` の `<!-- openspec-kit:begin -->`〜`<!-- openspec-kit:end -->` 内側は再同期で上書きされる。24,000B 警告が出た場合は管理区間外を別ファイルへ分割し、独自本文へ `<!-- openspec-kit:begin` プレフィックス文字列を書かないこと。
- **`AGENTS.md` アトミック更新制約**: リファクタ時も一時ファイルは必ず `AGENTS.md` と同一ディレクトリに作成し、クロスデバイス移動を避けること。
- **`run_*_review.py` の運用と障害復旧**:
  - `.agents/skills/sdd-{propose,archive}/scripts/run_{propose,archive}_review.py` はリポジトリルート基準で Antigravity CLI `run_workflow` から `args={"change_name": "<name>"}` を渡して実行する（直接 `python` 実行は仕様どおり終了コード `2` で停止、他環境は `SKILL.md` フォールバック使用）。
  - `parallel` 実行が部分失敗・タイムアウトした場合は、`references/antigravity-orchestration.md` §6 に従い未完了ロールのみ `invoke_subagent(Model: "pro")` で個別再実行する。
- **導入途中失敗時と旧 `.bak` ファイル**: 導入途中でファイルロック等により停止した場合は原因解消後に `-Force`（`--force`）を付けて再実行できる。退避された旧ワークフロー `.bak*` は内容確認後に削除してよいが、`opsx-*.md` は削除しないこと。また他プロジェクトでは `.github/` ディレクトリ存在のみで `-AgentTargets auto` が Copilot ターゲットを有効化する点に留意する。
- **ロールバック手順**:
  - **本リポジトリ側**: DB 等への非可逆変更はないため、PR マージコミットの `git revert -m 1 <merge-commit>` で安全に原状復帰できる。
  - **外部導入済みプロジェクト側**: 旧版インストーラは新設された `skills/sdd-*` を自動削除しないため、旧版へ戻す際は各導入先（`.agents`, `.claude`, `.github`, `.opencode`, `.hermes` 配下の `skills/sdd-*`）を手動削除し、退避された `.agents/workflows/sdd-*.md.bak*` がある場合は元のファイル名へ手動リネーム復元すること。
