local function render_template(path, context, depth)
    local file = io.open(path, "r")
    if not file then
        ngx.status = 500
        ngx.say("Template file not found: " .. path)
        return ngx.exit(500)
    end
    local content = file:read("*a")
    file:close()

    depth = depth or 2

    for i = 1, depth do
        for key, value in pairs(context) do
            content = content:gsub("{{%s*" .. key .. "%s*}}", value or "")
        end
    end

    ngx.header.content_type = "text/html"
    ngx.say(content)
end

return {
    render_template = render_template
}