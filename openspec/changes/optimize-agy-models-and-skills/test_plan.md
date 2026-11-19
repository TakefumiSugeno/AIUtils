# テスト計画・テストケース定義書 (Test Plan): optimize-agy-models-and-skills

- **変更名**: `optimize-agy-models-and-skills`
- **適用規模レベル**: `L2`
- **変更種別**: `feat`（機能追加/変更）

---

## 1. カバレッジ目標と完了基準

| 指標                          | 定義                                                                      | 目標値（全体 / 新規・変更差分） | 適用対象・計測手段                                               |
| :---------------------------- | :------------------------------------------------------------------------ | :------------------------------ | :--------------------------------------------------------------- |
| **C0 (命令網羅 / Line)**      | 実行可能な全ステートメントの網羅率                                        | **80%以上** / **90%以上**       | `install.ps1`: Pester 5 `-CodeCoverage`（`test-results/` 出力）  |
| **C1 (分岐網羅 / Branch)**    | `if/else`, `switch`, ガード節, エラー経路の真偽両方の網羅率               | **80%以上** / **85%以上**       | 全分岐パスに対応するテスト通過＋Pester カバレッジで未踏行確認    |
| **C2 (条件網羅 / Condition)** | 複合条件式（ターゲット判定 × 既存Dir × 既存スキル × Force × WhatIf）網羅  | **100%**（対象ロジック）        | 下記「4. デシジョンテーブル」全行のテスト実行                    |
| **Scenario 網羅率**           | `specs/**/spec.md` の全 `#### Scenario:` に対する結合/E2Eテスト対応率     | **100%**                        | 下記「2. トレーサビリティマトリクス」で対応付け                  |

- **カバレッジ除外・代替計測方針**:
  - `openspec-kit/install.sh`: Bash 標準のカバレッジ計測器が環境に依存するため、PowerShell 版と同等の全ケース（`tests/openspec-kit.sh.Tests.ps1`）および出力パリティ検証（`IT-01`）により分岐網羅を保証する。
  - `openspec-kit/skills/*/scripts/*.py`: Antigravity `run_workflow` ランタイム専用ツールに依存するため、通常 CLI 実行時は安全終了ガード（終了コード 2）を実プロセスでテストし、ランタイムロジックはスタブプリミティブ（`agent`, `parallel`, `phase`, `log`, `args`）を注入した Python 実行テスト（`UT-17`, `IT-05`）で検証する。
- **モック境界方針**:
  - **モック化する外部境界**: テスト時は OS 一時ディレクトリ上の実ファイル・実 `bash`・実 `python` を使用し、`install.ps1` / `install.sh` 内部ロジックはモック化しない（`scripts/*.py` の単体検証時のみテストハーネス側で `run_workflow` 組み込み関数をスタブ注入）。

---

## 2. シナリオ・トレーサビリティマトリクス

