local function render_template(file_path, context)
    local file = io.open(file_path, "r")
    if not file then
        return nil, "Template file not found: " .. file_path
    end
    local content = file:read("*a")
    file:close()

    for key, value in pairs(context) do
        content = content:gsub("{{%s*" .. key .. "%s*}}", value or "")
    end

    return content
end

return {
    render_template = render_template
}
