Route Structure:

Static Routes: /login, /register (no auth needed)
Index Route: / (dynamic nav based on auth)
SPA Routes: /chat, /dash (routed to user-specific handlers)

Template System:

Main Template: app.html (skeleton with placeholders)
Partials: CSS, nav, content sections per user type
Max Depth 3: Main → Partials → User data

Lua Handler Flow:

nginx.conf routes /chat and /dash based on is_who
is_admin.lua, is_approved.lua, or is_guest.lua handles the request
Each handler assembles the appropriate partials into app.html
Template renders with depth 3 maximum

JavaScript Loading:

Guest: guest.js only
Approved: guest.js + approved.js
Admin: guest.js + approved.js + admin.js

Security Benefits:

Server controls all routing and template selection
Users only get templates/JS for their permission level
No client-side permission logic
Template depth prevents infinite loops

This gives you a clean, secure, performant SPA system where the server completely controls what each user type sees and can do.