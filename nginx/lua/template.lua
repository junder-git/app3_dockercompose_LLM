-- =============================================================================
-- nginx/lua/template.lua - UNIFIED TEMPLATE RENDERING WITH SMART CONTEXT
-- =============================================================================

-- Helper function to read a file and return its content
local function read_file(path)
    local file = io.open(path, "r")
    if not file then
        return "<!-- File not found: " .. path .. " -->"
    end
    local content = file:read("*a")
    file:close()
    return content
end

-- Process template content with variable replacement and smart context handling
local function process_template_content(content, context, depth)
    if not context then
        context = {}
    end
    
    depth = depth or 2
    
    -- First pass: process context values (check for partials)
    local processed_context = {}
    for key, value in pairs(context) do
        if type(value) == "string" and string.match(value, "%.html$") then
            -- This looks like a file path - read it as a partial
            processed_context[key] = read_file(value)
        else
            -- Regular value - use as-is
            processed_context[key] = value
        end
    end
    
    -- Replace template variables with processed context
    for i = 1, depth do
        for key, value in pairs(processed_context) do
            if value then
                content = content:gsub("{{%s*" .. key .. "%s*}}", tostring(value))
            else
                content = content:gsub("{{%s*" .. key .. "%s*}}", "")
            end
        end
    end
    
    return content
end

-- UNIFIED render_template function with smart context processing
local function render_template(path, context, depth, return_content)
    local content = ""
    local error_occurred = false
    local error_msg = ""
    
    -- Handle multiple paths
    if type(path) == "table" then
        -- Multiple paths - concatenate all template contents
        for _, template_path in ipairs(path) do
            local file = io.open(template_path, "r")
            if not file then
                error_occurred = true
                error_msg = "Template file not found: " .. template_path
                break
            end
            
            local file_content = file:read("*a")
            file:close()
            content = content .. file_content
        end
    else
        -- Single path
        local file = io.open(path, "r")
        if not file then
            error_occurred = true
            error_msg = "Template file not found: " .. path
        else
            content = file:read("*a")
            file:close()
        end
    end
    
    -- Handle errors
    if error_occurred then
        local error_response = "<!-- " .. error_msg .. " -->"
        
        if return_content then
            return error_response
        else
            ngx.status = 500
            ngx.header.content_type = "text/html; charset=utf-8"
            ngx.say(error_msg)
            return ngx.exit(500)
        end
    end
    
    -- Process the template content with smart context handling
    content = process_template_content(content, context, depth)
    
    -- Return content or send response based on return_content parameter
    if return_content then
        return content
    else
        ngx.header.content_type = "text/html; charset=utf-8"
        ngx.say(content)
    end
end

-- Wrap render_template with error handling
local function safe_render_template(path, context, depth, return_content)
    local ok, result = pcall(function()
        return render_template(path, context, depth, return_content)
    end)
    
    if not ok then
        ngx.log(ngx.ERR, "Template rendering failed: " .. tostring(result))
        local error_html = [[
<!DOCTYPE html>
<html>
<head>
    <title>Error</title>
    <style>body{font-family:Arial,sans-serif;background:#1a1a1a;color:#fff;padding:20px}</style>
</head>
<body>
    <h1>Template Error</h1>
    <p>Failed to render template: ]] .. tostring(path) .. [[</p>
    <p>Error: ]] .. tostring(result) .. [[</p>
</body>
</html>
        ]]
        
        if return_content then
            return error_html
        else
            ngx.status = 500
            ngx.header.content_type = "text/html; charset=utf-8"
            ngx.say(error_html)
            ngx.exit(500)
        end
    end
    
    return result
end

-- Create final unified render_template that merges safe rendering with smart context
local function unified_render_template(path, context, depth, return_content)
    return safe_render_template(path, context, depth, return_content)
end

return {
    render_template = unified_render_template,
    read_file = read_file
}