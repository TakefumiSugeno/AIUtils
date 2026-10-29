## OpenSpec 運用ルール（openspec-kit）

本プロジェクトは **OpenSpec** による仕様駆動開発 (Spec-Driven Development) を採用しています。

- **Single Source of Truth**: システム仕様の正本は `openspec/specs/`。OpenSpec 管理外に仕様書・タスクを新規作成・二重管理しない。
- **仕様駆動ワークフロー**: 機能追加・仕様変更・不具合修正・大規模リファクタリングは、Explore → Propose → Apply → Archive に則って進める。
- **サブエージェントレビュー必須**: 各フェーズで専門の役割（User / SE / PG / QA Agent）によるレビューを実施し、品質と整合性を担保する。
- 設定: `openspec/config.yaml`（context / rules / operations）、テンプレート: `openspec/templates/`

### ディレクトリ構成

| パス                        | 内容                                                                                |
| --------------------------- | ----------------------------------------------------------------------------------- |
| `openspec/config.yaml`      | OpenSpec 設定（スキーマ・運用ルール・レビュー定義）                                 |
| `openspec/specs/`           | メイン仕様（システムの恒久的な仕様）                                                |
| `openspec/changes/<name>/`  | 変更単位の成果物（proposal / specs / design / tasks / mockup / reviews / handover） |
| `openspec/changes/archive/` | 完了した変更のアーカイブ                                                            |
| `openspec/templates/`       | レビュー記録・チェックリスト・handover・PR 本文テンプレート                         |
| `{{EVIDENCE_DIR}}`          | テストエビデンス・カバレッジレポート出力先（Git 管理外）                            |

### 変更ディレクトリの成果物

| ファイル           | 作成フェーズ | 内容                                                                  |
| ------------------ | ------------ | --------------------------------------------------------------------- |
| `proposal.md`      | Propose      | What & Why、Non-goals、受け入れ基準                                   |
| `specs/**/spec.md` | Propose      | デルタ仕様（外部観測可能な振る舞い・シナリオ）                        |
| `design.md`        | Propose      | 実現方法（アーキテクチャ・データフロー・IF）                          |
| `tasks.md`         | Propose      | テストファーストのタスクリスト（2時間以内/タスク）                    |
| `mockup.html`      | Propose      | UI/UX 変更時のみ。単一ファイル HTML モック（Single Source of Design） |
| `reviews.md`       | 全フェーズ   | レビュー記録（`review_record.md` 準拠で追記）                         |
| `handover.md`      | Archive      | 変更サマリ・テスト結果・保留指摘・改善候補（`handover.md` 準拠）      |

---

### サブエージェントレビュープロセス

レビュー記録は `openspec/changes/<name>/reviews.md` に `openspec/templates/review_record.md` 準拠で追記する。

| フェーズ | トリガー                                    | レビュアー                        | チェックリスト                                        | 合否                                     |
| -------- | ------------------------------------------- | --------------------------------- | ----------------------------------------------------- | ---------------------------------------- |
| Propose  | 全計画アーティファクト作成後、Propose合意前 | User Agent, SE Agent              | `checklist_propose.md`                                | 全役割 LGTM → ユーザー合意 → commit      |
| Apply    | 各タスクの `[x]` 更新前                     | 実装: PG Agent / テスト: QA Agent | `checklist_apply_impl.md` / `checklist_apply_test.md` | 全指摘クローズで `[x]` → commit          |
| Archive  | `openspec archive` 実行前                   | User / SE / PG / QA Agent 全役割  | `checklist_archive.md`                                | 全役割 LGTM → ユーザー最終合意 → archive |

#### レビューの実施方法

