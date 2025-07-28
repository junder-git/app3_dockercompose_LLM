-- =============================================================================
-- nginx/lua/manage_template.lua - JS CACHE WITH is_shared_chat.js SUPPORT
-- =============================================================================

-- Configuration
local TEMPLATE_CACHE = {}
local JS_CACHE = {}
local CACHE_INITIALIZED = false

-- FIXED: Use the correct JS path from Dockerfile
local JS_BASE_PATH = "/usr/local/openresty/nginx/dynamic_content/js/"

-- =============================================
-- CACHE INITIALIZATION - LOADS ALL JS AT STARTUP INCLUDING NEW CHAT FILE
-- =============================================

local function load_js_assets()
    local js_files = {
        "is_shared.js",         -- Core shared functionality (non-chat)
        "is_shared_sse.js",     -- NEW: Server-Sent Events management
        "is_shared_code.js",    -- NEW: Code artifact management
        "is_shared_chat.js",    -- Chat functionality (depends on SSE and Code)
        "is_admin.js",          -- Admin-specific functionality
        "is_approved.js",       -- Approved user functionality
        "is_guest.js",          -- Guest user functionality
        "is_none.js",           -- Anonymous user functionality
        "is_pending.js"         -- Pending user functionality
    }
    
    ngx.log(ngx.INFO, "Loading JavaScript files into permanent cache...")
    
    for _, filename in ipairs(js_files) do
        local filepath = JS_BASE_PATH .. filename
        local file = io.open(filepath, "r")
        
        if file then
            local content = file:read("*all")
            file:close()
            JS_CACHE[filename] = content
            ngx.log(ngx.INFO, "✅ Loaded JS: " .. filename .. " (" .. string.len(content) .. " bytes)")
        else
            ngx.log(ngx.WARN, "❌ JS file not found: " .. filepath)
            JS_CACHE[filename] = "" -- Store empty string to avoid repeated file system checks
        end
    end
end

local function initialize_cache()
    if CACHE_INITIALIZED then
        return
    end
    
    ngx.log(ngx.INFO, "🚀 Initializing permanent JS cache...")
    
    load_js_assets()
    
    CACHE_INITIALIZED = true
    ngx.log(ngx.INFO, "✅ Permanent JS cache initialized successfully")
end

-- =============================================
-- TEMPLATE FILE READING WITH CACHING
-- =============================================

local function read_file(path)
    -- Check template cache first
    local cached = TEMPLATE_CACHE[path]
    if cached then
        return cached
    end
    
    -- Read from filesystem
    local file = io.open(path, "r")
    if not file then
        error("File not found: " .. path)
    end
    local content = file:read("*a")
    file:close()
    
    -- Cache permanently
    TEMPLATE_CACHE[path] = content
    
    return content
end

-- =============================================
-- JS RETRIEVAL AND BUILDING
-- =============================================

local function get_js_content(filename)
    -- Initialize cache if not done yet
    if not CACHE_INITIALIZED then
        initialize_cache()
    end
    
    return JS_CACHE[filename] or ""
end

local function build_js_block(js_files)
    if not js_files or type(js_files) ~= "table" or #js_files == 0 then
        return ""
    end
    
    local js_content = {}
    
    for _, filename in ipairs(js_files) do
        local content = get_js_content(filename)
        if content and content ~= "" then
            table.insert(js_content, content)
        end
    end
    
    if #js_content == 0 then
        return ""
    end
    
    return "<script>\n(function() {\n'use strict';\n\n" .. 
           table.concat(js_content, "\n\n") .. 
           "\n\n})();\n</script>"
end

-- =============================================
-- ENHANCED TEMPLATE RENDERING
-- =============================================

local function render_template(path, context, depth)
    -- Initialize cache if not done yet
    if not CACHE_INITIALIZED then
        initialize_cache()
    end
    
    -- Read the main template file (will error if not found)
    local content = read_file(path)
    
    depth = depth or 2
    
    -- Process js_files if provided
    if context.js_files then
        context.js = build_js_block(context.js_files)
    end
    
    -- Original template processing logic
    for i = 1, depth do
        for key, value in pairs(context) do
            -- Check if value looks like an HTML file path using regex
            if type(value) == "string" and string.match(value, "%.html$") then
                -- This is an HTML file path - read it as a partial (will error if not found)
                local partial_content = read_file(value)

                -- Replace the placeholder with the file content
                content = content:gsub("{{%s*" .. key .. "%s*}}", partial_content)

                -- Update context for next pass - replace file path with content
                context[key] = partial_content
            else
                -- Regular variable replacement
                content = content:gsub("{{%s*" .. key .. "%s*}}", tostring(value))
            end
        end
    end

    ngx.header.content_type = "text/html"
    ngx.say(content)
