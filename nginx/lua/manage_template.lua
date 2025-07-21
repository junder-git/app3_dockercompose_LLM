-- Helper function to read a file and return its content
local function read_file(path)
    local file = io.open(path, "r")
    if not file then
        error("File not found: " .. path)
    end
    local content = file:read("*a")
    file:close()
    return content
end
-- Template rendering function
local function render_template(path, context, depth)
    -- Read the main template file (will error if not found)
    local content = read_file(path)

    depth = depth or 2

    for i = 1, depth do
        for key, value in pairs(context) do
            -- Check if value looks like an HTML file path using regex
            if type(value) == "string" and string.match(value, "%.html$") then
                -- This is an HTML file path - read it as a partial (will error if not found)
                local partial_content = read_file(value)

                -- Replace the placeholder with the file content
                content = content:gsub("{{%s" .. key .. "%s}}", partial_content)

                -- Update context for next pass - replace file path with content
                context[key] = partial_content
            else
                -- Regular variable replacement
                content = content:gsub("{{%s" .. key .. "%s}}", tostring(value))
            end
        end
    end

    ngx.header.content_type = "text/html"
    ngx.say(content)
end
return {
    render_template = render_template,
    read_file = read_file
}