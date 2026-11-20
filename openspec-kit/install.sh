#!/usr/bin/env bash
# =============================================================================
# openspec-kit/install.sh
#   openspec-kit（サブエージェント6ロール・5エージェント共通 Skills・TDD/C0-C2基準・
#   フェーズゲート・テンプレート）を対象プロジェクトへ導入／再同期する
#   （Bash 版: Linux / macOS / Git Bash / WSL 対応）。
#
# 使い方:
#   ./openspec-kit/install.sh --target-path <dir> [--base-branch develop] [--evidence-dir test/TestResults/] [--agent-targets auto] [--force] [--overwrite-config] [--skip-config] [--dry-run]
#   ※ PowerShell 版と同じ引数名（-TargetPath, -BaseBranch, -EvidenceDir, -AgentTargets, -Force, -OverwriteConfig, -SkipConfig, -WhatIf）も指定可能
# =============================================================================
set -euo pipefail

TARGET_PATH=""
BASE_BRANCH="develop"
EVIDENCE_DIR="test/TestResults/"
AGENT_TARGETS="auto"
FORCE=0
OVERWRITE_CONFIG=0
SKIP_CONFIG=0
DRY_RUN=0

TMP_AGENTS=""
trap 'rm -f "${TMP_AGENTS:-}"' EXIT INT TERM

usage() {
    cat <<'EOF'
Usage:
  install.sh --target-path <path> [options]

Options:
  -t, --target-path, -TargetPath <path>       導入先プロジェクトのルートディレクトリ（必須）
  -b, --base-branch, -BaseBranch <branch>     ベースブランチ名（既定: develop）
  -e, --evidence-dir, -EvidenceDir <dir>      テストエビデンス出力先（既定: test/TestResults/）
  -a, --agent-targets, -AgentTargets <list>   スキル展開先: auto(既定)|all|antigravity,claude,copilot,opencode,hermes
  -f, --force, -Force                         既存テンプレート・エージェント・スクリプト・スキルを上書き
      --overwrite-config, -OverwriteConfig    既存 openspec/config.yaml をバックアップして上書き
      --skip-config, -SkipConfig              openspec/config.yaml の処理をスキップ
  -n, --dry-run, --what-if, -WhatIf           ファイルを書き込まず実行予定のみ表示
  -h, --help                                  このヘルプを表示
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--target-path|-TargetPath)
            if [[ $# -lt 2 ]]; then echo "Error: $1 に値が指定されていません。" >&2; exit 1; fi
            TARGET_PATH="$2"; shift 2 ;;
        -b|--base-branch|-BaseBranch)
            if [[ $# -lt 2 ]]; then echo "Error: $1 に値が指定されていません。" >&2; exit 1; fi
            BASE_BRANCH="$2"; shift 2 ;;
        -e|--evidence-dir|-EvidenceDir)
            if [[ $# -lt 2 ]]; then echo "Error: $1 に値が指定されていません。" >&2; exit 1; fi
            EVIDENCE_DIR="$2"; shift 2 ;;
        -a|--agent-targets|-AgentTargets)
            if [[ $# -lt 2 ]]; then echo "Error: $1 に値が指定されていません。" >&2; exit 1; fi
            AGENT_TARGETS="$2"; shift 2 ;;
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

assert_no_linebreaks() {
    local name="$1"
    local val="$2"
    if [[ "$val" == *$'\n'* || "$val" == *$'\r'* ]]; then
        echo "Error: Invalid $name: 改行（CR/LF）または NUL 文字を含めることはできません。" >&2
        exit 1
    fi
}

assert_no_linebreaks "--base-branch" "$BASE_BRANCH"
assert_no_linebreaks "--evidence-dir" "$EVIDENCE_DIR"
assert_no_linebreaks "--agent-targets" "$AGENT_TARGETS"

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

agent_root_dir() {
    case "$1" in
        antigravity) echo ".agents" ;;
        claude)      echo ".claude" ;;
        copilot)     echo ".github" ;;
        opencode)    echo ".opencode" ;;
        hermes)      echo ".hermes" ;;
        *)           return 1 ;;
    esac
}

