-- =============================================================================
-- nginx/lua/manage_template.lua - ENHANCED WITH CSS AND JS CACHE SUPPORT
-- =============================================================================

-- Configuration
local TEMPLATE_CACHE = {}
local JS_CACHE = {}
local CSS_CACHE = {}
local CACHE_INITIALIZED = false
local CSS_VERSION = os.time() -- Use timestamp as version, or set manually

-- FIXED: Use the correct paths from Dockerfile
local JS_BASE_PATH = "/usr/local/openresty/nginx/dynamic_content/js/"
local CSS_BASE_PATH = "/usr/local/openresty/nginx/dynamic_content/css/"

-- =============================================
-- CACHE INITIALIZATION - LOADS ALL JS AND CSS AT STARTUP
-- =============================================

local function load_js_assets()
    local js_files = {
        "is_shared.js",         -- Core shared functionality (non-chat)
        "is_shared_sse.js",     -- SSE management (must load before chat)
        "is_shared_code.js",    -- Code artifact management (must load before chat)
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

local function load_css_assets()
    local css_files = {
        "view_base.css",        -- Core shared styles
        "view_index.css",       -- Index page styles
        "view_chat.css",        -- Chat page styles
        "view_auth.css",        -- Auth pages styles (login/register)
        "view_dash.css",        -- Dashboard page styles
        "view_error.css"        -- Error pages styles
    }
    
    ngx.log(ngx.INFO, "Loading CSS files into permanent cache...")
    
    for _, filename in ipairs(css_files) do
        local filepath = CSS_BASE_PATH .. filename
        local file = io.open(filepath, "r")
        
        if file then
            local content = file:read("*all")
            file:close()
            CSS_CACHE[filename] = content
            ngx.log(ngx.INFO, "✅ Loaded CSS: " .. filename .. " (" .. string.len(content) .. " bytes)")
        else
            ngx.log(ngx.WARN, "❌ CSS file not found: " .. filepath)
            CSS_CACHE[filename] = "" -- Store empty string to avoid repeated file system checks
        end
    end
end

local function initialize_cache()
    if CACHE_INITIALIZED then
        return
    end
    
    ngx.log(ngx.INFO, "🚀 Initializing permanent JS and CSS cache...")
    
    load_js_assets()
    load_css_assets()
    
    CACHE_INITIALIZED = true
    ngx.log(ngx.INFO, "✅ Permanent JS and CSS cache initialized successfully")
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
-- JS AND CSS RETRIEVAL AND BUILDING
-- =============================================

local function get_js_content(filename)
    -- Initialize cache if not done yet
    if not CACHE_INITIALIZED then
        initialize_cache()
    end
    
    return JS_CACHE[filename] or ""
end

local function get_css_content(filename)
    -- Initialize cache if not done yet
    if not CACHE_INITIALIZED then
        initialize_cache()
    end
    
    return CSS_CACHE[filename] or ""
end

local function build_css_block(css_files)
    if not css_files or type(css_files) ~= "table" or #css_files == 0 then
        return ""
    end
    
    local css_content = {}
    
    for _, filename in ipairs(css_files) do
        local content = get_css_content(filename)
        if content and content ~= "" then
            table.insert(css_content, content)
        end
    end
    
    if #css_content == 0 then
        return ""
    end
    
    return "<style>\n" .. table.concat(css_content, "\n\n") .. "\n</style>"
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

-- NEW: Build individual CSS blocks for ordered loading
local function build_individual_css_blocks(css_files)
    if not css_files or type(css_files) ~= "table" or #css_files == 0 then
        return {}
    end
    
    local css_blocks = {}
    
    for _, filename in ipairs(css_files) do
        local content = get_css_content(filename)
        if content and content ~= "" then
            local block = "<style>\n" .. content .. "\n</style>"
            css_blocks[filename] = block
        else
            css_blocks[filename] = ""
        end
    end
    
    return css_blocks
end

-- NEW: Build individual JS blocks for ordered loading
local function build_individual_js_blocks(js_files)
    if not js_files or type(js_files) ~= "table" or #js_files == 0 then
        return {}
    end
    
    local js_blocks = {}
    
    for _, filename in ipairs(js_files) do
        local content = get_js_content(filename)
        if content and content ~= "" then
            local block = "<script>\n(function() {\n'use strict';\n\n" .. 
                         content .. 
                         "\n\n})();\n</script>"
            js_blocks[filename] = block
        else
            js_blocks[filename] = ""
        end
    end
    
    return js_blocks
end

-- =============================================
-- ENHANCED TEMPLATE RENDERING WITH CSS SUPPORT
-- =============================================

local function render_template(path, context, depth)
    -- Initialize cache if not done yet
    if not CACHE_INITIALIZED then
        initialize_cache()
    end
    
    -- Read the main template file (will error if not found)
    local content = read_file(path)
    
    depth = depth or 2
    
    -- Process js_files if provided (for backward compatibility)
    if context.js_files and not context.js then
        context.js = build_js_block(context.js_files)
    end
    
    -- Process css_files if provided
    if context.css_files and not context.css then
        context.css = build_css_block(context.css_files)
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
-- CONVENIENCE FUNCTIONS - UPDATED FOR CSS AND CHAT PAGES
-- =============================================

-- Helper function to get appropriate CSS files for user type and page
local function get_css_files_for_context(user_type, page_type)
    local css_files = {"view_base.css"}  -- Always include core shared styles
    
    -- Add page-specific styles
    if page_type == "index" then
        table.insert(css_files, "view_index.css")
    elseif page_type == "chat" then
        table.insert(css_files, "view_chat.css")
    elseif page_type == "auth" then
        table.insert(css_files, "view_auth.css")
    elseif page_type == "dashboard" then
        table.insert(css_files, "view_dash.css")
    elseif page_type == "error" then
        table.insert(css_files, "view_error.css")
    end
    
    return css_files
end

-- Helper function to get appropriate JS files for user type and page
local function get_js_files_for_context(user_type, page_type)
    local js_files = {"is_shared.js"}  -- Always include core shared functionality
    
    -- Add specialized modules for chat pages IN CORRECT ORDER
    if page_type == "chat" then
        table.insert(js_files, "is_shared_sse.js")    -- Load SSE first
        table.insert(js_files, "is_shared_code.js")   -- Load Code second
        table.insert(js_files, "is_shared_chat.js")   -- Load Chat last (depends on both)
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

-- Enhanced render function that includes CSS and JS versioning
local function render_with_versioned_assets(template_path, user_type, page_type, context)
    context.css_version = os.time()
    
    -- Auto-inject appropriate CSS assets
    context.css_files = get_css_files_for_context(user_type, page_type)
    
    -- Auto-inject appropriate JS assets (existing logic)
    context.js_files = get_js_files_for_context(user_type, page_type)
    
    -- For chat pages, create individual JS blocks for ordered loading
    if page_type == "chat" then
        local js_blocks = build_individual_js_blocks(context.js_files)
        context.js_shared = js_blocks["is_shared.js"] or ""
        context.js_sse = js_blocks["is_shared_sse.js"] or ""
        context.js_code = js_blocks["is_shared_code.js"] or ""
        context.js_chat = js_blocks["is_shared_chat.js"] or ""
        
        -- Add user-specific JS
        local user_js_map = {
            is_admin = "is_admin.js",
            is_approved = "is_approved.js",
            is_guest = "is_guest.js", 
            is_none = "is_none.js",
            is_pending = "is_pending.js"
        }
        
        if user_js_map[user_type] then
            context.js_user = js_blocks[user_js_map[user_type]] or ""
        else
            context.js_user = ""
        end
        
        -- Clear the combined js field for chat pages
        context.js = ""
        
        -- For chat pages, also create individual CSS blocks for ordered loading
        local css_blocks = build_individual_css_blocks(context.css_files)
        context.css_base = css_blocks["view_base.css"] or ""
        context.css_chat = css_blocks["view_chat.css"] or ""
        
        -- Clear the combined css field for chat pages
        context.css = ""
    else
        -- For non-chat pages, use combined JS and CSS blocks
        context.js = build_js_block(context.js_files)
        context.css = build_css_block(context.css_files)
        
        -- Also create individual CSS blocks for flexibility
        local css_blocks = build_individual_css_blocks(context.css_files)
        context.css_base = css_blocks["view_base.css"] or ""
        context.css_index = css_blocks["view_index.css"] or ""
        context.css_auth = css_blocks["view_auth.css"] or ""
        context.css_dash = css_blocks["view_dash.css"] or ""
        context.css_error = css_blocks["view_error.css"] or ""
    end
    
    -- Call standard render function
    render_template(template_path, context)
end

-- Base template render function that uses base.html
local function render_page_with_base(page_content_path, user_type, page_type, context)
    -- Read the page content
    local content = read_file(page_content_path)
    
    -- Set the content in context
    context.content = content
    
    -- Use render_with_versioned_assets to handle CSS/JS and render with base template
    render_with_versioned_assets("/usr/local/openresty/nginx/dynamic_content/base.html", user_type, page_type, context)
end

-- =============================================
-- CACHE MANAGEMENT
-- =============================================

local function force_reload_cache()
    ngx.log(ngx.INFO, "🔄 Force reloading permanent cache...")
    
    -- Clear existing caches
    TEMPLATE_CACHE = {}
    JS_CACHE = {}
    CSS_CACHE = {}
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
    local css_count, css_size = count_cache(CSS_CACHE)
    
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
        css = {
            count = css_count,
            size_bytes = css_size
        },
        total_size_bytes = template_size + js_size + css_size
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

-- Update your module exports
return {
    -- Original API (backwards compatible)
    render_template = render_template,
    read_file = read_file,
    
    -- Enhanced rendering with automatic asset injection AND versioning
    render_with_versioned_assets = render_with_versioned_assets, -- Updated function
    render_page_with_base = render_page_with_base,
    
    -- Asset builders
    build_js_block = build_js_block,
    build_css_block = build_css_block,
    build_individual_js_blocks = build_individual_js_blocks,
    build_individual_css_blocks = build_individual_css_blocks,
    get_js_files_for_context = get_js_files_for_context,
    get_css_files_for_context = get_css_files_for_context,
    
    -- Cache management
    initialize_cache = initialize_cache,
    warm_up_cache = warm_up_cache,
    force_reload_cache = force_reload_cache,
    get_cache_stats = get_cache_stats,
    
    -- Direct asset access
    get_js_content = get_js_content,
    get_css_content = get_css_content
}