| Spec Capability / Requirement | Scenario 名 | Unit | Integration | E2E | 対応テストケースID |
| :--- | :--- | :--: | :---------: | :-: | :--- |
| `multi-agent-skills-distribution` / パッケージ構造 | スキル定義の必須構造と自己完結性 | ✅ | ✅ | ✅ | `UT-01`, `IT-05`, `E2E-01` |
| `multi-agent-skills-distribution` / パッケージ構造 | openspec 生成スキルとの非衝突 | ✅ | - | ✅ | `UT-02`, `E2E-01` |
| `multi-agent-skills-distribution` / 多面展開 | 自動検出による多面展開（Happy Path） | ✅ | ✅ | ✅ | `UT-03`, `DT-01`, `IT-01`, `E2E-01` |
| `multi-agent-skills-distribution` / 多面展開 | 他エージェント未検出時の Zero-State 案内 | ✅ | - | ✅ | `DT-02`, `E2E-02` |
| `multi-agent-skills-distribution` / 多面展開 | 明示指定（all / カンマ区切り）と異常入力の拒否 | ✅ | ✅ | ✅ | `UT-04`〜`UT-07`, `DT-03`〜`DT-06`, `IT-06`, `E2E-03` |
| `multi-agent-skills-distribution` / 多面展開 | 既存スキルの保護・半端更新警告・-WhatIf 抑止 | ✅ | ✅ | - | `UT-08`, `UT-22`, `DT-07`〜`DT-10`, `IT-02`, `IT-07` |
| `multi-agent-skills-distribution` / レガシー移行 | 旧 SDD ワークフロー残存時の安全な後段退避 | ✅ | ✅ | ✅ | `UT-09`, `UT-10`, `DT-09`, `IT-03`, `E2E-01` |
| `multi-agent-skills-distribution` / レガシー移行 | リネーム失敗時のエラー案内および非対象時の非実行 | ✅ | ✅ | ✅ | `UT-11`, `DT-10`, `IT-08`, `E2E-02` |
| `multi-agent-skills-distribution` / ルール安全更新 | 生成後 AGENTS.md のサイズ上限検証と超過警告 | ✅ | ✅ | ✅ | `UT-12`, `UT-23`, `IT-04`, `E2E-01` |
| `multi-agent-skills-distribution` / ルール安全更新 | マーカー破損防止・特殊文字置換安全性・アトミック書き換え | ✅ | ✅ | - | `UT-24`, `UT-25`, `IT-06` |
| `antigravity-model-orchestration` / ロール定義 | 高推論・設計レビュー系ロールの Neon 級割り当てと権限分離 | ✅ | - | - | `UT-13` |
| `antigravity-model-orchestration` / ロール定義 | 破壊テスト実行権を持つ QA レビュアーの定義 | ✅ | - | - | `UT-14` |
| `antigravity-model-orchestration` / ロール定義 | 高速実装・テスト生成ロールの Hydrogen 級割り当て | ✅ | - | - | `UT-15` |
| `antigravity-model-orchestration` / オーケストレーション | define_subagent による物理的書き込み分離と単一ライター転記 | ✅ | ✅ | - | `UT-16`, `IT-05` |
| `antigravity-model-orchestration` / オーケストレーション | Propose・Archive 並列実行スクリプトと誤実行ガード | ✅ | ✅ | - | `UT-17`, `UT-21`, `IT-05` |
| `antigravity-model-orchestration` / オーケストレーション | 並列失敗時のフォールバックおよび L3 swarm 連携 | ✅ | - | - | `UT-18` |
| `antigravity-model-orchestration` / 非推奨排除 | Gemini 3.8 Flash の非採用確認 | ✅ | - | - | `UT-19` |
| `antigravity-model-orchestration` / 非推奨排除 | Antigravity CLI 以外のエージェントでの実行 | ✅ | ✅ | ✅ | `UT-20`, `UT-26`, `E2E-01` |

---

## 3. 単体テスト：同値分割・境界値テストケース定義

### 3.1 同値クラス・境界値一覧