trim_ws() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

join_by() {
    local sep="$1"
    shift
    local first=1 item out=""
    for item in "$@"; do
        if [[ "$first" -eq 1 ]]; then
            out="$item"
            first=0
        else
            out="${out}${sep}${item}"
        fi
    done
    printf '%s' "$out"
}

confirm_action() {
    local target_path="$1"
    local operation="$2"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "What If: ターゲット \"$target_path\" に対して操作 \"$operation\" を実行します。"
        return 1
    fi
    return 0
}

resolve_backup_path() {
    local base_prefix="$1"
    local initial_candidate="$2"
    if [[ ! -e "$initial_candidate" ]]; then
        printf '%s' "$initial_candidate"
        return 0
    fi
    local ts counter=1 candidate
    ts="$(date +%Y%m%d%H%M%S)"
    while true; do
        candidate="${base_prefix}-${ts}-${counter}"
        if [[ ! -e "$candidate" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
        counter=$((counter + 1))
    done
}

assert_not_regular_file() {
    local p="$1"
    if [[ -e "$p" && ! -d "$p" ]]; then
        echo "Error: 展開先パス '$p' がディレクトリではなく通常ファイルとして存在するため導入できません。" >&2
        exit 1
    fi
}

assert_not_directory() {
    local p="$1"
    if [[ -d "$p" ]]; then
        echo "Error: 展開先ファイルパス '$p' に既にディレクトリが存在するため導入できません。" >&2
        exit 1
    fi
}

assert_dir_tree_destinations() {
    local src_dir="${1%/}"
    local dst_dir="$2"
    local recurse="${3:-0}"
    assert_not_regular_file "$dst_dir"
    [[ -d "$src_dir" ]] || return 0
    if [[ "$recurse" -eq 1 ]]; then
        local sub
        while IFS= read -r -d '' sub; do
            local rel="${sub#"$src_dir"/}"
            assert_not_regular_file "$dst_dir/$rel"
        done < <(find "$src_dir" -mindepth 1 -type d -print0)
        local f
        while IFS= read -r -d '' f; do
            local rel="${f#"$src_dir"/}"
            assert_not_directory "$dst_dir/$rel"
        done < <(find "$src_dir" -type f -print0)
    else
        local f
        while IFS= read -r -d '' f; do
            local rel="${f#"$src_dir"/}"
            assert_not_directory "$dst_dir/$rel"
        done < <(find "$src_dir" -maxdepth 1 -type f -print0)
    fi
}

# --- 0. --agent-targets バリデーションと解決（書き込み前） --------------------
TRIMMED_TARGETS="$(trim_ws "$AGENT_TARGETS")"
if [[ -z "$TRIMMED_TARGETS" ]]; then
    echo "Error: Invalid --agent-targets: 空文字または空白のみは指定できません。" >&2
    exit 1
fi

if [[ "$TRIMMED_TARGETS" == ,* || "$TRIMMED_TARGETS" == *, || "$TRIMMED_TARGETS" == *,,* ]]; then
    echo "Error: Invalid --agent-targets '$AGENT_TARGETS': 空のトークンが含まれています。" >&2
    exit 1
fi

IFS=',' read -r -a RAW_TOKENS <<< "$TRIMMED_TARGETS"
NORMALIZED_TOKENS=()
for raw_tok in "${RAW_TOKENS[@]}"; do
    tok="$(trim_ws "$raw_tok" | tr '[:upper:]' '[:lower:]')"
    if [[ -z "$tok" ]]; then
        echo "Error: Invalid --agent-targets '$AGENT_TARGETS': 空のトークンが含まれています。" >&2
        exit 1
    fi
    case "$tok" in
        auto|all|antigravity|claude|copilot|opencode|hermes) ;;
        *)
            echo "Error: Invalid --agent-targets '$AGENT_TARGETS': 未知のターゲット '$tok' です。" >&2
            exit 1 ;;
    esac
    if [[ ( "$tok" == "auto" || "$tok" == "all" ) && "${#RAW_TOKENS[@]}" -gt 1 ]]; then
        echo "Error: Invalid --agent-targets '$AGENT_TARGETS': '$tok' は他のターゲットと同時に指定できません。" >&2
        exit 1
    fi
    already_in=0
    for existing_tok in "${NORMALIZED_TOKENS[@]+"${NORMALIZED_TOKENS[@]}"}"; do
        if [[ "$existing_tok" == "$tok" ]]; then
            already_in=1
            break
        fi
    done
    if [[ "$already_in" -eq 0 ]]; then
        NORMALIZED_TOKENS+=("$tok")
    fi
