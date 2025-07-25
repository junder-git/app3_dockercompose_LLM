-- =============================================================================
-- nginx/lua/manage_stream_ollama.lua - COMPLETE ENV VAR INTEGRATION
-- =============================================================================

local cjson = require "cjson"
local http = require "resty.http"

local M = {}

-- Get ALL environment variables (no defaults - must be in .env)
local MODEL_URL = os.getenv("MODEL_URL")
local MODEL_NAME = os.getenv("MODEL_NAME")
local MODEL_GGUF_PATH = os.getenv("MODEL_GGUF_PATH")
local MODEL_TEMPERATURE = tonumber(os.getenv("MODEL_TEMPERATURE"))
local MODEL_TOP_P = tonumber(os.getenv("MODEL_TOP_P"))
local MODEL_TOP_K = tonumber(os.getenv("MODEL_TOP_K"))
local MODEL_MIN_P = tonumber(os.getenv("MODEL_MIN_P"))
local MODEL_NUM_CTX = tonumber(os.getenv("MODEL_NUM_CTX"))
local MODEL_NUM_PREDICT = tonumber(os.getenv("MODEL_NUM_PREDICT"))
local MODEL_REPEAT_PENALTY = tonumber(os.getenv("MODEL_REPEAT_PENALTY"))
local MODEL_REPEAT_LAST_N = tonumber(os.getenv("MODEL_REPEAT_LAST_N"))
local MODEL_SEED = tonumber(os.getenv("MODEL_SEED"))
local OLLAMA_GPU_LAYERS = tonumber(os.getenv("OLLAMA_GPU_LAYERS"))
local OLLAMA_NUM_THREAD = tonumber(os.getenv("OLLAMA_NUM_THREAD"))
local OLLAMA_KEEP_ALIVE = os.getenv("OLLAMA_KEEP_ALIVE")
local OLLAMA_USE_MMAP = os.getenv("OLLAMA_USE_MMAP") == "true"

-- Default system prompt for Devstral
local SYSTEM_PROMPT = [[You are Devstral, a helpful AI programming assistant.
- Provide accurate, helpful responses about programming topics
- Write clean, well-documented code
- Prioritize readability and best practices in all code examples
- Explain technical concepts clearly and concisely
- If you're unsure, acknowledge it instead of providing incorrect information
]]

-- Parse a URL string into its components
local function parse_url(url)
    local result = {}
    
    -- Get scheme (http/https)
    result.scheme = url:match("^([^:]+)://") or "http"
    
    -- Remove scheme from the url
    local remaining = url:gsub("^[^:]+://", "")
    
    -- Get host and port
    result.host, result.port = remaining:match("^([^:/]+):?(%d*)")
    
    -- If port wasn't provided, use default
    if not result.port or result.port == "" then
        if result.scheme == "https" then
            result.port = 443
        else
            result.port = 80
        end
    else
        result.port = tonumber(result.port)
    end
    
    -- Get path
    result.path = remaining:match(":[%d]+(.*)") or remaining:match("/.*") or ""
    if result.path == "" then result.path = "/" end
    
    return result
end

-- Format our internal messages to the Ollama format
function M.format_messages(messages)
    local formatted = {}
    
    -- Ensure we have a system message
    local has_system = false
    for _, msg in ipairs(messages or {}) do
        if msg.role == "system" then
            has_system = true
            break
        end
    end
    
    if not has_system then
        table.insert(formatted, {
            role = "system",
            content = SYSTEM_PROMPT
        })
    end
    
    -- Add all messages with proper format
    for _, msg in ipairs(messages or {}) do
        -- Handle different message formats
        if msg.role == "user" or msg.role == "assistant" or msg.role == "system" then
            table.insert(formatted, {
                role = msg.role,
                content = msg.content or ""
            })
        elseif msg.role == "ai" then
            -- Map 'ai' role to 'assistant'
            table.insert(formatted, {
                role = "assistant",
                content = msg.content or ""
            })
        end
    end
    
    return formatted
end

-- =============================================
-- SHARED CHAT API HANDLER - USED BY ALL USER TYPES
-- =============================================

