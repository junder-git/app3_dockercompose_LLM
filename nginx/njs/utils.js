function sanitizeHtml(text) {
    if (!text) return "";
    return text.replace(/&/g, "&amp;")
               .replace(/</g, "&lt;")
               .replace(/>/g, "&gt;")
               .replace(/"/g, "&quot;")
               .replace(/'/g, "&#x27;");
}

function validateUsername(username) {
    if (!username) return [false, "Username is required"];
    if (username.length < 3) return [false, "Username too short"];
    if (username.length > 32) return [false, "Username too long"];
    if (!/^[a-zA-Z0-9_-]+$/.test(username)) return [false, "Invalid characters"];
    return [true, ""];
}

function validatePassword(password) {
    if (!password) return [false, "Password is required"];
    if (password.length < 6) return [false, "Password too short"];
    if (password.length > 64) return [false, "Password too long"];
    return [true, ""];
}

export default { sanitizeHtml, validateUsername, validatePassword };
