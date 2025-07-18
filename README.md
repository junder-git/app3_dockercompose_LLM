git lfs install
git clone https://huggingface.co/mistralai/Devstral-Small-2507 ./volumes/models/devstral


=====

docker stop $(docker ps -aq)
docker rmi $(docker images -q)

=====

This is much cleaner and follows the DRY principle perfectly. All the complex logic lives in one place (is_who.lua), and nginx just delegates to it.

=====

my /static/js is public though... need to tweak that for adminjs and approvedjs

/
/chat
/dash
/pending
/login
/register

├── /api/auth/*
│   └── login.lua
│       ├── handle_login()
│       ├── handle_logout()
│       ├── handle_check_auth()
│       ├── handle_nav_refresh()
│       └── (render_nav_for_user - internal)

├── /api/register
│   └── register.lua
│       ├── handle_register_api()

├── /api/admin/*
│   └── is_admin.lua
│       ├── handle_admin_api()
│       │    ├── GET /api/admin/users
│       │    ├── GET /api/admin/stats
│       │    └── POST /api/admin/clear-guest-sessions
│       └── (handle_chat_page, handle_dash_page - for /chat, /dash)

├── /api/chat/*
│   ├── is_admin.lua → handle_chat_api() for admins
│   ├── is_approved.lua → handle_chat_api() for approved
│   ├── server.lua
│   │    └── handle_chat_stream_common() ← called internally by is_admin.lua & is_approved.lua
│   └── (chat streaming logic)

├── /api/guest/*
│   └── is_guest.lua
│       ├── handle_guest_api()
│       │    ├── POST /api/guest/create-session
│       │    ├── GET /api/guest/info
│       │    ├── GET /api/guest/stats
│       │    └── POST /api/guest/end
│       ├── initialize_guest_tokens() ← internal only
│       ├── validate_guest_session() ← internal only
│       ├── find_available_guest_slot() ← internal only
│       ├── create_secure_guest_session() ← internal only

(Static routes)

├── /login
│   └── is_public.lua → handle_login_page()

├── /register
│   └── is_public.lua → handle_register_page()

├── /
│   └── is_public.lua → handle_index_page()

├── /chat
│   └── is_who.lua → route_to_handler("chat")
│       ├── is_admin.lua → handle_chat_page()
│       ├── is_approved.lua → handle_chat_page()
│       ├── is_guest.lua → (guests get special flow or redirect)
│
├── /dash
│   └── is_who.lua → route_to_handler("dash")
│       ├── is_admin.lua → handle_dash_page()
│       ├── is_approved.lua → handle_dash_page()
│       ├── is_pending.lua → handle_dash_page()

├── /pending
│   └── is_who.lua → route_to_handler("dash") (alias)