done

RESOLVED_TARGETS=()
IS_ZERO_STATE_AUTO=0

if [[ "${#NORMALIZED_TOKENS[@]}" -eq 1 && "${NORMALIZED_TOKENS[0]}" == "auto" ]]; then
    RESOLVED_TARGETS+=("antigravity")
    DETECTED_OTHERS=0
    for agent_name in claude copilot opencode hermes; do
        root_rel="$(agent_root_dir "$agent_name")"
        root_full="$TARGET/$root_rel"
        if [[ -e "$root_full" ]]; then
            assert_not_regular_file "$root_full"
            RESOLVED_TARGETS+=("$agent_name")
            DETECTED_OTHERS=$((DETECTED_OTHERS + 1))
        fi
    done
    if [[ "$DETECTED_OTHERS" -eq 0 ]]; then
        IS_ZERO_STATE_AUTO=1
    fi
elif [[ "${#NORMALIZED_TOKENS[@]}" -eq 1 && "${NORMALIZED_TOKENS[0]}" == "all" ]]; then
    RESOLVED_TARGETS=(antigravity claude copilot opencode hermes)
else
    RESOLVED_TARGETS=("${NORMALIZED_TOKENS[@]}")
fi

# 展開先パス種別衝突チェック（書き込み前）
assert_dir_tree_destinations "$KIT_ROOT/templates" "$OPENSPEC_DIR/templates" 0
assert_dir_tree_destinations "$KIT_ROOT/agents" "$OPENSPEC_DIR/agents" 0
assert_dir_tree_destinations "$KIT_ROOT/scripts" "$OPENSPEC_DIR/scripts" 0

if [[ -e "$TARGET/.claude" ]]; then
    assert_not_regular_file "$TARGET/.claude"
    assert_dir_tree_destinations "$KIT_ROOT/agents" "$TARGET/.claude/agents" 0
fi

for agent_name in "${RESOLVED_TARGETS[@]}"; do
    root_rel="$(agent_root_dir "$agent_name")"
    assert_not_regular_file "$TARGET/$root_rel"
    assert_dir_tree_destinations "$KIT_ROOT/skills" "$TARGET/$root_rel/skills" 1
done

CONFIG_DST="$OPENSPEC_DIR/config.yaml"
if [[ "$SKIP_CONFIG" -eq 0 ]]; then
    assert_not_directory "$CONFIG_DST"
    assert_not_directory "$OPENSPEC_DIR/config.kit.yaml"
fi

AGENTS_PATH="$TARGET/AGENTS.md"
assert_not_directory "$AGENTS_PATH"
GITIGNORE_PATH="$TARGET/.gitignore"
assert_not_directory "$GITIGNORE_PATH"
assert_not_directory "$TARGET/CLAUDE.md"
assert_not_directory "$TARGET/GEMINI.md"

