async function apiGet(url) {
  const res = await fetch(url, {
    method: "GET",
    credentials: "include",
    headers: { "Content-Type": "application/json" }
  });
  return await res.json();
}

async function apiPost(url, data = {}) {
  const res = await fetch(url, {
    method: "POST",
    credentials: "include",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(data)
  });
  return await res.json();
}

async function loadUser() {
  try {
    const res = await apiGet("/api/auth/me");
    const usernameEl = document.getElementById("navbar-username");
    const logoutBtn = document.getElementById("logout-button");

    if (res.success && res.username) {
      if (usernameEl) usernameEl.innerText = `Logged in as: ${res.username}`;
      if (logoutBtn) {
        logoutBtn.style.display = "inline-block";
        logoutBtn.addEventListener("click", () => {
          document.cookie = "access_token=; Max-Age=0; Path=/";
          location.href = "/login.html";
        });
      }
    } else {
      if (usernameEl) usernameEl.innerText = "Guest";
    }
  } catch {
    const usernameEl = document.getElementById("navbar-username");
    if (usernameEl) usernameEl.innerText = "Guest";
  }
}

async function loadAdminPanel() {
  const res = await apiGet("/api/auth/me");
  if (!res.success || !res.is_admin) {
    window.location.href = "/login.html";
  }
}

async function setupChat() {
  const res = await apiGet("/api/auth/me");
  if (!res.success) {
    window.location.href = "/login.html";
  }
  // You can add further chat event listeners here
}

function setupLogin() {
  const loginForm = document.getElementById("login-form");
  if (loginForm) {
    loginForm.addEventListener("submit", async (e) => {
      e.preventDefault();
      const username = document.getElementById("username").value;
      const password = document.getElementById("password").value;

      const res = await apiPost("/api/auth/login", { username, password });
      if (res.success && res.token) {
        document.cookie = `access_token=${res.token}; Path=/;`;
        window.location.href = "/chat.html";
      } else {
        alert("Invalid credentials");
      }
    });
  }
}

function setupRegister() {
  const regForm = document.getElementById("register-form");
  if (regForm) {
    regForm.addEventListener("submit", async (e) => {
      e.preventDefault();
      const username = document.getElementById("username").value;
      const password = document.getElementById("password").value;

      const res = await apiPost("/api/register", { username, password });
      if (res.success) {
        alert("Registered successfully. Please login.");
        window.location.href = "/login.html";
      } else {
        alert("Registration failed: " + (res.error || "Unknown error"));
      }
    });
  }
}

window.DevstralCommon = {
  apiGet,
  apiPost,
  loadUser,
  loadAdminPanel,
  setupChat,
  setupLogin,
  setupRegister
};