function M.handle_chat_api(user_type)
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    if uri == "/api/chat/history" and method == "GET" then
        ngx.status = 200
        ngx.header.content_type = 'application/json'
        
        if user_type == "is_guest" then
            ngx.say(cjson.encode({
                success = true,
                messages = {},
                user_type = user_type,
                storage_type = "localStorage",
                note = "Guest users don't have persistent chat history"
            }))
        else
            -- For regular users, could load from Redis/database here
            ngx.say(cjson.encode({
                success = true,
                messages = {},
                user_type = user_type,
                storage_type = "redis",
                note = "Chat history loaded from server"
            }))
        end
        
    elseif uri == "/api/chat/clear" and method == "POST" then
        ngx.status = 200
        ngx.header.content_type = 'application/json'
        
        if user_type == "is_guest" then
            ngx.say(cjson.encode({ 
                success = true, 
                message = "Guest chat uses localStorage only - clear from browser"
            }))
        else
            -- For regular users, could clear Redis/database here
            ngx.say(cjson.encode({ 
                success = true, 
                message = "Chat history cleared from server"
            }))
        end
        
    elseif uri == "/api/chat/stream" and method == "POST" then
        -- Delegate to appropriate streaming handler based on user type
        if user_type == "is_guest" then
            local is_guest = require "is_guest"
            return is_guest.handle_ollama_chat_stream()
        elseif user_type == "is_admin" then
            local is_admin = require "is_admin"
            return is_admin.handle_ollama_chat_stream()
        elseif user_type == "is_approved" then
            local is_approved = require "is_approved"
            return is_approved.handle_ollama_chat_stream()
        else
            ngx.status = 403
            ngx.header.content_type = 'application/json'
            ngx.say(cjson.encode({
                error = "Access denied",
                message = "Invalid user type for chat streaming"
            }))
            return ngx.exit(403)
        end
        
    else
        ngx.status = 404
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({ 
            error = "Chat API endpoint not found",
            requested = method .. " " .. uri,
            user_type = user_type
        }))
        return ngx.exit(404)
    end
end

-- =============================================
-- SHARED CHAT STREAMING HANDLER - EXTENDED TIMEOUT
-- =============================================

function M.handle_chat_stream_common(stream_context)
    ngx.log(ngx.INFO, "🚀 Starting chat stream for user type: " .. (stream_context.user_type or "unknown"))
    
    -- Read request body
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body then
        ngx.status = 400
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({ error = "Request body required" }))
        return ngx.exit(400)
    end
    
    local ok, data = pcall(cjson.decode, body)
    if not ok then
        ngx.status = 400
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({ error = "Invalid JSON" }))
        return ngx.exit(400)
    end
    
    local message = data.message
    if not message or message == "" then
        ngx.status = 400
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({ error = "Message required" }))
        return ngx.exit(400)
    end
    
    -- Run pre-stream checks if provided
    if stream_context.pre_stream_check then
        local check_ok, check_error = stream_context.pre_stream_check(message, data)
        if not check_ok then
            ngx.status = 429
            ngx.header.content_type = 'application/json'
            ngx.say(cjson.encode({
                error = "Stream check failed",
                message = check_error
            }))
            return ngx.exit(429)
        end
    end
    
    -- Set up SSE headers
    ngx.header.content_type = 'text/event-stream; charset=utf-8'
    ngx.header.cache_control = 'no-cache'
    ngx.header.connection = 'keep-alive'
    ngx.header["X-Accel-Buffering"] = "no"
    ngx.flush(true)
    
    -- Build messages for Ollama
    local messages = {}
    
    -- Add chat history if enabled
    if stream_context.include_history and stream_context.history_limit > 0 then
        -- Could load chat history here for regular users
        -- For now, just add the current message
    end
    
    -- Add current user message
    table.insert(messages, {
        role = "user",
        content = message
    })
    
    -- Use stream context options or defaults from env
    local options = {}
    if stream_context.default_options then
        for k, v in pairs(stream_context.default_options) do
            options[k] = data[k] or v
        end
    end
    
    -- Stream callback function - FIXED TO USE CORRECT SSE FORMAT
    local function stream_callback(chunk)
        if chunk.content and chunk.content ~= "" then
            -- Send content as 'type': 'content' for compatibility with frontend
            ngx.print("data: " .. cjson.encode({
                type = "content",
                content = chunk.content,
                done = false
            }) .. "\n\n")
            ngx.flush(true)
        end
        
        if chunk.done then
            -- Send completion signal
            ngx.print("data: " .. cjson.encode({
                type = "complete",
                content = "",
                done = true
            }) .. "\n\n")
            ngx.flush(true)
            return true
        end
        
        return false
    end
    
    -- Call Ollama streaming
    local success, error_msg = M.call_ollama_streaming(messages, options, stream_callback)
    
    if not success then
        ngx.print("data: " .. cjson.encode({
            type = "error",
            error = error_msg or "Unknown streaming error",
            done = true
        }) .. "\n\n")
        ngx.flush(true)
    end
    
    ngx.log(ngx.INFO, "✅ Chat stream completed for " .. (stream_context.user_type or "unknown"))