# AGENTS.md のマーカー多重/順序逆転チェック（書き込み前・文字インデックスベース）
check_agents_markers() {
    local target_file="$1"
    KIT_TARGET_FILE="$target_file" KIT_M_END="$MARKER_END" awk '
    function count_str(str, pat,    cnt, pos, plen) {
        cnt = 0
        plen = length(pat)
        while ((pos = index(str, pat)) > 0) {
            cnt++
            str = substr(str, pos + plen)
        }
        return cnt
    }
    BEGIN {
        m_begin = "<!-- openspec-kit:begin"
        m_end = ENVIRON["KIT_M_END"]
        path = ENVIRON["KIT_TARGET_FILE"]
        buf = ""
        first = 1
        while ((getline line < path) > 0) {
            gsub(/\r/, "", line)
            buf = (first ? line : buf "\n" line)
            first = 0
        }
        close(path)
        b_cnt = count_str(buf, m_begin)
        e_cnt = count_str(buf, m_end)
        if (b_cnt == 0 && e_cnt == 0) {
            print "NONE"
        } else if (b_cnt == 1 && e_cnt == 1 && index(buf, m_begin) < index(buf, m_end)) {
            print "VALID"
        } else {
            print "CORRUPT"
        }
    }'
}

MARKER_STATUS="NEW"
if [[ -f "$AGENTS_PATH" ]]; then
    MARKER_STATUS="$(check_agents_markers "$AGENTS_PATH")"
    if [[ "$MARKER_STATUS" == "CORRUPT" ]]; then
        echo "Error: AGENTS.md の管理マーカーが破損しています（片側マーカーのみ残存、多重出現、または順序不正）: $AGENTS_PATH" >&2
        echo "手動で '<!-- openspec-kit:begin ... -->' と '$MARKER_END' のペアを修復または削除してから再実行してください。" >&2
        exit 1
    fi
fi

echo "openspec-kit を導入します"
echo "  Target       : $TARGET"
echo "  BaseBranch   : $BASE_BRANCH"
echo "  EvidenceDir  : $EVIDENCE_DIR"
echo "  AgentTargets : $(join_by ', ' "${RESOLVED_TARGETS[@]}") (指定: $AGENT_TARGETS)"

# プレースホルダを 1 パス同時置換（特殊文字 &, \, | 安全、.ps1 時のみ ' を '' にエスケープ）
expand_placeholders() {
    local file="$1"
    local escape_sq="${2:-0}"
    BASE_VAL="$BASE_BRANCH" EVID_VAL="$EVIDENCE_DIR" ESCAPE_SQ="$escape_sq" awk '
    function expand_line(str, b, e,    out, pb, pe, pos, rep, plen) {
        out = ""
        while (1) {
            pb = index(str, "{{BASE_BRANCH}}")
            pe = index(str, "{{EVIDENCE_DIR}}")
            if (pb == 0 && pe == 0) {
                return out str
            }
            if (pb > 0 && (pe == 0 || pb < pe)) {
                pos = pb
                rep = b
                plen = 15
            } else {
                pos = pe
                rep = e
                plen = 16
            }
            out = out substr(str, 1, pos - 1) rep
            str = substr(str, pos + plen)
        }
    }
    BEGIN {
        b = ENVIRON["BASE_VAL"]
        e = ENVIRON["EVID_VAL"]
        if (ENVIRON["ESCAPE_SQ"] == "1") {
            sq = sprintf("%c", 39)
            gsub(sq, sq sq, b)
            gsub(sq, sq sq, e)
        }
    }
    {
        gsub(/\r/, "", $0)
        print expand_line($0, b, e)
    }' "$file"
}

read_trimmed_file() {
    KIT_TRIM_FILE="$1" awk '
    BEGIN {
        path = ENVIRON["KIT_TRIM_FILE"]
        out = ""
        first = 1
        while ((getline line < path) > 0) {
            gsub(/\r/, "", line)
            out = (first ? line : out "\n" line)
            first = 0
        }
        close(path)
        sub(/[ \t\r\n]+$/, "", out)
        printf "%s", out
    }'
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
        local chmod_err
        if ! chmod_err="$(chmod +x "$dst" 2>&1)"; then
            echo "  [warn] chmod +x '$dst' に失敗しました: $chmod_err" >&2
        fi
    fi
}

