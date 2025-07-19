-- =============================================================================
-- nginx/lua/manage_adapter_vllm_streaming.lua - Complete adapter for vLLM API
-- =============================================================================

local cjson = require "cjson"
local http = require "resty.http"

local M = {}

-- Get environment variables with fallbacks
local VLLM_URL = os.getenv("VLLM_URL") or "http://vllm:8000"
local VLLM_MODEL = os.getenv("VLLM_MODEL") or "devstral"

-- Default system prompt for Devstral (fallback if not loading from file)
local SYSTEM_PROMPT = [[You are Devstral, a helpful AI programming assistant.
- Provide accurate, helpful responses about programming topics
- Write clean, well-documented code
- Prioritize readability and best practices in all code examples
- Explain technical concepts clearly and concisely
- If you're unsure, acknowledge it instead of providing incorrect information
]]

-- Try to load system prompt from model
local function try_load_system_prompt()
    local system_prompt_path = "/models/devstral/SYSTEM_PROMPT.txt"
    local file = io.open(system_prompt_path, "r")
    if file then
        local content = file:read("*all")
        file:close()
        if content and #content > 0 then
            ngx.log(ngx.INFO, "Loaded system prompt from file, length: " .. #content)
            return content
        end
    end
    
    -- If loading fails, use default
    ngx.log(ngx.WARN, "Could not load system prompt from file, using default")
    return SYSTEM_PROMPT
end

-- Try to load the system prompt on module load
SYSTEM_PROMPT = try_load_system_prompt()

-- Configure default parameters - FIXED: Reduced max_tokens
local DEFAULT_PARAMS = {
    temperature = 0.7,
    top_p = 0.9,
    top_k = 40,
    max_tokens = 512  -- FIXED: Reduced from 1024 to fit in 2048 context
}

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

-- Call the vLLM API
function M.call_vllm_api(messages, options)
    local httpc = http.new()
    httpc:set_timeout(600000) -- 10 minute timeout
    
    -- Parse URL
    local url_parts = parse_url(VLLM_URL)
    
    ngx.log(ngx.INFO, "Calling vLLM API at " .. VLLM_URL .. " with model " .. VLLM_MODEL)
    
    -- Ensure system message is present
    local has_system = false
    for _, msg in ipairs(messages or {}) do
        if msg.role == "system" then
            has_system = true
            break
        end
    end
    
    if not has_system then
        table.insert(messages, 1, {
            role = "system",
            content = SYSTEM_PROMPT
        })
    end
    
    -- Build vLLM API request
    local request_data = {
        model = VLLM_MODEL,
        messages = messages,
        stream = options.stream or false
    }
    
    -- Add model parameters from options or defaults
    for k, v in pairs(DEFAULT_PARAMS) do
        if options[k] ~= nil then
            request_data[k] = options[k]
        else
            request_data[k] = v
        end
    end
    
    ngx.log(ngx.DEBUG, "vLLM request data: " .. cjson.encode(request_data))
    
    -- Connect to vLLM
    local ok, err = httpc:connect(url_parts.host, url_parts.port)
    if not ok then
        ngx.log(ngx.ERR, "Failed to connect to vLLM: " .. tostring(err))
        return {
            success = false,
            error = "Failed to connect to vLLM: " .. tostring(err)
        }
    end
    
    -- Make the API request
    local res, err = httpc:request({
        path = "/v1/chat/completions",
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json"
        },
        body = cjson.encode(request_data)
    })
    
    if not res then
        ngx.log(ngx.ERR, "Failed to request vLLM: " .. tostring(err))
        return {
            success = false,
            error = "Failed to request vLLM: " .. tostring(err)
        }
    end
    
    -- Handle response based on streaming mode
    if not options.stream then
        -- Non-streaming response handling
        local body, err = res:read_body()
        httpc:close()
        
        if not body then
            ngx.log(ngx.ERR, "Failed to read vLLM response: " .. tostring(err))
            return {
                success = false,
                error = "Failed to read vLLM response: " .. tostring(err)
            }
        end
        
        local ok, data = pcall(cjson.decode, body)
        if not ok then
            ngx.log(ngx.ERR, "Failed to parse vLLM response: " .. tostring(data))
            return {
                success = false,
                error = "Failed to parse vLLM response"
            }
        end
        
        -- Extract text from OpenAI response format
        if data.choices and data.choices[1] and data.choices[1].message then
            return {
                success = true,
                content = data.choices[1].message.content,
                raw_response = data
            }
        else
            ngx.log(ngx.ERR, "Unexpected vLLM response format: " .. body)
            return {
                success = false,
                error = "Unexpected vLLM response format",
                raw_response = data
            }
        end
    else
        -- Return the response object for streaming
        return {
            success = true,
            response = res,
            http_client = httpc
        }
    end
end

