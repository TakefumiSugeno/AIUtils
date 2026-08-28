---
name: rfp-init
description: >-
  ユーザが新しいアプリのアイデアを伝えてプロジェクトを開始したいとき、
  または「要件定義」「プロジェクト初期化」「リポジトリ作成」を依頼したときに使用する。
  ユーザの入力を構造化して request.md（要件定義書）を作成し、
  仕様書駆動開発（SDD）に準拠したディレクトリ構成・AGENTS.md・Git リポジトリを一括構築する。
---

# /rfp-init: 要求・要件定義およびプロジェクト初期化スキル

## 1. 目的と役割

ユーザから提示された「アプリのアイデア」や「質疑応答の回答」を構造化して `request.md`（要件定義書）を作成し、仕様書駆動開発（SDD）に準拠した初期リポジトリ環境および `AGENTS.md` を一括構築する。

---

## 2. 実行手順・ワークフロー

### Step 1: 要求ヒアリングとプロジェクト名の特定

1. ユーザから提供されたインプット（アイデア、背景、Q&A等）を解析する。
2. アプリケーション名（英数字・PascalCaseまたはkebab-case）を決定またはユーザに確認する。
3. プロジェクトの作成先ディレクトリをユーザに確認する（デフォルト: カレントワークスペースの親ディレクトリ）。
   - ルートパス: `[WORKSPACE_ROOT]/[AppName]`

**✅ 検証**: アプリ名と作成先パスがユーザに承認されたことを確認する。

### Step 2: ワークスペースおよびディレクトリ構造の作成

[init_project.ps1](./scripts/init_project.ps1) を実行して以下の構造を作成する。

```text
[WORKSPACE_ROOT]/[AppName]/
├── .git/
├── AGENTS.md                 # 開発工程・運用ルール
├── request.md                # 要件定義ドキュメント（AIへの入力原典）
├── doc/
│   ├── spec.md               # システム仕様書（初期空ファイルまたは骨子）
│   ├── design_detail.md      # 詳細設計書（初期空ファイルまたは骨子）
│   ├── mock/                 # UIモック・ワイヤーフレーム配置用
│   ├── tasks/
│   └── work/                 # 一時作業・バグ管理用
├── src/                      # ソースコード
└── test/                     # テストコード
```

**✅ 検証**: スクリプト出力のディレクトリ構造表示で、全ディレクトリ・ファイルの存在を確認する。

### Step 3: `request.md` の生成

[request_template.md](./resources/request_template.md) テンプレートに基づき、ユーザの入力内容を漏れなく構造化して配置する。

**✅ 検証**: テンプレートの全セクションが埋められているか確認する。空セクションがあればユーザに追加ヒアリングを行う。

### Step 4: `AGENTS.md` の生成

[agents_template.md](./resources/agents_template.md) に基づき、プロジェクトルートに `AGENTS.md` を作成する。

- SDD ワークフローの詳細手順は [sdd_workflow.md](./references/sdd_workflow.md) を参照。
- 自動フォーマット定義は [auto_format_policy.md](./references/auto_format_policy.md) を参照。

**✅ 検証**: 生成された `AGENTS.md` のプレビューをユーザに提示して確認を得る。

### Step 5: Git初期化および初期コミット

1. Step 2 で `init_project.ps1` 実行時に `git init` とブランチ `alpha` の作成は完了している。
2. 生成したファイル一式をフォーマットし、初期コミットを行う。
   - コミットメッセージ: `docs: initialize project with request.md and AGENTS.md`

**✅ 検証**: `git status` で追跡対象外のファイルがないこと、`git log --oneline -1` で初期コミットの存在を確認する。

### Step 6: 完了報告

生成された `request.md` の概要とリポジトリ構成をユーザに提示し、SDD ワークフローの `Step 1`（タスク計画作成）の着手合意を求める。