TOTAL_SKILLS_DEPLOYED=0
TOTAL_SKILLS_SKIPPED=0

copy_kit_directory() {
    local src_dir="${1%/}"
    local dst_dir="$2"
    local label="$3"
    local ps1_with_bom="${4:-0}"
    local track_skill="${5:-0}"
    local recurse="${6:-0}"

    [[ -d "$src_dir" ]] || return 0

    local find_args=("$src_dir")
    if [[ "$recurse" -eq 0 ]]; then
        find_args+=(-maxdepth 1)
    fi
    find_args+=(-type f -print0)

    local src_file
    while IFS= read -r -d '' src_file; do
        local rel="${src_file#"$src_dir"/}"
        local fname
        fname="$(basename "$src_file")"
        local dst_file="$dst_dir/$rel"

        if [[ -f "$dst_file" && "$FORCE" -eq 0 ]]; then
            if [[ "$track_skill" -eq 1 ]]; then
                TOTAL_SKILLS_SKIPPED=$((TOTAL_SKILLS_SKIPPED + 1))
            fi
            echo "  [skip] $label/$rel（既存。上書きは --force）"
            continue
        fi

        if ! confirm_action "$dst_file" "$label を配置"; then
            continue
        fi

        local is_ps1=0
        local use_bom=0
        local use_exec=0
        if [[ "$fname" == *.ps1 ]]; then
            is_ps1=1
            if [[ "$ps1_with_bom" -eq 1 ]]; then
                use_bom=1
            fi
        fi
        if [[ "$fname" == *.sh ]]; then
            use_exec=1
        fi

        local expanded
        expanded="$(expand_placeholders "$src_file" "$is_ps1")"
        write_file "$dst_file" "$expanded" "$use_bom" "$use_exec"
        if [[ "$track_skill" -eq 1 ]]; then
            TOTAL_SKILLS_DEPLOYED=$((TOTAL_SKILLS_DEPLOYED + 1))
        fi
        echo "  [ok]   $label/$rel"
    done < <(find "${find_args[@]}" | sort -z)
}

# --- 1. テンプレート ----------------------------------------------------------
copy_kit_directory "$KIT_ROOT/templates" "$OPENSPEC_DIR/templates" "templates" 0 0 0

# --- 2. サブエージェント定義 --------------------------------------------------
copy_kit_directory "$KIT_ROOT/agents" "$OPENSPEC_DIR/agents" "agents" 0 0 0
if [[ -d "$TARGET/.claude" ]]; then
    copy_kit_directory "$KIT_ROOT/agents" "$TARGET/.claude/agents" ".claude/agents" 0 0 0
fi

# --- 3. フェーズゲート検証スクリプト ------------------------------------------
copy_kit_directory "$KIT_ROOT/scripts" "$OPENSPEC_DIR/scripts" "scripts" 1 0 0

# --- 4. SDD スキル多面展開 ----------------------------------------------------
DEPLOYED_SKILL_PATHS=()
HAS_ANTIGRAVITY_TARGET=0
for agent_name in "${RESOLVED_TARGETS[@]}"; do
    if [[ "$agent_name" == "antigravity" ]]; then
        HAS_ANTIGRAVITY_TARGET=1
    fi
    root_rel="$(agent_root_dir "$agent_name")"
    skills_rel="$root_rel/skills"
    copy_kit_directory "$KIT_ROOT/skills" "$TARGET/$skills_rel" "$skills_rel" 0 1 1
    DEPLOYED_SKILL_PATHS+=("$skills_rel")
done

