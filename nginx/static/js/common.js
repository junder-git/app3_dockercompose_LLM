window.DevstralCommon = {
    loadUser: async function () {
        try {
            const res = await fetch("/api/auth/me", { credentials: "include" }).then(r => r.json());
            const usernameSpan = document.getElementById("navbar-username");
            const logoutButton = document.getElementById("logout-button");
            if (res.success && res.username) {
                usernameSpan.innerText = `Logged in as: ${res.username}`;
                logoutButton.style.display = "inline-block";
                logoutButton.onclick = () => {
                    document.cookie = "access_token=; Max-Age=0; Path=/";
                    window.location.href = "/login.html";
                };
            } else {
                usernameSpan.innerText = "Guest";
                logoutButton.style.display = "none";
                if (window.location.pathname.includes("chat") || window.location.pathname.includes("admin")) {
                    window.location.href = "/login.html";
                }
            }
        } catch (err) {
            console.error("Error fetching user:", err);
        }
    },

    setupLogin: function () {
        const form = document.getElementById("login-form");
        if (!form) return;
        form.addEventListener("submit", async function (e) {
            e.preventDefault();
            const formData = new FormData(form);
            const payload = {
                username: formData.get("username"),
                password: formData.get("password")
            };
            try {
                const res = await fetch("/api/auth/login", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify(payload)
                }).then(r => r.json());
                if (res.success && res.token) {
                    document.cookie = `access_token=${res.token}; Path=/;`;
                    window.location.href = "/chat.html"; // Redirect after login
                } else {
                    alert("Invalid credentials");
                }
            } catch {
                alert("Login failed");
            }
        });
    },

    setupRegister: function () {
        const form = document.getElementById("register-form");
        if (!form) return;
        form.addEventListener("submit", async function (e) {
            e.preventDefault();
            const formData = new FormData(form);
            const payload = {
                username: formData.get("username"),
                password: formData.get("password")
            };
            try {
                const res = await fetch("/api/register", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify(payload)
                }).then(r => r.json());
                if (res.success) {
                    alert("Registered successfully, please log in!");
                    window.location.href = "/login.html";
                } else {
                    alert("Registration failed");
                }
            } catch {
                alert("Registration failed");
            }
        });
    },

    setupChat: function () {
        console.log("Chat setup called");
        // Add your chat-specific frontend logic here
    },

    loadAdminPanel: function () {
        console.log("Admin panel setup called");
        // Add your admin-specific frontend logic here
    }
};