-- COMPLETELY REWRITTEN: Handle streaming response for SSE output
function M.stream_to_sse(response, http_client)
    -- Send connecting event
    ngx.print("data: " .. cjson.encode({
        type = "connecting",
        message = "Connecting to AI model...",
        model = VLLM_MODEL
    }) .. "\n\n")
    ngx.flush(true)
    
    -- Send initial start event
    ngx.print("data: " .. cjson.encode({
        type = "start",
        message = "Stream started",
        timestamp = ngx.time()
    }) .. "\n\n")
    ngx.flush(true)
    
    -- Set up variables for streaming
    local reader = response.body_reader
    local accumulated = ""
    local chunk_count = 0
    local buffer = ""
    local stream_started = false
    
    ngx.log(ngx.INFO, "Starting vLLM stream processing")
    
    while true do
        -- Read next chunk from vLLM
        local chunk, read_err = reader()
        
        if read_err then
            ngx.log(ngx.ERR, "Error reading vLLM stream: " .. tostring(read_err))
            ngx.print("data: " .. cjson.encode({
                type = "error",
                error = "Error reading stream: " .. tostring(read_err),
                done = true
            }) .. "\n\n")
            ngx.print("data: [DONE]\n\n")
            ngx.flush(true)
            break
        end
        
        if not chunk then
            -- End of stream from vLLM
            ngx.log(ngx.INFO, "vLLM stream ended, accumulated: " .. tostring(#accumulated) .. " chars")
            ngx.print("data: " .. cjson.encode({
                type = "complete",
                final_content = accumulated,
                total_chunks = chunk_count
            }) .. "\n\n")
            ngx.print("data: [DONE]\n\n")
            ngx.flush(true)
            break
        end
        
        -- Add chunk to buffer
        buffer = buffer .. chunk
        
        -- Process complete lines (split by \n)
        while true do
            local newline_pos = buffer:find("\n")
            if not newline_pos then break end
            
            local line = buffer:sub(1, newline_pos - 1):gsub("^%s+", ""):gsub("%s+$", "")
            buffer = buffer:sub(newline_pos + 1)
            
            if line == "" then
                -- Skip empty lines
                goto continue_line
            end
            
            ngx.log(ngx.DEBUG, "Processing vLLM line: " .. line)
            
            -- Handle SSE data lines
            if line:sub(1, 6) == "data: " then
                local data_part = line:sub(7)
                
                -- Check for completion marker
                if data_part == "[DONE]" then
                    ngx.log(ngx.INFO, "Received [DONE] from vLLM")
                    ngx.print("data: " .. cjson.encode({
                        type = "complete",
                        final_content = accumulated,
                        total_chunks = chunk_count
                    }) .. "\n\n")
                    ngx.print("data: [DONE]\n\n")
                    ngx.flush(true)
                    goto stream_end
                end
                
                -- Try to parse JSON data
                local ok, data = pcall(cjson.decode, data_part)
                if ok and data.choices and data.choices[1] then
                    local choice = data.choices[1]
                    
                    -- Handle delta content (streaming format)
                    if choice.delta then
                        if choice.delta.role and not stream_started then
                            stream_started = true
                            ngx.log(ngx.INFO, "Stream role detected: " .. choice.delta.role)
                        end
                        
                        if choice.delta.content and choice.delta.content ~= "" then
                            chunk_count = chunk_count + 1
                            accumulated = accumulated .. choice.delta.content
                            
                            ngx.log(ngx.DEBUG, "Content chunk " .. chunk_count .. ": " .. choice.delta.content)
                            
                            -- Send content event to browser
                            ngx.print("data: " .. cjson.encode({
                                type = "content",
                                content = choice.delta.content
                            }) .. "\n\n")
                            ngx.flush(true)
                        end
                        
                        -- Check for completion
                        if choice.finish_reason then
                            ngx.log(ngx.INFO, "Stream completed with reason: " .. choice.finish_reason)
                            ngx.print("data: " .. cjson.encode({
                                type = "complete",
                                final_content = accumulated,
                                total_chunks = chunk_count
                            }) .. "\n\n")
                            ngx.print("data: [DONE]\n\n")
                            ngx.flush(true)
                            goto stream_end
                        end
                    end
                    
                    -- Handle message content (non-streaming format fallback)
                    if choice.message and choice.message.content then
                        accumulated = choice.message.content
                        chunk_count = 1
                        
                        ngx.print("data: " .. cjson.encode({
                            type = "content",
                            content = choice.message.content
                        }) .. "\n\n")
                        ngx.flush(true)
                        
                        ngx.print("data: " .. cjson.encode({
                            type = "complete",
                            final_content = accumulated,
                            total_chunks = chunk_count
                        }) .. "\n\n")
                        ngx.print("data: [DONE]\n\n")
                        ngx.flush(true)
                        goto stream_end
                    end
                else
                    if not ok then
                        ngx.log(ngx.WARN, "Failed to parse vLLM JSON: " .. tostring(data))
                    end
                end
            end
            
            ::continue_line::
        end
    end
    
    ::stream_end::
    
    ngx.log(ngx.INFO, "vLLM stream completed. Total chunks: " .. chunk_count .. ", Total content: " .. #accumulated .. " chars")
    
    -- Close the HTTP client
    if http_client then
        http_client:close()
    end
end

-- Format our internal messages to the vLLM format
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
                content = msg.content
            })
        elseif msg.role == "ai" then
            -- Map 'ai' role to 'assistant'
            table.insert(formatted, {
                role = "assistant",
                content = msg.content
            })
        end
    end
    
    return formatted
end

return M