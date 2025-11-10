#!/bin/bash

# --- 配置 ---
UPLOAD_API="https://www.dlink666.com/api/upload"
TEMP_RESULT_FILE="upload_results.json"
MAX_RETRIES=5 # 最大重试次数
JQ_CMD=$(command -v jq 2>/dev/null)
JQ_EXIT_CODE=$?

# 检查 jq 是否安装
if [ $JQ_EXIT_CODE -ne 0 ]; then
    echo "🚨 错误：未找到 'jq'。请安装 'jq' 以处理 JSON 数据。" >&2
    echo "在 Debian/Ubuntu 上: sudo apt install jq" >&2
    exit 1
fi

# ANSI 颜色代码
BLUE='\e[34m'
RED='\e[31m'
GREEN='\e[32m'
RESET='\e[0m'

# ----------------------------------------------------------------------
# --- 上传函数 (带重试逻辑) ---
# ----------------------------------------------------------------------
# 参数:
# $1: 文件路径
# $2: 相对路径 (用于提示)
# 返回: 成功返回 JSON 片段到 STDOUT，失败返回空字符串
upload_file() {
    local file_path="$1"
    local relative_path="$2"
    local file_name=$(basename "$file_path")
    local full_url="${UPLOAD_API}?name=${file_name}"
    local TEMP_CURL_RESPONSE=$(mktemp)
    local attempt=1
    local delay=2 # 初始延迟 2 秒
    local uploaded_url=""
    local json_item=""
    local response=""

    # 获取文件大小作为上传前的提示
    local FILE_SIZE=$(du -h "$file_path" 2>/dev/null | awk '{print $1}')
    if [ -z "$FILE_SIZE" ]; then
        FILE_SIZE="N/A"
    fi

    echo "  -> [开始] 上传文件: $relative_path" >&2
    echo "   [大小]: $FILE_SIZE" >&2

    while [ $attempt -le $MAX_RETRIES ]; do
        echo "   [尝试]: 第 $attempt/$MAX_RETRIES 次..." >&2

        # 执行上传：将服务器响应 STDOUT 干净地重定向到临时文件。
        curl -T "$file_path" "$full_url" -o "$TEMP_CURL_RESPONSE"
        local exit_code=$?
        response=$(cat "$TEMP_CURL_RESPONSE")
        rm "$TEMP_CURL_RESPONSE" # 立即清理临时文件

        if [ $exit_code -eq 0 ]; then
            uploaded_url=$(echo "$response" | tr -d '[:space:][:cntrl:]')

            if [[ "$uploaded_url" == https://* ]]; then
                echo -e "  ${GREEN}✅ [成功]${RESET} URL: $uploaded_url" >&2

                # 构造 JSON 对象并返回
                json_item="{
                    \"absolute_path\": \"$file_path\",
                    \"relative_path\": \"$relative_path\",
                    \"filename\": \"$file_name\",
                    \"url\": \"$uploaded_url\"
                }"
                printf "%s" "$json_item"
                return 0 # 成功上传，退出函数
            fi
        fi

        # 失败处理或 URL 提取失败
        if [ $attempt -lt $MAX_RETRIES ]; then
            echo -e "  ${RED}❌ [失败]${RESET} 服务器响应异常/curl 退出码 $exit_code。" >&2
            echo "    返回内容: $response" >&2
            echo "   [等待]: $delay 秒后重试..." >&2
            sleep "$delay"
            delay=$((delay * 2)) # 指数退避
            attempt=$((attempt + 1))
        else
            echo -e "  ${RED}❌ [失败]${RESET} 重试 $MAX_RETRIES 次后仍然失败。跳过此文件。" >&2
            echo "    最后返回内容: $response" >&2
            return 1 # 最终失败，返回非零退出码
        fi
    done
    return 1 # 应该永远不会到达这里，但以防万一
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
    # 1. 模式判断：URL (下载) - (保持不变)
    # ===============================================
    if [[ "$TARGET" =~ ^https?:// ]]; then
        # ... (下载逻辑保持 V2.4 不变，此处省略) ...
        local DOWNLOAD_URL="$TARGET"
        local TEMP_CLEAN_FILE=$(mktemp)
        local IS_LIKELY_JSON="false"
        local IS_TEXT_CONTENT="false"

        echo "📥 正在检查 URL 类型: $DOWNLOAD_URL" >&2

        # 1. HEAD 请求获取 Header
        local HEADERS=$(curl -sI "$DOWNLOAD_URL")
        local EXIT_CODE=$?

        if [ $EXIT_CODE -ne 0 ]; then
            echo "❌ 错误：无法访问 URL ($EXIT_CODE)。请检查网络或 URL 是否有效。" >&2
            return 1
        fi

        # 2. 从 Header 中提取 Content-Type 和 Content-Disposition
        local CONTENT_TYPE=$(echo "$HEADERS" | grep -i '^Content-Type:' | awk '{print $2}' | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
        local CONTENT_DISPO=$(echo "$HEADERS" | grep -i '^Content-Disposition:' | grep -o 'filename="[^"]*"' | sed 's/filename="//;s/"$//' | tr -d '\r')

        # 3. 基于 Content-Type 进行严格文本判断
        case "$CONTENT_TYPE" in
            application/json | text/* | application/xml)
                IS_TEXT_CONTENT="true"
                ;;
            *)
                IS_TEXT_CONTENT="false"
                ;;
        esac

        # 4. 基于 Content-Type/文件名进行 JSON 预判断
        if [ "$IS_TEXT_CONTENT" == "true" ]; then
            case "$CONTENT_TYPE" in
                application/json)
                    echo "💡 提示：Content-Type 为 JSON，倾向于清单下载。" >&2
                    IS_LIKELY_JSON="true"
                    ;;
            esac

            if [[ "$CONTENT_DISPO" =~ \.json$ ]] || [[ "$DOWNLOAD_URL" =~ \.json(\?|$) ]]; then
                echo "💡 提示：文件名或 URL 包含 .json 后缀，倾向于清单下载。" >&2
                IS_LIKELY_JSON="true"
            fi
        fi

        # 5. --- 执行内容下载和 JSON 检查 ---

        if [ "$IS_TEXT_CONTENT" == "false" ]; then
            echo "---" >&2
            echo "📄 模式: 检测到 Content-Type 为非文本内容 ($CONTENT_TYPE)，将执行直接下载。" >&2
            rm "$TEMP_CLEAN_FILE"
            wget --content-disposition -P . "$DOWNLOAD_URL"
            if [ $? -eq 0 ]; then
                echo "✅ 下载成功！文件已保存到当前目录。" >&2
            else
                echo "❌ 下载失败：$DOWNLOAD_URL" >&2
            fi
            return 0
        fi

        local CONTENT=""
        if [ "$IS_LIKELY_JSON" == "true" ]; then
            echo "⬇️ 尝试下载完整内容进行 JSON 结构检查..." >&2
            CONTENT=$(curl -sL "$DOWNLOAD_URL")
        else
            local RANGE_LIMIT="0-10240"
            echo "⬇️ 倾向于单文件。下载前 ${RANGE_LIMIT} 字节进行结构检查..." >&2
            CONTENT=$(curl -sL -r "$RANGE_LIMIT" "$DOWNLOAD_URL")
        fi

        # 6. 检查下载内容
        local CLEAN_CONTENT=$(echo "$CONTENT" | tr -d '\000' | tr -d '[:cntrl:]' | tr -s '[:space:]' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        printf "%s" "$CLEAN_CONTENT" > "$TEMP_CLEAN_FILE"

        if [ ! -s "$TEMP_CLEAN_FILE" ]; then
            echo "❌ 错误：URL 内容为空或全为空白字符。" >&2
            rm "$TEMP_CLEAN_FILE"
            return 1
        fi

        local IS_VALID_JSON="false"
        local JQ_EXIT_CODE=1

        $JQ_CMD '.' "$TEMP_CLEAN_FILE" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            IS_VALID_JSON="true"
        fi

        if [ "$IS_VALID_JSON" == "true" ]; then
            $JQ_CMD -e '.[].url' "$TEMP_CLEAN_FILE" > /dev/null 2>&1
            if [ $? -eq 0 ]; then
                JQ_EXIT_CODE=0 # 成功：认定为批量下载清单
            else
                JQ_EXIT_CODE=1
            fi
        else
            JQ_EXIT_CODE=1
        fi

        if [ $JQ_EXIT_CODE -eq 0 ]; then
            # 模式 1: 批量下载 (JSON 清单)
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

                # wget 不支持断点续传，不加入重试机制
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
            # 模式 2.2: 单文件下载 (文本内容但非 JSON 结构)
            echo "---" >&2
            echo "📄 模式: 检测到单个文本文件 URL，将执行直接下载。" >&2
            rm "$TEMP_CLEAN_FILE"
            wget --content-disposition -P . "$DOWNLOAD_URL"
            if [ $? -eq 0 ]; then
                echo "✅ 下载成功！文件已保存到当前目录。" >&2
            else
                echo "❌ 下载失败：$DOWNLOAD_URL" >&2
            fi
        fi

    # ===============================================
    # 2. 模式判断：文件或文件夹 (上传) - 【断点续传大改】
    # ===============================================
    elif [ -e "$TARGET" ]; then
        local TARGET_PATH="$TARGET"

        # 内层判断：文件 vs 文件夹
        if [ -f "$TARGET_PATH" ]; then
            # 模式 1: 上传单个文件 (使用带重试的 upload_file)
            echo "📤 模式: 上传单个文件 -> $TARGET_PATH"

            local RESULT_JSON=$(upload_file "$TARGET_PATH" "")
            local FILE_URL=$(echo "$RESULT_JSON" | $JQ_CMD -r '.url' 2>/dev/null)

            if [[ "$FILE_URL" == https://* ]]; then
                echo -e "${GREEN}✅ 上传成功！${RESET}"
                echo -e "${BLUE}$FILE_URL${RESET}"
            else
                echo -e "${RED}❌ 上传失败。${RESET}请检查上方错误信息。" >&2
            fi

        elif [ -d "$TARGET_PATH" ]; then
            # 模式 2: 递归上传文件夹 (支持断点续传)
            echo "📤 模式: 递归上传文件夹 (支持断点续传) -> $TARGET_PATH"

            local BASE_DIR=$(echo "$TARGET_PATH" | sed 's/\/$//')
            local LOCAL_RESULT_FILE="$BASE_DIR/$TEMP_RESULT_FILE"

            # --- 步骤 A: 检查或生成本地清单 ---
            if [ -f "$LOCAL_RESULT_FILE" ]; then
                echo "📢 检测到本地清单文件 '$TEMP_RESULT_FILE'，将尝试断点续传..." >&2
            else
                echo "📢 未检测到本地清单文件，正在生成新的清单..." >&2
                local file_list_array="["
                local first_file="true"
                find "$BASE_DIR" -type f -print0 | while IFS= read -r -d $'\0' FILE_PATH; do
                    if [ "$FILE_PATH" == "$LOCAL_RESULT_FILE" ]; then
                        continue # 跳过清单文件本身
                    fi
                    local RELATIVE_PATH="${FILE_PATH#$BASE_DIR/}"
                    local file_json="{
                        \"absolute_path\": \"$FILE_PATH\",
                        \"relative_path\": \"$RELATIVE_PATH\",
                        \"filename\": \"$(basename "$FILE_PATH")\",
                        \"url\": \"\"
                    }"
                    if [ "$first_file" != "true" ]; then
                        file_list_array+=", "
                    fi
                    file_list_array+="$file_json"
                    first_file="false"
                done
                file_list_array+="]"

                printf "%s" "$file_list_array" | $JQ_CMD '.' > "$LOCAL_RESULT_FILE" 2>/dev/null
                if [ $? -ne 0 ]; then
                     echo "🚨 致命错误：无法生成有效的 JSON 清单。请检查 $BASE_DIR 是否有特殊字符。" >&2
                     return 1
                fi
                echo -e "${GREEN}✅ 清单生成成功：${RESET}$LOCAL_RESULT_FILE" >&2
            fi

            # --- 步骤 B: 遍历清单，执行重试上传和更新 ---
            echo "📢 开始遍历清单，上传未成功的文件..." >&2

            local TOTAL_FILES=$(cat "$LOCAL_RESULT_FILE" | $JQ_CMD 'length')
            local COUNT=0

            # 遍历 JSON 数组，获取每个对象的索引
            cat "$LOCAL_RESULT_FILE" | $JQ_CMD -c '.[].url | select(. == "")' > /dev/null 2>&1 # 检查是否有未上传的文件

            if [ $? -eq 0 ]; then
                 # 遍历所有对象，如果 url 为空则上传
                 for INDEX in $($JQ_CMD 'keys[]' "$LOCAL_RESULT_FILE"); do
                    COUNT=$((COUNT + 1))
                    local ITEM=$(cat "$LOCAL_RESULT_FILE" | $JQ_CMD -r ".[$INDEX]")
                    local URL=$(echo "$ITEM" | $JQ_CMD -r '.url')
                    local ABS_PATH=$(echo "$ITEM" | $JQ_CMD -r '.absolute_path')
                    local REL_PATH=$(echo "$ITEM" | $JQ_CMD -r '.relative_path')

                    if [ -z "$URL" ]; then
                        echo "--- (文件 $COUNT/$TOTAL_FILES) ---" >&2
                        local UPLOAD_RESULT_JSON=$(upload_file "$ABS_PATH" "$REL_PATH")

                        if [ $? -eq 0 ]; then
                            # 上传成功，更新本地 JSON 文件
                            local NEW_URL=$(echo "$UPLOAD_RESULT_JSON" | $JQ_CMD -r '.url')

                            # 使用 jq 批量更新 URL 字段 (直接修改文件)
                            # 这种方法比读取-修改-写入更健壮，但要求 jq 支持 --arg
                            $JQ_CMD ".[$INDEX].url = \"$NEW_URL\"" "$LOCAL_RESULT_FILE" > "$LOCAL_RESULT_FILE.tmp"
                            mv "$LOCAL_RESULT_FILE.tmp" "$LOCAL_RESULT_FILE"
                            echo -e "${GREEN}✅ 清单已更新：${RESET}$REL_PATH URL 字段已记录。" >&2
                        else
                            echo -e "${RED}⚠️ 跳过：${RESET}$REL_PATH 在重试后依然失败。" >&2
                        fi
                    else
                        echo -e "--- (文件 $COUNT/$TOTAL_FILES) ---" >&2
                        echo "✅ 已上传：$REL_PATH" >&2
                    fi
                done
            fi

            # --- 步骤 C: 检查是否全部完成，并上传最终清单 ---

            local REMAINING_UNUPLOADED=$(cat "$LOCAL_RESULT_FILE" | $JQ_CMD -r '[.[] | select(.url == "")] | length')

            echo "---" >&2
            if [ "$REMAINING_UNUPLOADED" -eq 0 ]; then
                echo -e "${GREEN}🎉 所有文件已上传成功！${RESET}" >&2
            else
                echo -e "${RED}⚠️ 仍有 $REMAINING_UNUPLOADED 个文件上传失败或被跳过。${RESET}" >&2
            fi

            echo "📤 正在上传最终结果 JSON 文件: $TEMP_RESULT_FILE"

            # 上传最终的 JSON 文件 (使用带重试的 upload_file)
            local FINAL_JSON_RESULT=$(upload_file "$LOCAL_RESULT_FILE" "$TEMP_RESULT_FILE")

            if [ $? -eq 0 ]; then
                local JSON_UPLOAD_URL=$(echo "$FINAL_JSON_RESULT" | $JQ_CMD -r '.url' | tr -d '[:space:][:cntrl:]')
                echo -e "${GREEN}✅ JSON 清单上传流程完成！${RESET}"
                echo -e "${BLUE}$JSON_UPLOAD_URL${RESET}"
            else
                echo -e "${RED}❌ JSON 文件上传失败。${RESET}请检查上方错误信息。" >&2
                return 1
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

