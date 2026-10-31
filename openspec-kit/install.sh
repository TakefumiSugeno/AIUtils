#!/usr/bin/env bash
# =============================================================================
# openspec-kit/install.sh
#   openspec-kit（サブエージェント6ロール・TDD/C0-C2基準・フェーズゲート・テンプレート）を
#   対象プロジェクトへ導入／再同期する（Bash 版: Linux / macOS / Git Bash / WSL 対応）。
#
# 使い方:
#   ./openspec-kit/install.sh --target-path <dir> [--base-branch develop] [--evidence-dir test/TestResults/] [--force] [--overwrite-config] [--skip-config] [--dry-run]
#   ※ PowerShell 版と同じ引数名（-TargetPath, -BaseBranch, -EvidenceDir, -Force, -OverwriteConfig, -SkipConfig, -WhatIf）も指定可能
# =============================================================================
set -euo pipefail

TARGET_PATH=""
BASE_BRANCH="develop"
EVIDENCE_DIR="test/TestResults/"
FORCE=0
OVERWRITE_CONFIG=0
SKIP_CONFIG=0
DRY_RUN=0

usage() {
    cat <<'EOF'
Usage:
  install.sh --target-path <path> [options]

Options:
  -t, --target-path, -TargetPath <path>       導入先プロジェクトのルートディレクトリ（必須）
  -b, --base-branch, -BaseBranch <branch>     ベースブランチ名（既定: develop）
  -e, --evidence-dir, -EvidenceDir <dir>      テストエビデンス出力先（既定: test/TestResults/）
  -f, --force, -Force                         既存テンプレート・エージェント・スクリプト・ワークフローを上書き
      --overwrite-config, -OverwriteConfig    既存 openspec/config.yaml をバックアップして上書き
      --skip-config, -SkipConfig              openspec/config.yaml の処理をスキップ
  -n, --dry-run, --what-if, -WhatIf           ファイルを書き込まず実行予定のみ表示
  -h, --help                                  このヘルプを表示
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--target-path|-TargetPath)
            TARGET_PATH="${2:-}"; shift 2 ;;
        -b|--base-branch|-BaseBranch)
            BASE_BRANCH="${2:-}"; shift 2 ;;
        -e|--evidence-dir|-EvidenceDir)
            EVIDENCE_DIR="${2:-}"; shift 2 ;;
        -f|--force|-Force)
            FORCE=1; shift ;;
        --overwrite-config|-OverwriteConfig)
            OVERWRITE_CONFIG=1; shift ;;
        --skip-config|-SkipConfig)
            SKIP_CONFIG=1; shift ;;
        -n|--dry-run|--what-if|-WhatIf)
            DRY_RUN=1; shift ;;
        -h|--help|-Help)
            usage; exit 0 ;;
        -*)
            echo "Error: 未知のオプション: $1" >&2
            usage >&2
            exit 1 ;;
        *)
            if [[ -z "$TARGET_PATH" ]]; then
                TARGET_PATH="$1"; shift
            else
                echo "Error: 余分な引数: $1" >&2
                exit 1
            fi ;;
    esac
done

if [[ -z "$TARGET_PATH" ]]; then
    echo "Error: --target-path (-TargetPath) の指定が必須です。" >&2
    usage >&2
    exit 1
fi

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -d "$TARGET_PATH" ]]; then
    echo "Error: TargetPath が存在しません: $TARGET_PATH" >&2
    exit 1
fi
TARGET="$(cd "$TARGET_PATH" && pwd)"
OPENSPEC_DIR="$TARGET/openspec"

if [[ ! -d "$OPENSPEC_DIR" ]]; then
    echo "Error: openspec/ が見つかりません: $OPENSPEC_DIR" >&2
    echo "先に対象プロジェクトで 'openspec init' を実行してください。" >&2
    exit 1
fi

MARKER_BEGIN="<!-- openspec-kit:begin (install.ps1 により管理。手動編集は再同期で上書きされます) -->"
MARKER_END="<!-- openspec-kit:end -->"

echo "openspec-kit を導入します"
echo "  Target     : $TARGET"
echo "  BaseBranch : $BASE_BRANCH"
echo "  EvidenceDir: $EVIDENCE_DIR"

# プレースホルダ置換して標準出力へ出す関数
expand_placeholders() {
    local file="$1"
    sed -e "s|{{BASE_BRANCH}}|${BASE_BRANCH}|g" \
        -e "s|{{EVIDENCE_DIR}}|${EVIDENCE_DIR}|g" "$file" | tr -d '\r'
}