| ケースID | 対象関数 / 成果物 | 検証観点（区分） | 入力値・前提状態 | 期待される出力・状態変化 |
| :--- | :--- | :--- | :--- | :--- |
| `UT-01` | `openspec-kit/skills/*/SKILL.md` | スキル定義構造・自己完結性 | `sdd-propose`, `sdd-apply`, `sdd-archive` | `name` がディレクトリ名と一致し、`description` 非空、`references/sdd-reference.md` と `antigravity-orchestration.md` が各スキル内に自己完結で存在 |
| `UT-02` | `openspec-kit/skills/*` | 名前空間非衝突 | スキル名一覧 | `openspec-*` や `opsx-*` を一切含まない（`sdd-*` のみ） |
| `UT-03` | `install.ps1` / `install.sh` | 自動検出（複数存在） | `.claude/` と `.github/` のみ存在、`-AgentTargets auto` | `.agents/skills`, `.claude/skills`, `.github/skills`, `.claude/agents` に展開し、`.opencode/skills`, `.hermes/skills` は未作成 |
| `UT-04` | `install.ps1` / `install.sh` | 明示指定（`all`） | 空プロジェクト（`openspec/` のみ）、`-AgentTargets all` | 5 エージェントすべての `skills/sdd-*`（`references/`, `scripts/` 含む）が展開される |
| `UT-05` | `install.ps1` / `install.sh` | 明示指定（CSV・空白・大小・非antigravity） | `-AgentTargets " Claude , copilot "` | `.claude/skills` と `.github/skills` のみへ展開し、`.agents/skills` は作成しない |
| `UT-06` | `install.ps1` / `install.sh` | 境界値（空文字 / 空白のみ / 空トークン） | `""`, `"   "`, `"claude,"` | バリデーションエラーで即時停止（終了コード非ゼロ）、ファイル変更ゼロ |
| `UT-07` | `install.ps1` / `install.sh` | 異常系（未知・重複混在ターゲット） | `"claude,unknown_cli"`, `"auto,claude"`, `"claude,claude"` | `"unknown_cli"`・`"auto,claude"` はエラー停止、`"claude,claude"` は重複排除して正常実行 |
| `UT-08` | `install.ps1` / `install.sh` | 境界値（既存保護 / `-Force` / `-WhatIf`） | 既存 `SKILL.md` に対し `-Force` なし・あり・`-WhatIf` | `-Force` なしは維持、`-Force` ありは上書き、`-WhatIf` はファイル作成・退避ゼロ |
| `UT-09` | `install.ps1` / `install.sh` | レガシー退避（後段実行・`opsx`保護） | `.agents/workflows/sdd-propose.md` と `opsx-propose.md` 存在 | スキル展開成功後に `sdd-propose.md.bak` へリネーム、`opsx-propose.md` 無傷 |
| `UT-10` | `install.ps1` / `install.sh` | レガシー退避（`.bak` 衝突・連続実行） | `sdd-propose.md` と `sdd-propose.md.bak` が両方存在（同秒連続含む） | 既存 `.bak` を上書きせず `sdd-propose.md.bak-<timestamp>-<n>` へ退避 |
| `UT-11` | `install.ps1` / `install.sh` | 境界値（0件不在・非antigravity時非実行） | `.agents/workflows/` 不在、または `-AgentTargets claude` | 空 `.agents/workflows/` を作らず、`-AgentTargets claude` 時は既存 `sdd-*.md` に触れない |
| `UT-12` | `AGENTS.openspec.md` / `AGENTS.md` | 境界値（24,000 バイト上限） | `AGENTS.openspec.md` 単体、新規生成 `AGENTS.md`、本リポジトリ `AGENTS.md` | 単体 `< 12,000B`、新規生成 `<= 16,000B`、本リポジトリ実ファイル `< 24,000B`（UTF-8 BOM なし） |
| `UT-13` | `openspec-kit/agents/{user,se,pg}-reviewer.md` | メタデータ・契約検証（Neon + Read-only） | 各ロール定義ファイル | `model_tier: pro`, `thinking: high`, `write_tools: false` と親への結果返却契約を明記 |
| `UT-14` | `openspec-kit/agents/qa-reviewer.md` | メタデータ検証（Neon + 破壊テスト可） | `qa-reviewer.md` | `model_tier: pro`, `thinking: high`, `write_tools: true` を含む |
| `UT-15` | `openspec-kit/agents/{qa-tester,pg-implementer}.md` | メタデータ検証（Hydrogen + 編集可） | `qa-tester.md`, `pg-implementer.md` | `model_tier: flash`, `write_tools: true` を含む |
| `UT-16` | `skills/*/references/antigravity-orchestration.md` | オーケストレーション仕様記述 | 3 スキルの参照ガイド | `define_subagent`（`EnableWriteTools` 制御）・`invoke_subagent`（`Model` 明示）・単一ライター原則を含む |
| `UT-17` | `skills/sdd-{propose,archive}/scripts/*.py` | `run_workflow` スクリプト AST & スタブ実行 | `run_propose_review.py`, `run_archive_review.py` | `ast.parse` 通過＋スタブ `agent`/`parallel`/`phase`/`log`/`args` 注入実行で Propose 2ロール・Archive 4ロールを `model="pro"` で呼ぶ |
| `UT-18` | `skills/*/references/antigravity-orchestration.md` | 部分失敗回復・L3 swarm 連携 | 参照ガイド | `parallel` 部分失敗時の `invoke_subagent` 単体再実行手順と L3 `swarm`（`workspace="share"`・1ワーカー1ファイル群）を含む |
| `UT-19` | `openspec-kit/` 全体 | 非推奨モデル除外 | `agents/`, `skills/`, `config.yaml`, `AGENTS.openspec.md` | アクティブな推奨・指定値として `gemini-3.8-flash` を含まない |
| `UT-20` | `openspec-kit/skills/*/SKILL.md` | 他エージェント互換フォールバック | 3 スキルの `SKILL.md` | 非 Antigravity 環境での標準サブエージェント/直列フォールバック手順を含み、相対リンク先が存在 |
| `UT-21` | `skills/sdd-{propose,archive}/scripts/*.py` | 異常系（通常 `python3` CLI 直叩きガード） | スタブなし環境で `python3 <script>` 実行 | `NameError` にならず終了コード `2` で終了し、stderr に `run_workflow` 専用メッセージを出す |
| `UT-22` | `install.ps1` / `install.sh` | 警告出力（`-Force` 未指定スキルスキップ） | 既存スキルあり＋`-Force` なしで再実行 | 標準出力/警告に `-Force`（`--force`）再実行推奨メッセージが出力される |
| `UT-23` | `install.ps1` / `install.sh` | 境界値超過（既存 `AGENTS.md` >= 24,000B） | 管理区間外に 20,000B のテキストがある既存 `AGENTS.md` を再同期 | 処理完了しつつ実バイト数・超過バイト数・分割案内を警告出力する |
| `UT-24` | `install.ps1` / `install.sh` | 異常系（片側マーカー破損 `AGENTS.md`） | `<!-- openspec-kit:begin` のみ存在（`end` 欠損） | 二重追記せずエラー終了（非ゼロ）し、復旧案内を出力する |
| `UT-25` | `install.sh` / `install.ps1` | 境界値（置換文字列への `& \ |` 混入） | `BaseBranch = 'feat/a&b|c\d'`, `EvidenceDir = 'out&1/ev/'` | 置換結果が壊れずそのままのリテラル文字列として展開される |
| `UT-26` | `openspec-kit/config.yaml`, `openspec/config.yaml`, `README.md` | 設定・ドキュメント旧参照除去 | 対象ファイル群 | 旧パス `.agents/workflows/sdd-` へのアクティブ参照が 0 件であること |