end

-- =============================================
-- MAIN OLLAMA STREAMING FUNCTION - COMPLETE ENV INTEGRATION
-- =============================================

function M.call_ollama_streaming(messages, options, callback)
    ngx.log(ngx.INFO, "call_ollama_streaming(): Using Ollama adapter for streaming")
    
    local httpc = http.new()
    httpc:set_timeout(600000) -- 10 minute timeout - EXTENDED
    
    -- Parse URL
    local url_parts = parse_url(MODEL_URL)
    
    -- Format messages for Ollama
    local formatted_messages = M.format_messages(messages)
    
    -- Build Ollama API request using your specified payload format
    local request_data = {
        model = MODEL_NAME,
        messages = formatted_messages,
        stream = true,
        keep_alive = OLLAMA_KEEP_ALIVE,
        use_mmap = OLLAMA_USE_MMAP,
        options = {
            -- Modelfile parameters (can be overridden at runtime)
            temperature = options.temperature or MODEL_TEMPERATURE,
            top_p = options.top_p or MODEL_TOP_P,
            top_k = options.top_k or MODEL_TOP_K,
            min_p = options.min_p or MODEL_MIN_P,
            repeat_penalty = options.repeat_penalty or MODEL_REPEAT_PENALTY,
            repeat_last_n = options.repeat_last_n or MODEL_REPEAT_LAST_N,
            num_ctx = options.num_ctx or MODEL_NUM_CTX,
            num_predict = options.num_predict or options.max_tokens or MODEL_NUM_PREDICT,
            seed = options.seed or MODEL_SEED,
            
            -- Runtime-only parameters (not in Modelfile)
            num_gpu = OLLAMA_GPU_LAYERS,
            num_thread = OLLAMA_NUM_THREAD
        }
    }
    
    ngx.log(ngx.INFO, "Ollama request payload: " .. cjson.encode(request_data))
    
    -- Connect to Ollama
    local ok, err = httpc:connect(url_parts.host, url_parts.port)
    if not ok then
        ngx.log(ngx.ERR, "Failed to connect to Ollama: " .. tostring(err))
        return false, "Failed to connect to Ollama: " .. tostring(err)
    end
    
    -- Make the API request
    local res, err = httpc:request({
        path = "/api/chat",
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json"
        },
        body = cjson.encode(request_data)
    })
    
    if not res then
        ngx.log(ngx.ERR, "Failed to request Ollama: " .. tostring(err))
        httpc:close()
        return false, "Failed to request Ollama: " .. tostring(err)
    end
    
    -- Check for HTTP errors
    if res.status >= 400 then
        local body, _ = res:read_body()
        httpc:close()
        ngx.log(ngx.ERR, "Ollama HTTP error " .. res.status .. ": " .. tostring(body))
        return false, "Ollama HTTP error " .. res.status
    end
    
    -- Process the streaming response
    local reader = res.body_reader
    local buffer = ""
    
    while true do
        local chunk, read_err = reader()
        if read_err then
            ngx.log(ngx.ERR, "Error reading Ollama stream: " .. tostring(read_err))
            httpc:close()
            return false, "Error reading response: " .. read_err
        end
        
        if not chunk then 
            break 
        end
        
        buffer = buffer .. chunk
        
        -- Process each line as JSON (Ollama format)
        for line in buffer:gmatch("[^\r\n]+") do
            if line and line ~= "" then
                local ok, data = pcall(cjson.decode, line)
                if ok and type(data) == "table" then
                    local content = ""
                    local done = false
                    
                    if data.message and data.message.content then
                        content = data.message.content
                    end
                    
                    done = data.done or false
                    
                    -- Call callback with content
                    local callback_ok, cb_err = pcall(callback, {
                        content = content,
                        done = done
                    })
                    
                    if not callback_ok then
                        ngx.log(ngx.ERR, "Callback error: ", cb_err)
                        httpc:close()
                        return false, "Streaming callback failed"
                    end
                    
                    if done then
                        ngx.log(ngx.INFO, "Ollama streaming complete.")
                        httpc:close()
                        return true
                    end
                    
                    -- Handle errors
                    if data.error then
                        ngx.log(ngx.ERR, "Ollama API error: " .. tostring(data.error))
                        httpc:close()
                        return false, "API error: " .. tostring(data.error)
                    end
                end
            end
        end
        
        -- Remove processed lines from buffer
        buffer = buffer:gsub("[^\r\n]*[\r\n]", "")
    end
    
    httpc:close()
    return true
end

return M