write_file() {
    local dst="$1"
    local content="$2"
    local with_bom="${3:-0}"
    local is_exec="${4:-0}"
    local dir
    dir="$(dirname "$dst")"
    mkdir -p "$dir"
    if [[ "$with_bom" -eq 1 ]]; then
        printf '\xEF\xBB\xBF%s\n' "$content" > "$dst"
    else
        printf '%s\n' "$content" > "$dst"
    fi
    if [[ "$is_exec" -eq 1 ]]; then
        chmod +x "$dst" 2>/dev/null || true
    fi
}

copy_kit_directory() {
    local src_dir="$1"
    local dst_dir="$2"
    local label="$3"
    local ps1_with_bom="${4:-0}"

    [[ -d "$src_dir" ]] || return 0

    for src_file in "$src_dir"/*; do
        [[ -f "$src_file" ]] || continue
        local fname
        fname="$(basename "$src_file")"
        local dst_file="$dst_dir/$fname"

        if [[ -f "$dst_file" && "$FORCE" -eq 0 ]]; then
            echo "  [skip] $label/$fname（既存。上書きは --force）"
            continue
        fi

        if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "What If: ターゲット \"$dst_file\" に対して操作 \"$label を配置\" を実行します。"
            continue
        fi

        local expanded
        expanded="$(expand_placeholders "$src_file")"
        local use_bom=0
        local use_exec=0
        if [[ "$ps1_with_bom" -eq 1 && "$fname" == *.ps1 ]]; then
            use_bom=1
        fi
        if [[ "$fname" == *.sh ]]; then
            use_exec=1
        fi
        write_file "$dst_file" "$expanded" "$use_bom" "$use_exec"
        echo "  [ok]   $label/$fname"
    done
}

# --- 1. テンプレート ----------------------------------------------------------
copy_kit_directory "$KIT_ROOT/templates" "$OPENSPEC_DIR/templates" "templates" 0

# --- 2. サブエージェント定義 --------------------------------------------------
copy_kit_directory "$KIT_ROOT/agents" "$OPENSPEC_DIR/agents" "agents" 0
if [[ -d "$TARGET/.claude" ]]; then
    copy_kit_directory "$KIT_ROOT/agents" "$TARGET/.claude/agents" ".claude/agents" 0
fi

# --- 3. フェーズゲート検証スクリプト ------------------------------------------
copy_kit_directory "$KIT_ROOT/scripts" "$OPENSPEC_DIR/scripts" "scripts" 1

# --- 4. SDD ワークフロー定義 --------------------------------------------------
copy_kit_directory "$KIT_ROOT/workflows" "$TARGET/.agents/workflows" ".agents/workflows" 0

# --- 5. config.yaml -----------------------------------------------------------
CONFIG_SRC="$KIT_ROOT/config.yaml"
CONFIG_DST="$OPENSPEC_DIR/config.yaml"
CONFIG_CONTENT="$(expand_placeholders "$CONFIG_SRC")"

if [[ "$SKIP_CONFIG" -eq 1 ]]; then
    echo "  [skip] openspec/config.yaml（--skip-config）"
elif [[ -f "$CONFIG_DST" && "$OVERWRITE_CONFIG" -eq 0 ]]; then
    SIDE_BY_SIDE="$OPENSPEC_DIR/config.kit.yaml"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "What If: ターゲット \"$SIDE_BY_SIDE\" に対して操作 \"既存 config.yaml と並べて出力\" を実行します。"
    else
        write_file "$SIDE_BY_SIDE" "$CONFIG_CONTENT" 0 0
        echo "  [warn] openspec/config.yaml は既存のため openspec/config.kit.yaml に出力しました。手動でマージ後、config.kit.yaml を削除してください（上書きは --overwrite-config）"
    fi
else
    if [[ -f "$CONFIG_DST" ]]; then
        BACKUP="${CONFIG_DST}.bak-$(date +%Y%m%d%H%M%S)"
        if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "What If: ターゲット \"$BACKUP\" に対して操作 \"既存 config.yaml をバックアップ\" を実行します。"
        else
            cp "$CONFIG_DST" "$BACKUP"
            echo "  [ok]   config.yaml をバックアップ: $(basename "$BACKUP")"
        fi
    fi
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "What If: ターゲット \"$CONFIG_DST\" に対して操作 \"config.yaml を配置\" を実行します。"
    else
        write_file "$CONFIG_DST" "$CONFIG_CONTENT" 0 0
        echo "  [ok]   openspec/config.yaml（context の技術スタック等の TODO を記入してください）"
    fi
fi

# --- 6. AGENTS.md -------------------------------------------------------------
SNIPPET="$(expand_placeholders "$KIT_ROOT/AGENTS.openspec.md")"
BLOCK="$(printf '%s\n\n%s\n\n%s' "$MARKER_BEGIN" "$SNIPPET" "$MARKER_END")"
AGENTS_PATH="$TARGET/AGENTS.md"

if [[ -f "$AGENTS_PATH" ]]; then
    if grep -q "<!-- openspec-kit:begin" "$AGENTS_PATH" && grep -q "$MARKER_END" "$AGENTS_PATH"; then
        ACTION="マーカー区間を置換"
        if [[ "$DRY_RUN" -eq 0 ]]; then
            BEFORE="$(awk '/<!-- openspec-kit:begin/{exit} {print}' "$AGENTS_PATH" | tr -d '\r')"
            AFTER="$(awk 'found{print} /<!-- openspec-kit:end -->/{found=1}' "$AGENTS_PATH" | tr -d '\r')"
            {
                [[ -n "$BEFORE" ]] && printf '%s\n' "$BEFORE"
                printf '%s\n' "$BLOCK"
                [[ -n "$AFTER" ]] && printf '%s\n' "$AFTER"
            } > "$AGENTS_PATH"
        fi
    else
        ACTION="末尾に追記"
        if [[ "$DRY_RUN" -eq 0 ]]; then
            EXISTING="$(tr -d '\r' < "$AGENTS_PATH" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"
            printf '%s\n\n---\n\n%s\n' "$EXISTING" "$BLOCK" > "$AGENTS_PATH"
        fi
    fi
else
    ACTION="新規作成"
    if [[ "$DRY_RUN" -eq 0 ]]; then
        SKELETON="$(expand_placeholders "$KIT_ROOT/AGENTS.project.md")"
        printf '%s\n\n---\n\n%s\n' "$SKELETON" "$BLOCK" > "$AGENTS_PATH"
    fi
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "What If: ターゲット \"$AGENTS_PATH\" に対して操作 \"AGENTS.md: $ACTION\" を実行します。"
else
    echo "  [ok]   AGENTS.md（$ACTION。管理区間外の TODO（概要・フォーマットコマンド等）を記入してください）"
fi

# --- 7. .gitignore ------------------------------------------------------------
GITIGNORE_PATH="$TARGET/.gitignore"
IGNORE_LINE="${EVIDENCE_DIR//\\//}"
ALREADY_IGNORED=0
if [[ -f "$GITIGNORE_PATH" ]]; then
    if tr -d '\r' < "$GITIGNORE_PATH" | grep -Fxq "$IGNORE_LINE"; then
        ALREADY_IGNORED=1
    fi
fi

if [[ "$ALREADY_IGNORED" -eq 0 ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "What If: ターゲット \"$GITIGNORE_PATH\" に対して操作 \"$IGNORE_LINE を追記\" を実行します。"
    else
        if [[ -f "$GITIGNORE_PATH" && -s "$GITIGNORE_PATH" ]]; then
            EXISTING_IG="$(tr -d '\r' < "$GITIGNORE_PATH")"
            printf '%s\n\n# Test evidence & coverage (openspec-kit)\n%s\n' "$EXISTING_IG" "$IGNORE_LINE" > "$GITIGNORE_PATH"
        else
            printf '# Test evidence & coverage (openspec-kit)\n%s\n' "$IGNORE_LINE" > "$GITIGNORE_PATH"
        fi
        echo "  [ok]   .gitignore に $IGNORE_LINE を追記"
    fi
fi

# --- 8. CLAUDE.md / GEMINI.md -------------------------------------------------
for entry in CLAUDE.md GEMINI.md; do
    ENTRY_PATH="$TARGET/$entry"
    if [[ -f "$ENTRY_PATH" ]]; then
        if ! grep -q "@AGENTS\.md" "$ENTRY_PATH"; then
            echo "  [warn] $entry は既存で @AGENTS.md を参照していません。必要に応じて '@AGENTS.md' を追記してください"
        fi
        continue
    fi
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "What If: ターゲット \"$ENTRY_PATH\" に対して操作 \"@AGENTS.md を参照するエントリファイルを作成\" を実行します。"
    else
        printf '@AGENTS.md\n' > "$ENTRY_PATH"
        echo "  [ok]   $entry（@AGENTS.md）"
    fi
done

echo "完了。'openspec instructions proposal --change <name> --json' 等で context / rules が反映されることを確認してください。"