---

## 4. 単体テスト：複合条件デシジョンテーブル（C2 / MC/DC 網羅）

対象ロジック: `install.ps1` / `install.sh` におけるスキル展開・レガシー退避判定

| ケースID | `AgentTargets` | 対象Dir存在 (`.claude`等) | 既存スキル | `-Force` | `-WhatIf` | 旧 `sdd-*.md` | 期待される判定結果・アクション |
| :------- | :------------: | :-----------------------: | :--------: | :------: | :-------: | :-----------: | :----------------------------- |
| `DT-01`  | `auto`         | Yes                       | No         | No       | No        | No            | `.agents`＋検出Dirへ展開（他不在なら案内なし） |
| `DT-02`  | `auto`         | No（全不在）              | No         | No       | No        | No            | `.agents/skills` のみ展開＋Zero-State 案内出力 |
| `DT-03`  | `all`          | No                        | No         | No       | No        | Yes           | 全5ターゲット作成・展開後、旧 `sdd-*.md` 退避 |
| `DT-04`  | `claude,hermes`| No                        | No         | No       | No        | Yes           | `.claude/skills`, `.hermes/skills` のみ作成（`.agents` 非作成・退避非実行） |
| `DT-05`  | `antigravity,claude` | No                  | No         | No       | No        | Yes           | `.agents/skills`, `.claude/skills` 作成＋旧 `sdd-*.md` 退避 |
| `DT-06`  | 不正 (`""`/`foo`/`auto,claude`) | -        | -          | -        | -         | -             | バリデーションエラーで即時停止（ファイル変更なし） |
| `DT-07`  | `claude` (CSV) | Yes                       | Yes        | No       | No        | -             | 既存スキルをスキップし `-Force` 推奨警告を出力 |
| `DT-08`  | `claude` (CSV) | Yes                       | Yes        | Yes      | No        | -             | 既存スキルを上書き更新 |
| `DT-09`  | `auto`         | Yes                       | Yes        | Yes      | No        | Yes           | 上書き展開完了後にのみ旧 `sdd-*.md` を `.bak` 退避 |
| `DT-10`  | `all`          | Yes                       | Yes        | Yes      | Yes       | Yes           | ドライラン出力のみ（ファイル作成・上書き・`.bak` 退避すべてなし） |

---

## 5. 結合テスト（Integration Test）ケース定義

### 5.1 インターフェース契約・異常系注入（Fault Injection）