# --- 5. レガシーワークフロー（.agents/workflows/sdd-*.md）の後段安全退避 ------
MIGRATED_BACKUPS=()
if [[ "$HAS_ANTIGRAVITY_TARGET" -eq 1 && -d "$TARGET/.agents/workflows" ]]; then
    LEGACY_WF_DIR="$TARGET/.agents/workflows"
    for wf_name in sdd-propose.md sdd-apply.md sdd-archive.md; do
        wf_path="$LEGACY_WF_DIR/$wf_name"
        [[ -f "$wf_path" ]] || continue

        candidate_bak="$(resolve_backup_path "${wf_path}.bak" "${wf_path}.bak")"
        bak_leaf="$(basename "$candidate_bak")"

        if ! confirm_action "$wf_path" "旧 SDD ワークフローを $bak_leaf へ退避"; then
            continue
        fi

        if ! mv_err="$(mv -f "$wf_path" "$candidate_bak" 2>&1)"; then
            echo "Error: 旧ワークフロー '$wf_path' を '$candidate_bak' へ退避（リネーム）できませんでした: $mv_err" >&2
            echo "ファイルを開いているエディタやプロセスを閉じるか、手動でバックアップ退避・リネームまたは削除してから再実行してください。" >&2
            exit 1
        fi
        MIGRATED_BACKUPS+=(".agents/workflows/$bak_leaf")
        echo "  [bak]  .agents/workflows/$wf_name -> .agents/workflows/$bak_leaf"
    done
fi

# --- 6. config.yaml -----------------------------------------------------------
if [[ "$SKIP_CONFIG" -eq 1 ]]; then
    echo "  [skip] openspec/config.yaml（--skip-config）"
else
    CONFIG_SRC="$KIT_ROOT/config.yaml"
    CONFIG_CONTENT="$(expand_placeholders "$CONFIG_SRC" 0)"

    if [[ -f "$CONFIG_DST" && "$OVERWRITE_CONFIG" -eq 0 ]]; then
        SIDE_BY_SIDE="$OPENSPEC_DIR/config.kit.yaml"
        if confirm_action "$SIDE_BY_SIDE" "既存 config.yaml と並べて出力"; then
            write_file "$SIDE_BY_SIDE" "$CONFIG_CONTENT" 0 0
            echo "  [warn] openspec/config.yaml は既存のため openspec/config.kit.yaml に出力しました。手動でマージ後、config.kit.yaml を削除してください（上書きは --overwrite-config）"
        fi
    else
        if [[ -f "$CONFIG_DST" ]]; then
            TS_PREFIX="${CONFIG_DST}.bak-$(date +%Y%m%d%H%M%S)"
            BACKUP="$(resolve_backup_path "$TS_PREFIX" "$TS_PREFIX")"
            if confirm_action "$BACKUP" "既存 config.yaml をバックアップ"; then
                cp "$CONFIG_DST" "$BACKUP"
                echo "  [ok]   config.yaml をバックアップ: $(basename "$BACKUP")"
            fi
        fi
        if confirm_action "$CONFIG_DST" "config.yaml を配置"; then
            write_file "$CONFIG_DST" "$CONFIG_CONTENT" 0 0
            echo "  [ok]   openspec/config.yaml（context の技術スタック等の TODO を記入してください）"
        fi
    fi
fi

# --- 7. AGENTS.md（mktemp + trap によるアトミック更新） ------------------------
if [[ "$MARKER_STATUS" == "VALID" ]]; then
    ACTION="マーカー区間を置換"
elif [[ "$MARKER_STATUS" == "NONE" ]]; then
    ACTION="末尾に追記"
else
    ACTION="新規作成"
fi