1. **独立したコンテキストで実施する**: 可能な限りサブエージェント（別会話コンテキスト）を起動し、役割・観点・チェックリストのパス・対象成果物のパスを渡してレビューさせる。実装者自身の思い込みを持ち込まないため。サブエージェント機能がない環境では、役割を明示して観点別にセルフレビューし、その旨を記録に残す。
2. **批判的に行う**: 追認ではなく、UX不備・エッジケース・設計漏れ・仕様との乖離・テストの抜けを積極的に指摘する。指摘なしの場合も「何を確認したか」の根拠を残す。
3. **全項目を判定する**: チェックリストの全項目に ✅/❌/⚠️ とコメント（根拠）を記入する。
4. **対応方針を明記する**: 各指摘に重要度（Critical / Major / Minor / Suggestion）と対応方針（採用 / 保留 / 却下＋理由）、対応コミットを記録する。
5. **再レビュー**: 採用指摘の修正後に再レビューし、全指摘クローズ（LGTM）で次へ進む。
6. **保留指摘の扱い**: 当該タスクは完了扱いとし、「申し送り事項」として `reviews.md` に記録、Archive 時に `handover.md` へ転記する。

---

### テストエビデンス・カバレッジ

- TDD（Red → Green → Refactor）を前提とし、Red（実装前に失敗すること）を実際に確認してから実装する。
- テストレポート・カバレッジレポート・E2E 失敗時キャプチャは `{{EVIDENCE_DIR}}` に出力する（実行ごとにタイムスタンプ付きフォルダ推奨）。
- **Git 管理不要**: エビデンスやカバレッジレポートは `.gitignore` 対象とし commit しない。
- **レビューでの確認**: QA Agent / Archive 総括レビューではローカルのレポートを参照して合否判定し、`reviews.md` には本文ではなく「件数・Pass/Fail・カバレッジ率」のサマリをテキストで記録する。

#### E2E テストおよび画面検証の厳格運用（GUI / Web アプリの場合）

- **名ばかり E2E の禁止**: バックエンドの関数結合テストを「E2E テスト」と称して UI・プレゼンテーション層の検証を省略しない。
- **実画面レンダリング検証義務**: 実ブラウザ / 実ウィンドウで描画し、主要な画面状態（初期表示・結果一覧・詳細・エラー表示等）のスクリーンショット（PNG）を出力して、視認性・レイアウト崩れ・コントラストを検証する。
- **「ゼロ設定・初回起動」ユーザージャーニーのテスト義務**: モックデータの正常系だけでなく、「APIキー未設定」「未ログイン」「初回起動（対象0件）」などの初期状態から、ユーザーが主要操作を行えるまでの現実的なジャーニーをテストシナリオに含める。

#### UI モックアップ

- **作成義務**: 画面レイアウト・インタラクション・配色・コンポーネント構成に変更が入る場合、Propose フェーズで `openspec/changes/<name>/mockup.html` を作成・更新する。CDN（例: Tailwind CSS + Alpine.js）を用いた単一ファイルとし、ブラウザで状態変化・アニメーションまで確認できるようにする。ユーザーとの合意形成および実装の Single Source of Design とする。
- **忠実再現の原則**: モックやデザイン詳細が定義されている場合、実装者はテーマ・配色・レイアウト・フォント・各要素のスタイル・情報階層を勝手に簡略化・改変しない。

---

### 自動フォーマット

ファイル更新時・コミット前・テスト実行前に、ファイル種別に応じたフォーマッタを実行する。
ファイル種別ごとのコマンドは、本ファイルの **openspec-kit 管理区間外**（「プロジェクト固有ルール」の「自動フォーマット」表）に記載する。

---

### Git 操作ルール

OpenSpec の成果物（`openspec/` 配下）も Git 管理対象とする。

#### 1. ブランチ作成（Explore → Propose 移行時の安全シーケンス）

`openspec new change "<change-name>"` 実行直前に、**必ず以下を順に実行**する:

1. **作業ツリー確認と退避**: `git status --porcelain` で未コミット変更を確認し、存在する場合は破棄・上書きせず退避する。
   ```bash
   git stash push -u -m "wip: backup before switch to <change-name>"
   ```
