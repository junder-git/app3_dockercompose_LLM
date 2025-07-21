-- =============================================================================
-- nginx/lua/manage_adapter_ollama_streaming.lua - Simple Ollama adapter
-- =============================================================================

local cjson = require "cjson"
local http = require "resty.http"

local M = {}

-- Get environment variables (no defaults - must be in .env)
local MODEL_URL = os.getenv("MODEL_URL")
local MODEL_NAME = os.getenv("MODEL_NAME")
local MODEL_TEMPERATURE = tonumber(os.getenv("MODEL_TEMPERATURE"))
local MODEL_TOP_P = tonumber(os.getenv("MODEL_TOP_P"))
local MODEL_TOP_K = tonumber(os.getenv("MODEL_TOP_K"))
local MODEL_NUM_CTX = tonumber(os.getenv("MODEL_NUM_CTX"))
local MODEL_NUM_PREDICT = tonumber(os.getenv("MODEL_NUM_PREDICT"))
local MODEL_REPEAT_PENALTY = tonumber(os.getenv("MODEL_REPEAT_PENALTY"))
local MODEL_REPEAT_LAST_N = tonumber(os.getenv("MODEL_REPEAT_LAST_N"))
local MODEL_SEED = tonumber(os.getenv("MODEL_SEED"))
local OLLAMA_GPU_LAYERS = tonumber(os.getenv("OLLAMA_GPU_LAYERS"))

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

-- Main Ollama streaming function
function M.call_ollama_streaming(messages, options, callback)
    ngx.log(ngx.INFO, "call_ollama_streaming(): Using Ollama adapter for streaming")
    
    local httpc = http.new()
    httpc:set_timeout(600000) -- 10 minute timeout
    
    -- Parse URL
    local url_parts = parse_url(MODEL_URL)
    
    -- Format messages for Ollama
    local formatted_messages = M.format_messages(messages)
    
    -- Build Ollama API request with env parameters
    local request_data = {
        model = MODEL_NAME,
        messages = formatted_messages,
        stream = true,
        options = {
            temperature = options.temperature or MODEL_TEMPERATURE,
            top_p = options.top_p or MODEL_TOP_P,
            top_k = options.top_k or MODEL_TOP_K,
            num_predict = options.num_predict or options.max_tokens or MODEL_NUM_PREDICT,
            num_ctx = options.num_ctx or MODEL_NUM_CTX,
            repeat_penalty = options.repeat_penalty or MODEL_REPEAT_PENALTY,
            repeat_last_n = options.repeat_last_n or MODEL_REPEAT_LAST_N,
            seed = options.seed or MODEL_SEED,
            mmap = false,
            num_gpu = OLLAMA_GPU_LAYERS,
            num_thread = 4
        }
    }
    
    ngx.log(ngx.DEBUG, "Ollama request data: " .. cjson.encode(request_data))
    
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