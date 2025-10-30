#!/bin/bash

# --- 配置 ---
UPLOAD_API="https://www.dlink666.com/api/upload"
JQ_CMD=$(which jq)

# ANSI 颜色代码
BLUE='\e[34m'
RESET='\e[0m'

# 检查 jq 是否安装
if [ $? -ne 0 ]; then
    echo "🚨 错误：未找到 'jq'。请安装 'jq' 以处理 JSON 数据。" >&2
    echo "在 Debian/Ubuntu 上: sudo apt install jq" >&2
    exit 1
fi

# --- 上传函数 (保持不变) ---
upload_file() {
    local file_path="$1"
    local relative_path="$2"
    local file_name=$(basename "$file_path")
    local full_url="${UPLOAD_API}?name=${file_name}"
    local response=""
    local uploaded_url=""
    local exit_code

    echo "  -> [开始] 上传文件: $relative_path" >&2

    response=$(curl -sS -T "$file_path" "$full_url")
    exit_code=$?

    if [ $exit_code -eq 0 ]; then
        uploaded_url=$(echo "$response" | tr -d '[:space:][:cntrl:]')

        if [[ "$uploaded_url" == https://* ]]; then
            echo "  ✅ [成功] URL: $uploaded_url" >&2

            local json_item="{
                \"absolute_path\": \"$file_path\",
                \"relative_path\": \"$relative_path\",
                \"filename\": \"$file_name\",
                \"url\": \"$uploaded_url\"
            }"
            printf "%s" "$json_item"
        else
            echo "  ❌ [失败] 服务器响应异常。文件: $relative_path" >&2
            echo "    返回内容: $response" >&2
        fi
    else
        echo "  ❌ [失败] curl 退出代码 $exit_code。文件: $relative_path" >&2
        if [ -n "$response" ]; then
             echo "    curl 错误信息: $response" >&2
        fi
    fi
}

# ----------------------------------------------------------------------
# --- 主执行逻辑函数 (main) ---
# ----------------------------------------------------------------------
main() {
    if [ -z "$1" ]; then
        echo "🚨 错误：请提供要上传的路径或要下载的 URL。" >&2
        echo "用法:" >&2
        echo "  $0 /path/to/file_or_folder (上传模式)" >&2
        echo "  $0 https://url/to/file_or_json (下载模式)" >&2
        return 1
    fi

    local TARGET="$1"

    # ===============================================
    # 1. 模式判断：URL (下载)
    # ===============================================
    if [[ "$TARGET" =~ ^https?:// ]]; then
        # --- 下载模式代码 (保持不变) ---

        local DOWNLOAD_URL="$TARGET"
        local TEMP_CLEAN_FILE=$(mktemp)

        echo "📥 正在检查 URL 类型: $DOWNLOAD_URL" >&2

        local CONTENT=$(curl -sL "$DOWNLOAD_URL")
        local EXIT_CODE=$?

        if [ $EXIT_CODE -ne 0 ]; then
            echo "❌ 错误：无法访问 URL ($EXIT_CODE)。请检查网络或 URL 是否有效。" >&2
            rm "$TEMP_CLEAN_FILE"
            return 1
        fi

        # 严格清理内容并写入临时文件
        local CLEAN_CONTENT=$(echo "$CONTENT" | tr -d '\000' | tr -d '[:cntrl:]' | tr -s '[:space:]' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        printf "%s" "$CLEAN_CONTENT" > "$TEMP_CLEAN_FILE"

        if [ ! -s "$TEMP_CLEAN_FILE" ]; then
            echo "❌ 错误：URL 内容为空或全为空白字符。" >&2
            rm "$TEMP_CLEAN_FILE"
            return 1
        fi

        $JQ_CMD -e '.[0]' "$TEMP_CLEAN_FILE" > /dev/null 2>&1
        local JQ_EXIT_CODE=$?

        if [ $JQ_EXIT_CODE -eq 0 ]; then
            # 批量下载 (JSON 清单)

            echo "---" >&2
            echo "📦 模式: 检测到 JSON 清单，将执行批量下载。" >&2

            local DOWNLOAD_DIR="download-$(date +%Y%m%d_%H%M%S)"
            mkdir -p "$DOWNLOAD_DIR"
            echo "📁 所有文件将下载到目录: $DOWNLOAD_DIR" >&2

            local MANIFEST=$(cat "$TEMP_CLEAN_FILE")

            echo "$MANIFEST" | $JQ_CMD -c '.[]' | while IFS= read -r ITEM_JSON; do
                local FILE_URL=$(echo "$ITEM_JSON" | $JQ_CMD -r '.url')
                local RELATIVE_PATH=$(echo "$ITEM_JSON" | $JQ_CMD -r '.relative_path // .filename')

                local TARGET_FILE="$DOWNLOAD_DIR/$RELATIVE_PATH"

                mkdir -p "$(dirname "$TARGET_FILE")"

                echo "---" >&2
                echo "⬇️ 正在下载: $RELATIVE_PATH" >&2
                echo "   URL: $FILE_URL" >&2

                wget --content-disposition -q "$FILE_URL" -O "$TARGET_FILE" 2>&1 | grep -v '已保存' || true

                if [ $? -eq 0 ]; then
                    echo "✅ 下载成功：$TARGET_FILE" >&2
                else
                    echo "❌ 下载失败：$FILE_URL" >&2
                fi
            done

            rm "$TEMP_CLEAN_FILE"

            echo "---" >&2
            echo "🎉 批量下载完成！" >&2

        else
            # 单文件下载

            echo "---" >&2
            echo "📄 模式: 检测到单个文件 URL，将执行直接下载。" >&2

            rm "$TEMP_CLEAN_FILE"

            wget --content-disposition -P . "$DOWNLOAD_URL"

            if [ $? -eq 0 ]; then
                echo "✅ 下载成功！文件已保存到当前目录。" >&2
            else
                echo "❌ 下载失败：$DOWNLOAD_URL" >&2
            fi
        fi

    # ===============================================
    # 2. 模式判断：文件或文件夹 (上传)
    # ===============================================
    elif [ -e "$TARGET" ]; then
        local TARGET_PATH="$TARGET"

        # 内层判断：文件 vs 文件夹
        if [ -f "$TARGET_PATH" ]; then
            # 模式 1: 上传单个文件
            echo "📤 模式: 上传单个文件 -> $TARGET_PATH"

            local RESULT_JSON=$(upload_file "$TARGET_PATH" "")
            local FILE_URL=$(echo "$RESULT_JSON" | $JQ_CMD -r '.url' 2>/dev/null)

            if [[ "$FILE_URL" == https://* ]]; then
                echo "✅ 上传成功！"
                echo -e "${BLUE}$FILE_URL${RESET}"
            else
                echo "❌ 上传失败。请检查上方错误信息。" >&2
            fi

        elif [ -d "$TARGET_PATH" ]; then
            # 模式 2: 递归上传文件夹
            echo "📤 模式: 递归上传文件夹 -> $TARGET_PATH"

            local BASE_DIR=$(echo "$TARGET_PATH" | sed 's/\/$//')
            local TEMP_JSON_FRAGMENTS=$(mktemp)

            echo "📢 开始遍历并上传文件..." >&2

            find "$BASE_DIR" -type f -print0 | while IFS= read -r -d $'\0' FILE_PATH; do
                local RELATIVE_PATH="${FILE_PATH#$BASE_DIR/}"
                local UPLOAD_ITEM=$(upload_file "$FILE_PATH" "$RELATIVE_PATH")

                if [ -n "$UPLOAD_ITEM" ]; then
                    printf "%s\n" "$UPLOAD_ITEM" >> "$TEMP_JSON_FRAGMENTS"
                fi
            done

            # --- 组合 JSON 结果 ---
            local LOCAL_JSON_FILE="upload_results_$(date +%Y%m%d_%H%M%S).json"
            local FINAL_JSON=$(cat "$TEMP_JSON_FRAGMENTS" | $JQ_CMD -s '.')

            if [ -n "$FINAL_JSON" ] && [ "$FINAL_JSON" != "null" ]; then
                echo "$FINAL_JSON" > "$LOCAL_JSON_FILE"
                echo "💾 所有上传结果已保存至本地文件: $LOCAL_JSON_FILE"
            else
                echo "❌ 错误：没有成功上传任何文件，未生成结果 JSON 文件。" >&2
                rm "$TEMP_JSON_FRAGMENTS"
                return 1
            fi

            rm "$TEMP_JSON_FRAGMENTS"

            # --- 上传结果 JSON 文件 ---
            echo "---"
            echo "📤 正在上传结果 JSON 文件: $LOCAL_JSON_FILE"

            local JSON_UPLOAD_RESULT=$(upload_file "$LOCAL_JSON_FILE" "$LOCAL_JSON_FILE")

            if [ -z "$JSON_UPLOAD_RESULT" ]; then
                echo "❌ JSON 文件上传失败。请检查上方错误信息。" >&2
                return 1
            fi

            local JSON_UPLOAD_URL=$(echo "$JSON_UPLOAD_RESULT" | $JQ_CMD -r '.url' | tr -d '[:space:][:cntrl:]')

            if [[ "$JSON_UPLOAD_URL" == https://* ]]; then
                echo "✅ JSON 清单上传流程完成！"
                echo -e "\n${BLUE}$JSON_UPLOAD_URL${RESET}\n"
            else
                echo "❌ JSON 文件上传失败。无法从服务器响应中提取有效 URL。" >&2
                echo "   服务器返回的 JSON: $JSON_UPLOAD_RESULT" >&2
            fi

        # 错误：TARGET 存在，但既不是文件也不是文件夹
        else
            echo "🚨 错误：'$TARGET' 存在，但既不是文件也不是文件夹（例如，套接字或设备）。" >&2
            return 1
        fi

    # ===============================================
    # 3. 模式判断：都不是 (错误)
    # ===============================================
    else
        echo "🚨 错误：'$TARGET' 既不是有效的 URL，也不是存在的文件或文件夹。" >&2
        return 1
    fi
}

# 运行主函数，并将所有命令行参数传递给它
main "$@"