2. **ベースブランチの最新化**:
   ```bash
   git checkout {{BASE_BRANCH}}
   git pull origin {{BASE_BRANCH}}
   ```
3. **トピックブランチの作成**:
   ```bash
   git checkout -b feature/<change-name>
   ```
4. **確認**: `git branch --show-current` で対象ブランチにいることを確認してから成果物作成に着手する。

**ブランチ命名規約**: 新機能・通常変更 `feature/<change-name>` / 不具合修正 `fix/<change-name>` / リファクタ・運用改善 `refactor/<change-name>` または `chore/<change-name>`

#### 2. Commit タイミング

1. **Propose 合意後**: `openspec/changes/<name>/` 配下の全成果物（proposal / specs / design / tasks / mockup / reviews）
2. **Apply 中の各タスク完了時**: 実装・テストコード、`tasks.md` の進捗、`reviews.md` のレビュー記録
3. **Archive 完了後**: 更新されたメイン仕様（`openspec/specs/`）、アーカイブされた変更、README 等の関連ドキュメント

**Commit メッセージ規約**（Conventional Commits）:

```
<type>(<scope>): <subject>

<body>
```

- type: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `review`, `spec`
- scope: change 名（例: `add-user-auth`）
- subject: 50 文字以内（日本語可）

#### 3. Push / Pull Request

- **Push**: 作業区切り（1 日 1 回以上推奨）および Archive 完了・ユーザー最終合意後に `git push -u origin feature/<change-name>`
- **PR 作成**: Archive 完了コミットの push 後、AI が GitHub CLI で PR を作成する。本文は `openspec/templates/pr_body.md` に従い OpenSpec 成果物を正本として構成する。
  ```bash
  gh pr create --base {{BASE_BRANCH}} --head feature/<change-name> --title "<type>(<scope>): <subject>" --body-file <PR本文ファイル>
  ```
- **マージ**: **Merge commit** を採用する（Squash / Rebase merge は禁止）。タスク単位のコミット、TDD の Red-Green-Refactor、レビュー履歴をベースブランチに保持するため。ユーザー合意後に実行する。
  ```bash
  gh pr merge <PR番号> --merge --delete-branch
  git checkout {{BASE_BRANCH}}
  git pull origin {{BASE_BRANCH}}
  git branch -d feature/<change-name>
  ```

#### 4. 禁止事項

- `{{BASE_BRANCH}}` および `main` への直接コミット・直接 push
- ユーザー合意なしでの push および PR マージ
- 未フォーマット・未テスト状態での commit
- テストエビデンス・カバレッジレポート・秘密情報（`.env` 等）の commit
- WIP の commit はメッセージに `wip:` を付与し、後で整理する

---

### OpenSpec CLI リファレンス

```bash
# 変更の作成・一覧・進捗
openspec new change "<name>"                              # 新規変更作成
openspec list --json                                      # 進行中の変更一覧
openspec list --specs                                     # メイン仕様（capability）一覧
openspec status --change "<name>" --json                  # 成果物の進捗確認

# 成果物の作成指示・検証
openspec instructions <artifact> --change "<name>" --json # 作成指示（context / rules / template）
openspec instructions apply --change "<name>" --json      # 実装指示（operations.apply.guidance を含む）
openspec validate "<name>"                                # 変更の検証

# 完了
openspec archive "<name>"                                 # アーカイブ（メイン仕様へ反映）

# コンテキスト・設定
openspec context --json                                   # OpenSpec ルート確認
openspec schemas --json                                   # 利用可能スキーマ一覧
```

> [!NOTE]
> 振る舞いが変わらない変更（純粋なリファクタ・ツール・ドキュメント）は、`.openspec.yaml` に `skip_specs: true` を設定してデルタ仕様を省略できる。要件をでっち上げて validate を通すことはしない。