render_agents_md() {
    BASE_VAL="$BASE_BRANCH" \
    EVID_VAL="$EVIDENCE_DIR" \
    KIT_M_BEGIN="$MARKER_BEGIN" \
    KIT_M_END="$MARKER_END" \
    KIT_STATUS="$MARKER_STATUS" \
    KIT_AGENTS_FILE="$AGENTS_PATH" \
    KIT_SNIPPET_FILE="$KIT_ROOT/AGENTS.openspec.md" \
    KIT_SKELETON_FILE="$KIT_ROOT/AGENTS.project.md" \
    awk '
    function expand_line(str, b, e,    out, pb, pe, pos, rep, plen) {
        out = ""
        while (1) {
            pb = index(str, "{{BASE_BRANCH}}")
            pe = index(str, "{{EVIDENCE_DIR}}")
            if (pb == 0 && pe == 0) return out str
            if (pb > 0 && (pe == 0 || pb < pe)) {
                pos = pb; rep = b; plen = 15
            } else {
                pos = pe; rep = e; plen = 16
            }
            out = out substr(str, 1, pos - 1) rep
            str = substr(str, pos + plen)
        }
    }
    function read_file_lf(path, do_expand, b, e,    line, res, first, rc) {
        res = ""
        first = 1
        while ((rc = (getline line < path)) > 0) {
            gsub(/\r/, "", line)
            if (do_expand) line = expand_line(line, b, e)
            res = (first ? line : res "\n" line)
            first = 0
        }
        close(path)
        return res
    }
    function rtrim_ws(s) {
        sub(/[ \t\r\n]+$/, "", s)
        return s
    }
    BEGIN {
        b = ENVIRON["BASE_VAL"]
        e = ENVIRON["EVID_VAL"]
        m_begin_prefix = "<!-- openspec-kit:begin"
        m_begin = ENVIRON["KIT_M_BEGIN"]
        m_end = ENVIRON["KIT_M_END"]
        status = ENVIRON["KIT_STATUS"]

        snippet = rtrim_ws(read_file_lf(ENVIRON["KIT_SNIPPET_FILE"], 1, b, e))
        block = m_begin "\n\n" snippet "\n\n" m_end

        if (status == "VALID") {
            agents = read_file_lf(ENVIRON["KIT_AGENTS_FILE"], 0, b, e)
            b_idx = index(agents, m_begin_prefix)
            e_idx = index(agents, m_end)
            before_raw = substr(agents, 1, b_idx - 1)
            if (before_raw ~ /^[ \t\r\n]*$/) {
                before_part = ""
            } else {
                before_part = before_raw
                sub(/\n$/, "", before_part)
            }

            after_raw = substr(agents, e_idx + length(m_end))
            if (after_raw ~ /^[ \t\r\n]*$/) {
                after_part = ""
            } else {
                after_part = after_raw
                sub(/^\n/, "", after_part)
                sub(/\n+$/, "", after_part)
            }

            out = ""
            if (before_part != "") out = before_part "\n"
            out = out block
            if (after_part != "") out = out "\n" after_part
            out = out "\n"
        } else if (status == "NONE") {
            agents = rtrim_ws(read_file_lf(ENVIRON["KIT_AGENTS_FILE"], 0, b, e))
            out = agents "\n\n---\n\n" block "\n"
        } else {
            skeleton = rtrim_ws(read_file_lf(ENVIRON["KIT_SKELETON_FILE"], 1, b, e))
            out = skeleton "\n\n---\n\n" block "\n"
        }
        printf "%s", out
    }'
}

if confirm_action "$AGENTS_PATH" "AGENTS.md: $ACTION"; then
    TMP_AGENTS="$(mktemp "${AGENTS_PATH}.tmp.XXXXXX")"
    render_agents_md > "$TMP_AGENTS"
    AGENTS_BYTES="$(wc -c < "$TMP_AGENTS" | tr -d '[:space:]')"
    mv -f "$TMP_AGENTS" "$AGENTS_PATH"
    TMP_AGENTS=""
    echo "  [ok]   AGENTS.md（$ACTION / $AGENTS_BYTES bytes。管理区間外の TODO を記入してください）"
    if [[ "$AGENTS_BYTES" -ge 24000 ]]; then
        EXCESS_BYTES=$((AGENTS_BYTES - 24000))
        echo "  [warn] AGENTS.md のサイズが 24,000 バイト上限以上です（実バイト数: $AGENTS_BYTES bytes / 超過: $EXCESS_BYTES bytes）。プロジェクト固有ルールを別ファイル（references 等）へ分割してください。"
    fi
else
    AGENTS_BYTES="$(render_agents_md | wc -c | tr -d '[:space:]')"
fi

