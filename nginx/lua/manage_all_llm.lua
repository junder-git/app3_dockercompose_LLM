-- =============================================================================
-- nginx/lua/manage_all_llm.lua - vLLM streaming functions
-- =============================================================================

local cjson = require "cjson"
local vllm_adapter = require "manage_adapter_vllm_streaming"
local sse_manager = require "manage_sse"
local user_manager = require "manage_users"

local M = {}

-- Common function to handle chat streaming
function M.handle_chat_stream_common(stream_context)
    local function send_json(status, tbl)
        ngx.status = status
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode(tbl))
        ngx.exit(status)
    end

    -- Get and validate request body
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body then
        send_json(400, { error = "No request body" })
    end

    local ok, request_data = pcall(cjson.decode, body)
    if not ok or type(request_data) ~= "table" then
        send_json(400, { error = "Invalid JSON" })
    end

    local message = request_data.message
    if not message or message == "" then
        send_json(400, { error = "Message is required" })
    end

    -- Run pre-check (rate limiting, etc.)
    if stream_context.pre_stream_check then
        local check_ok, check_error = stream_context.pre_stream_check(message, request_data)
        if not check_ok then
            send_json(429, { error = check_error })
        end
    end

    -- Set SSE headers
    sse_manager.setup_sse_response()

    -- Initial SSE signal
    sse_manager.sse_send({
        type = "start",
        message = "Stream started",
        timestamp = ngx.time()
    })

    -- Prepare messages
    local messages = {}

    -- Load chat history if requested
    if stream_context.include_history and request_data.include_history then
        local history = stream_context.get_history(stream_context.history_limit or 10)
        for _, msg in ipairs(history) do
            table.insert(messages, { role = msg.role, content = msg.content })
        end
    end

    -- Add current message
    table.insert(messages, { role = "user", content = message })

    -- Save user message if storage function provided
    if stream_context.save_user_message then
        stream_context.save_user_message(message)
    end

    -- Merge options with defaults
    local options = request_data.options or {}
    if stream_context.default_options then
        for k, v in pairs(stream_context.default_options) do
            if options[k] == nil then
                options[k] = v
            end
        end
    end

    -- Announce connection
    sse_manager.sse_send({
        type = "connecting",
        message = "Connecting to AI model...",
        model = options.model or stream_context.default_options.model or "Devstral"
    })

    local accumulated_response = ""
    
    -- Convert messages to vLLM format and enable streaming
    options.stream = true
    local formatted_messages = vllm_adapter.format_messages(messages)
    
    -- Call vLLM API
    local result = vllm_adapter.call_vllm_api(formatted_messages, options)
    
    if result.success then
        -- Use the adapter's streaming function
        vllm_adapter.stream_to_sse(result.response, result.http_client)
        
        -- The final accumulated response is captured from the streaming process
        -- Try to get it from the stream completion event
        if stream_context.save_ai_response then
            stream_context.save_ai_response(accumulated_response)
        end
    else
        -- Error handling
        sse_manager.sse_send({
            type = "error",
            error = result.error or "AI service unavailable",
            content = "*Error: " .. (result.error or "AI service unavailable") .. "*",
            done = true
        })
        ngx.print("data: [DONE]\n\n")
        ngx.flush(true)
    end

    -- Run post-stream cleanup
    if stream_context.post_stream_cleanup then
        stream_context.post_stream_cleanup(accumulated_response)
    end

    ngx.exit(200)
end

-- Legacy compatibility function (renamed from call_ollama_streaming)
function M.call_vllm_streaming(messages, options, callback)
    ngx.log(ngx.INFO, "call_vllm_streaming(): Using vLLM adapter for streaming")
    
    -- Format messages for vLLM
    local formatted_messages = vllm_adapter.format_messages(messages)
    
    -- Call vLLM API
    local result = vllm_adapter.call_vllm_api(formatted_messages, {
        stream = true,
        temperature = options.temperature,
        top_p = options.top_p,
        top_k = options.top_k,
        max_tokens = options.max_tokens or options.num_predict
    })
    
    if not result.success then
        return false, result.error
    end
    
    -- Process the streaming response
    local reader = result.response.body_reader
    local buffer = ""
    
    while true do
        local chunk, read_err = reader()
        if read_err then
            ngx.log(ngx.ERR, "Error reading vLLM stream: " .. tostring(read_err))
            return false, "Error reading response: " .. read_err
        end
        
        if not chunk then break end
        buffer = buffer .. chunk
        
        while true do
            local newline_pos = buffer:find("\n")
            if not newline_pos then break end
            
            local line = buffer:sub(1, newline_pos - 1)
            buffer = buffer:sub(newline_pos + 1)
            
            if line and line:match("%S") then
                -- Remove "data: " prefix if present
                if line:sub(1, 6) == "data: " then
                    line = line:sub(7)
                end
                
                if line == "[DONE]" then
                    result.http_client:close()
                    return true
                end
                
                local ok, data = pcall(cjson.decode, line)
                if ok and type(data) == "table" then
                    local content = ""
                    local done = false
                    
                    if data.choices and data.choices[1] then
                        local choice = data.choices[1]
                        
                        if choice.delta and choice.delta.content then
                            content = choice.delta.content
                        elseif choice.message and choice.message.content then
                            content = choice.message.content
                        end
                        
                        done = choice.finish_reason ~= nil
                    end
                    
                    -- Call callback with content
                    local callback_ok, cb_err = pcall(callback, {
                        content = content,
                        done = done
                    })
                    
                    if not callback_ok then
                        ngx.log(ngx.ERR, "Callback error: ", cb_err)
                        result.http_client:close()
                        return false, "Streaming callback failed"
                    end
                    
                    if done then
                        ngx.log(ngx.INFO, "vLLM streaming complete.")
                        result.http_client:close()
                        return true
                    end
                end
            end
        end
    end
    
    result.http_client:close()
    return true
end

return M