| ケースID | 連携対象（CLI / Script / File） | シナリオ・注入する異常 | 期待される振る舞い |
| :--- | :--- | :--- | :--- |
| `IT-01` | `install.ps1` ↔ `install.sh` | 同一ダミープロジェクト・同一パラメータ（`auto` / `all` / `claude,copilot`）での実行比較 | 配置ファイル一覧・内容・LF/BOM規約が PowerShell 版と Bash 版で一致すること |
| `IT-02` | `install.ps1` / `install.sh` | `--skip-config --force` の 2 回連続冪等実行（カスタム追記維持） | `AGENTS.md` 管理区間 1 つのみ、区間外カスタム追記および既存非対象ファイル維持 |
| `IT-03` | `install.ps1` / `install.sh` | `.agents/workflows/sdd-*.md` + `.bak` + `opsx-propose.md` 混在環境での再同期 | `sdd-*.md` のみ連番タイムスタンプ退避、`opsx-propose.md` 無傷 |
| `IT-04` | `install.ps1` ↔ `verify-gate.ps1` | 生成済みプロジェクトで `AGENTS.md` サイズ検証＋`verify-gate.ps1 -Gate pre-propose` | `AGENTS.md` < 24,000B かつ `verify-gate.ps1` 正常終了 |
| `IT-05` | `SKILL.md` ↔ `agents/*.md` ↔ `scripts/*.py` | スタブ注入実行およびファイル参照実在検査 | スキル内の相対パスリンク・`scripts/*.py` が参照する `openspec/agents/*.md` / `openspec/templates/checklist_*.md` がすべて実在すること |
| `IT-06` | `install.ps1` / `install.sh` | **異常注入**: `.claude` が通常ファイルとして存在 / 破損片側マーカー `AGENTS.md` / 特殊文字 `&\|` | 書き込み前に明確なエラーメッセージで非ゼロ終了し、既存ユーザーデータを破損させないこと（特殊文字時は正常置換） |
| `IT-07` | `install.ps1` / `install.sh` | **異常注入（途中失敗耐性）**: スキル展開先が読み取り専用または不正状態で失敗した場合 | スキル展開が失敗した時点で停止し、`.agents/workflows/sdd-*.md` が先に退避されて消滅しないこと |
| `IT-08` | `install.ps1` / `install.sh` | **異常注入（退避失敗）**: 退避対象ファイルや `.agents/workflows/` へのロック／権限エラー模擬 | 対象パスと復旧案内を出力して非ゼロ終了すること |

### 5.2 状態遷移網羅（0-switch / 1-switch）

| ケースID | 現在の状態 | イベント / 操作 | 遷移後の状態（または拒否エラー） | 区分 |
| :--- | :--- | :--- | :--- | :--- |
| `ST-01` | `openspec/` のみ（未導入） | `install.ps1 -AgentTargets auto` | `.agents/skills` + `AGENTS.md` + `openspec/` 構成＋Zero-State案内 | 正常遷移（0-switch） |
| `ST-02` | 旧ワークフロー導入済み（`sdd-*.md`） | `install.ps1 -Force -SkipConfig` | 新スキル展開完了後に旧 `sdd-*.md` が `.bak` 退避 | 正常遷移（0-switch） |
| `ST-03` | 移行完了済み | `install.ps1 -Force -SkipConfig` 再実行 | 同一結果（追加 `.bak` 増殖なし・冪等） | 冪等性確認 |
| `ST-04` | `openspec/` 未存在（`openspec init` 未実行） | `install.ps1` / `install.sh` 実行 | 非ゼロ終了コードで拒否（`'openspec init'` 案内）、ファイル未作成 | 異常遷移拒否（1-switch） |

---

## 6. E2Eテスト・シナリオ検証ケース定義

| ケースID | ジャーニー種別 | 操作手順（Given → When） | 期待される結果・出力エビデンス（Then） |
| :--- | :--- | :--- | :--- |
| `E2E-01` | **Happy Path**（本リポジトリ再同期 & 全テスト） | `install.ps1 -TargetPath . -BaseBranch main -EvidenceDir test-results/ -AgentTargets all -Force -SkipConfig` 実行、`.bak` 整理後、`Invoke-Pester` と `verify-gate` 実行 | 5 エージェントすべてのスキル・6ロール定義・スリム化された `AGENTS.md`（<24KB）が配置され、Pester 全件 Pass・skip 0 件・カバレッジ基準達成 |
| `E2E-02` | **Zero-State / 初回起動** | `.claude/` 等が一切ない新規 `openspec init` 直後の空プロジェクトに `-AgentTargets auto` で導入 | `.agents/skills/sdd-*` と `AGENTS.md`（<24KB）が生成され、不要ディレクトリ未作成＋後から他ターゲットへ展開する案内が出力されること |
| `E2E-03` | **Negative / Recovery Path** | 1. 不正 `-AgentTargets invalid` で失敗確認 → 2. 正しい `-AgentTargets claude` で再実行 | 1 で明快なエラーで停止（無変更）、2 の再実行で正常に導入完了できること |
| `E2E-04` | **UIモック検証** | 該当なし（CLI / マークダウン配布キットであり UI 変更なし） | 対象外 |