# --- 8. .gitignore ------------------------------------------------------------
IGNORE_LINE="${EVIDENCE_DIR//\\//}"
ALREADY_IGNORED=0
if [[ -f "$GITIGNORE_PATH" ]]; then
    if tr -d '\r' < "$GITIGNORE_PATH" | grep -Fxq -- "$IGNORE_LINE"; then
        ALREADY_IGNORED=1
    fi
fi

if [[ "$ALREADY_IGNORED" -eq 0 ]] && confirm_action "$GITIGNORE_PATH" "$IGNORE_LINE を追記"; then
    EXISTING_IG=""
    if [[ -f "$GITIGNORE_PATH" ]]; then
        EXISTING_IG="$(read_trimmed_file "$GITIGNORE_PATH")"
    fi
    if [[ -n "$EXISTING_IG" ]]; then
        printf '%s\n\n# Test evidence & coverage (openspec-kit)\n%s\n' "$EXISTING_IG" "$IGNORE_LINE" > "$GITIGNORE_PATH"
    else
        printf '# Test evidence & coverage (openspec-kit)\n%s\n' "$IGNORE_LINE" > "$GITIGNORE_PATH"
    fi
    echo "  [ok]   .gitignore に $IGNORE_LINE を追記"
fi

# --- 9. CLAUDE.md / GEMINI.md -------------------------------------------------
for entry in CLAUDE.md GEMINI.md; do
    ENTRY_PATH="$TARGET/$entry"
    if [[ -f "$ENTRY_PATH" ]]; then
        if ! grep -Fq -- "@AGENTS.md" "$ENTRY_PATH"; then
            echo "  [warn] $entry は既存で @AGENTS.md を参照していません。必要に応じて '@AGENTS.md' を追記してください"
        fi
        continue
    fi
    if confirm_action "$ENTRY_PATH" "@AGENTS.md を参照するエントリファイルを作成"; then
        printf '@AGENTS.md\n' > "$ENTRY_PATH"
        echo "  [ok]   $entry（@AGENTS.md）"
    fi
done

# --- 10. 可観測性サマリとガイダンス -------------------------------------------
echo ""
echo "=== openspec-kit 導入サマリ ==="
echo "  対象ターゲット : $(join_by ', ' "${RESOLVED_TARGETS[@]}")"
echo "  スキル展開先   : $(join_by ', ' "${DEPLOYED_SKILL_PATHS[@]}")"
echo "  スキル配置件数 : 配置 ${TOTAL_SKILLS_DEPLOYED} 件 / スキップ ${TOTAL_SKILLS_SKIPPED} 件"
echo "  旧WF退避件数   : ${#MIGRATED_BACKUPS[@]} 件"
echo "  AGENTS.md      : ${AGENTS_BYTES} bytes"

if [[ "$TOTAL_SKILLS_SKIPPED" -gt 0 && "$FORCE" -eq 0 ]]; then
    echo "  [warn] 既存のスキルファイルが ${TOTAL_SKILLS_SKIPPED} 件スキップされました。更新された AGENTS.md との不整合を防ぐため、--force（-Force）を付けて再実行することを推奨します。"
fi

if [[ "$IS_ZERO_STATE_AUTO" -eq 1 ]]; then
    echo "  [info] 他のエージェントディレクトリ（.claude / .github / .opencode / .hermes）が未検出のため、.agents/skills のみに配置しました。後から他エージェントを追加する場合は --agent-targets（-AgentTargets）を指定して再実行してください（例: --agent-targets claude,copilot または --agent-targets all）。"
fi

if [[ "${#MIGRATED_BACKUPS[@]}" -gt 0 ]]; then
    echo "  [info] 旧 .agents/workflows/sdd-*.md を .bak（$(join_by ', ' "${MIGRATED_BACKUPS[@]}")）へ退避しました。カスタム記述がある場合は内容を確認し、不要であれば .bak ファイルを削除してください。"
fi

echo "完了。'openspec instructions proposal --change <name> --json' 等で context / rules が反映されることを確認してください。"