end

-- =============================================
-- CONVENIENCE FUNCTIONS - UPDATED FOR CHAT PAGES
-- =============================================

-- Helper function to get appropriate JS files for user type and page
local function get_js_files_for_context(user_type, page_type)
    local js_files = {"is_shared.js"}  -- Always include core shared functionality
    
    -- Add chat functionality for chat pages
    if page_type == "chat" then
        table.insert(js_files, "is_shared_chat.js")  -- Include chat functionality
    end
    
    -- Add user-type specific JS
    local user_js_map = {
        is_admin = "is_admin.js",
        is_approved = "is_approved.js",
        is_guest = "is_guest.js", 
        is_none = "is_none.js",
        is_pending = "is_pending.js"
    }
    
    if user_js_map[user_type] then
        table.insert(js_files, user_js_map[user_type])
    end
    
    return js_files
end

-- Enhanced render function with automatic JS injection
local function render_with_assets(template_path, user_type, page_type, context)
    -- Auto-inject appropriate JS assets
    context.js_files = get_js_files_for_context(user_type, page_type)
    
    -- Call standard render function
    render_template(template_path, context)
end

-- Base template render function that uses base.html
local function render_page_with_base(page_content_path, user_type, page_type, context)
    -- Read the page content
    local content = read_file(page_content_path)
    
    -- Set the content in context
    context.content = content
    
    -- Use render_with_assets to handle JS and render with base template
    render_with_assets("/usr/local/openresty/nginx/dynamic_content/base.html", user_type, page_type, context)
end

-- =============================================
-- CACHE MANAGEMENT
-- =============================================

local function force_reload_cache()
    ngx.log(ngx.INFO, "🔄 Force reloading permanent cache...")
    
    -- Clear existing caches
    TEMPLATE_CACHE = {}
    JS_CACHE = {}
    CACHE_INITIALIZED = false
    
    -- Reinitialize
    initialize_cache()
    
    ngx.log(ngx.INFO, "✅ Cache reloaded successfully")
end

local function get_cache_stats()
    local function count_cache(cache)
        local count = 0
        local total_size = 0
        for key, value in pairs(cache) do
            count = count + 1
            if type(value) == "string" then
                total_size = total_size + string.len(value)
            end
        end
        return count, total_size
    end
    
    local template_count, template_size = count_cache(TEMPLATE_CACHE)
    local js_count, js_size = count_cache(JS_CACHE)
    
    return {
        initialized = CACHE_INITIALIZED,
        templates = {
            count = template_count,
            size_bytes = template_size
        },
        javascript = {
            count = js_count,
            size_bytes = js_size
        },
        total_size_bytes = template_size + js_size
    }
end

local function warm_up_cache()
    -- Force initialization on startup
    initialize_cache()
    
    -- Pre-load commonly used templates
    local common_templates = {
        "/usr/local/openresty/nginx/dynamic_content/base.html",
        "/usr/local/openresty/nginx/dynamic_content/chat.html",
        "/usr/local/openresty/nginx/dynamic_content/dash.html", 
        "/usr/local/openresty/nginx/dynamic_content/index.html",
        "/usr/local/openresty/nginx/dynamic_content/login.html",
        "/usr/local/openresty/nginx/dynamic_content/register.html",
        "/usr/local/openresty/nginx/dynamic_content/404.html",
        "/usr/local/openresty/nginx/dynamic_content/50x.html",
        "/usr/local/openresty/nginx/dynamic_content/429.html"
    }
    
    for _, template_path in ipairs(common_templates) do
        local file = io.open(template_path, "r")
        if file then
            local content = file:read("*all")
            file:close()
            TEMPLATE_CACHE[template_path] = content
            ngx.log(ngx.INFO, "✅ Pre-loaded template: " .. template_path)
        end
    end
    
    ngx.log(ngx.INFO, "🔥 Cache warm-up completed")
end

-- =============================================
-- MODULE EXPORTS
-- =============================================

return {
    -- Original API (backwards compatible)
    render_template = render_template,
    read_file = read_file,
    
    -- Enhanced rendering with automatic asset injection
    render_with_assets = render_with_assets,
    render_page_with_base = render_page_with_base,
    
    -- Asset builders
    build_js_block = build_js_block,
    get_js_files_for_context = get_js_files_for_context,
    
    -- Cache management
    initialize_cache = initialize_cache,
    warm_up_cache = warm_up_cache,
    force_reload_cache = force_reload_cache,
    get_cache_stats = get_cache_stats,
    
    -- Direct JS access
    get_js_content = get_js_content
}