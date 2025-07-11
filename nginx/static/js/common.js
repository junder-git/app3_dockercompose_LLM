const DevstralCommon = {};

// Load user info and update navbar
DevstralCommon.loadUser = function() {
    fetch('/api/auth/me', {
        method: 'GET',
        credentials: 'include'  // Important: send cookies
    })
    .then(res => res.json())
    .then(data => {
        if (data.username) {
            document.getElementById('navbar-username').textContent = data.username;
            document.getElementById('logout-button').style.display = 'inline-block';
        } else {
            document.getElementById('navbar-username').textContent = 'Guest';
            document.getElementById('logout-button').style.display = 'none';
        }
    })
    .catch(() => {
        document.getElementById('navbar-username').textContent = 'Guest';
        document.getElementById('logout-button').style.display = 'none';
    });
};

// Setup login form
DevstralCommon.setupLogin = function() {
    $('#login-form').on('submit', function(e) {
        e.preventDefault();
        const formData = {
            username: this.username.value,
            password: this.password.value
        };
        fetch('/api/auth/login', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            credentials: 'include', // Important: receive cookies
            body: JSON.stringify(formData)
        })
        .then(res => res.json())
        .then(data => {
            if (data.token) { // ✅ only check for token
                const redirect = new URLSearchParams(window.location.search).get('redirect') || '/chat.html';
                location.href = redirect;
            } else {
                alert('Invalid login');
            }
        })
        .catch(() => {
            alert('Login error');
        });
    });
};

// Setup register form
DevstralCommon.setupRegister = function() {
    $('#register-form').on('submit', function(e) {
        e.preventDefault();
        const formData = {
            username: this.username.value,
            password: this.password.value
        };
        fetch('/api/register', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(formData)
        })
        .then(res => res.json())
        .then(data => {
            if (data.success) {
                alert('Registration successful. Please wait for approval.');
                window.location.href = '/login.html';
            } else {
                alert(data.error || 'Registration failed.');
            }
        })
        .catch(() => {
            alert('Registration error');
        });
    });
};

// Setup logout button
document.getElementById('logout-button').addEventListener('click', function() {
    document.cookie = 'access_token=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT';
    location.reload();
});
