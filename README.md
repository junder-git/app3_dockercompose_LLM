# Final Routing Structure Summary

## User Type Access Matrix

| Route      | is_none | is_guest | is_pending | is_approved | is_admin |
|------------|---------|----------|------------|-------------|----------|
| `/`        | ✅      | ✅       | ✅         | ✅          | ✅       |
| `/login`   | ✅      | ✅       | ❌         | ❌          | ❌       |
| `/register`| ✅      | ✅       | ❌         | ❌          | ❌       |
| `/chat`    | ❌      | ✅       | ❌         | ✅          | ✅       |
| `/dash`    | ❌      | ✅       | ✅         | ✅          | ✅       |

## Routing Logic in `is_who.lua`

### **is_admin & is_approved**
- ✅ Can see: `/`, `/chat`, `/dash`
- 🔄 Redirected: `/login` → `/dash`, `/register` → `/dash`

### **is_guest** 
- ✅ Can see: ALL routes (`/`, `/chat`, `/dash`, `/login`, `/register`)
- 🔄 No redirects (guests have full access)

### **is_pending**
- ✅ Can see: `/`, `/dash` (shows pending status)
- 🔄 Redirected: `/chat` → `/dash`, `/login` → `/dash`, `/register` → `/dash`

### **is_none**
- ✅ Can see: `/`, `/login`, `/register`
- 🔄 Redirected: `/chat` → `/`, `/dash` → `/`
- 🎯 **Guest Upgrade**: Can acquire `is_guest` status through available logic

## Module Responsibilities

### **`is_who.lua` (Router & Controller)**
- High-level routing and redirects
- Error page handlers (404, 429, 50x)
- Ollama API delegation
- Auth/Register/Admin API routing

### **`is_none.lua` (Public + Guest Acquisition)**
- Handles: `index`, `login`, `register` pages
- **Guest session creation API** (moved from is_guest)
- Shows guest availability on index/dash pages
- Template usage: `{{ page_title }}`, `{{ nav }}`, etc.

### **`is_guest.lua` (Active Guests)**
- Handles: ALL pages (`index`, `chat`, `dash`, `login`, `register`)  
- Guest-specific dashboard showing session status
- Ollama chat streaming for guests
- Template usage: Shows guest session info in templates

### **`is_approved.lua` (Approved Users)**
- Handles: `index` → redirect to `/dash`, `chat`, `dash`
- Full chat access with Redis history
- Ollama streaming with higher limits
- Template usage: Approved user features

### **`is_admin.lua` (Administrators)**
- Handles: `index` → redirect to `/dash`, `chat`, `dash`
- Admin dashboard with system stats
- Ollama streaming with highest limits
- Admin API management
- Template usage: Admin-specific features

### **`is_pending.lua` (Pending Users)**
- Handles: `index` → redirect to `/dash`, `dash` (pending status)
- Shows account pending approval status
- Template usage: Pending status info

## Template Integration

All modules use the `{{ }}` template syntax:

```lua
local context = {
    page_title = "Chat - ai.junder.uk",
    nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",
    username = username,
    dash_buttons = get_nav_buttons(username),
    chat_features = get_chat_features(),
    chat_placeholder = "Ask anything..."
}

template.render_template("/usr/local/openresty/nginx/dynamic_content/chat.html", context)
```

## Key Features

1. **Clean Separation**: Each module handles only what it should access
2. **Guest Acquisition**: `is_none` users can upgrade to `is_guest` temporarily
3. **Template-Driven**: All pages use `{{ }}` template syntax consistently
4. **Ollama Integration**: Each user type has appropriate streaming limits
5. **Error Handling**: Centralized in `is_who.lua`
6. **API Routing**: Smart delegation based on user type and endpoint

This structure is maintainable, follows single-responsibility principle, and provides clear upgrade paths for users!