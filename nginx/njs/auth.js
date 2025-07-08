// nginx/njs/auth.js - NJS-compatible version
import database from "./database.js";
import utils from "./utils.js";

function generateToken(user) {
    var payload = {
        user_id: user.id,
        username: user.username,
        is_admin: user.is_admin,
        exp: Date.now() + (7 * 24 * 60 * 60 * 1000) // 7 days
    };
    return Buffer.from(JSON.stringify(payload)).toString('base64');
}

function verifyToken(token) {
    try {
        var payload = JSON.parse(Buffer.from(token, 'base64').toString());
        if (payload.exp < Date.now()) {
            return null;
        }
        return payload;
    } catch (e) {
        return null;
    }
}

async function verifyRequest(r) {
    try {
        var authHeader = r.headersIn.Authorization;
        if (!authHeader || !authHeader.startsWith('Bearer ')) {
            return { success: false, error: "No token provided" };
        }

        var token = authHeader.substring(7);
        var payload = verifyToken(token);
        
        if (!payload) {
            return { success: false, error: "Invalid or expired token" };
        }

        var user = await database.getUserById(payload.user_id);
        if (!user) {
            return { success: false, error: "User not found" };
        }

        if (user.is_approved !== 'true' && user.is_approved !== true) {
            return { success: false, error: "Account not approved" };
        }

        return { 
            success: true, 
            user: {
                id: user.id,
                username: user.username,
                is_admin: user.is_admin === 'true' || user.is_admin === true
            }
        };

    } catch (e) {
        return { success: false, error: "Authentication failed" };
    }
}

async function handleLogin(r) {
    try {
        r.log('=== LOGIN REQUEST START ===');
        r.log('Method: ' + r.method);
        r.log('Content-Type: ' + (r.headersIn['Content-Type'] || 'not set'));
        r.log('Content-Length: ' + (r.headersIn['Content-Length'] || 'not set'));
        
        if (r.method !== 'POST') {
            r.return(405, JSON.stringify({ error: 'Method not allowed' }));
            return;
        }

        // In NJS, we need to read the request body synchronously
        var body = null;
        var data = null;
        
        // Try different ways to get the request body
        if (r.requestBody !== undefined) {
            body = r.requestBody;
            r.log('Got body from r.requestBody: ' + (body || 'null'));
        } else if (r.requestText !== undefined) {
            body = r.requestText;
            r.log('Got body from r.requestText: ' + (body || 'null'));
        } else {
            // Try to get from variables
            if (r.variables && r.variables.request_body) {
                body = r.variables.request_body;
                r.log('Got body from variables: ' + (body || 'null'));
            }
        }
        
        // Debug: show all available properties on r
        var allProps = Object.getOwnPropertyNames(r);
        var props = [];
        for (var i = 0; i < allProps.length; i++) {
            var prop = allProps[i];
            if (typeof r[prop] !== 'function' && prop.indexOf('_') !== 0 && prop.length < 20) {
                props.push(prop);
            }
        }
        r.log('Available properties on r: ' + props.join(', '));
        
        // If still no body, try reading from query string for testing
        if (!body && r.args) {
            if (r.args.username && r.args.password) {
                r.log('Using query parameters for testing');
                data = {
                    username: r.args.username,
                    password: r.args.password
                };
            }
        }
        
        if (!body && !data) {
            r.return(400, JSON.stringify({ 
                error: 'Request body required',
                debug: {
                    method: r.method,
                    contentType: r.headersIn['Content-Type'],
                    contentLength: r.headersIn['Content-Length'],
                    hasRequestBody: r.hasOwnProperty('requestBody'),
                    hasRequestText: r.hasOwnProperty('requestText'),
                    hasVariables: r.hasOwnProperty('variables'),
                    requestBodyValue: r.requestBody,
                    requestTextValue: r.requestText,
                    availableProps: props,
                    args: r.args
                }
            }));
            return;
        }

        // Parse JSON if we have a body string
        if (body && !data) {
            try {
                data = JSON.parse(body);
                r.log('Parsed JSON successfully');
            } catch (parseError) {
                r.log('JSON parse error: ' + parseError.message);
                r.return(400, JSON.stringify({ 
                    error: 'Invalid JSON in request body',
                    body: body.substring(0, 100),
                    parseError: parseError.message
                }));
                return;
            }
        }
        
        if (!data) {
            r.return(400, JSON.stringify({ error: 'No data found in request' }));
            return;
        }
        
        var username = data.username;
        var password = data.password;
        
        r.log('Username: ' + username);
        r.log('Password provided: ' + (password ? 'yes' : 'no'));

        // Validate input
        var usernameValidation = utils.validateUsername(username);
        if (!usernameValidation[0]) {
            r.return(400, JSON.stringify({ error: usernameValidation[1] }));
            return;
        }

        var passwordValidation = utils.validatePassword(password);
        if (!passwordValidation[0]) {
            r.return(400, JSON.stringify({ error: passwordValidation[1] }));
            return;
        }

        // Get user from database
        r.log('Looking up user: ' + username);
        var user = await database.getUserByUsername(username);
        if (!user) {
            r.log('User not found');
            r.return(401, JSON.stringify({ error: 'Invalid credentials' }));
            return;
        }

        r.log('User found: ' + user.username);
        r.log('Stored password hash: ' + user.password_hash);
        r.log('Provided password: ' + password);

        // Check password
        if (user.password_hash !== password) {
            r.log('Password mismatch');
            r.return(401, JSON.stringify({ error: 'Invalid credentials' }));
            return;
        }

        // Check if user is approved
        r.log('User approved status: ' + user.is_approved);
        if (user.is_approved !== 'true' && user.is_approved !== true) {
            r.log('User not approved');
            r.return(403, JSON.stringify({ error: 'Account pending approval' }));
            return;
        }

        r.log('Login successful, generating token');

        // Generate token
        var token = generateToken({
            id: user.id,
            username: user.username,
            is_admin: user.is_admin === 'true' || user.is_admin === true
        });

        r.log('Token generated successfully');

        // Return success response
        r.return(200, JSON.stringify({
            success: true,
            token: token,
            user: {
                id: user.id,
                username: user.username,
                is_admin: user.is_admin === 'true' || user.is_admin === true
            }
        }));

    } catch (e) {
        r.log('Login error: ' + e.message);
        r.log('Error stack: ' + (e.stack || 'no stack'));
        r.return(500, JSON.stringify({ 
            error: 'Internal server error',
            details: e.message
        }));
    }
}

async function handleRegister(r) {
    try {
        r.log('=== REGISTER REQUEST START ===');
        
        if (r.method !== 'POST') {
            r.return(405, JSON.stringify({ error: 'Method not allowed' }));
            return;
        }

        var body = r.requestBody || r.requestText || (r.variables && r.variables.request_body);
        var data = null;
        
        // Try query params for testing
        if (!body && r.args && r.args.username && r.args.password) {
            data = {
                username: r.args.username,
                password: r.args.password
            };
        }
        
        if (!body && !data) {
            r.return(400, JSON.stringify({ error: 'Request body required' }));
            return;
        }

        if (body && !data) {
            try {
                data = JSON.parse(body);
            } catch (parseError) {
                r.return(400, JSON.stringify({ error: 'Invalid JSON in request body' }));
                return;
            }
        }

        var username = data.username;
        var password = data.password;

        // Validate input
        var usernameValidation = utils.validateUsername(username);
        if (!usernameValidation[0]) {
            r.return(400, JSON.stringify({ error: usernameValidation[1] }));
            return;
        }

        var passwordValidation = utils.validatePassword(password);
        if (!passwordValidation[0]) {
            r.return(400, JSON.stringify({ error: passwordValidation[1] }));
            return;
        }

        // Check if user already exists
        var existingUser = await database.getUserByUsername(username);
        if (existingUser) {
            r.return(409, JSON.stringify({ error: 'Username already exists' }));
            return;
        }

        // Create new user
        var newUser = {
            id: Date.now().toString(),
            username: username,
            password_hash: password,
            is_admin: false,
            is_approved: false,
            created_at: new Date().toISOString()
        };

        var saved = await database.saveUser(newUser);
        if (!saved) {
            r.return(500, JSON.stringify({ error: 'Failed to create user' }));
            return;
        }

        r.return(201, JSON.stringify({
            success: true,
            message: 'User created successfully. Pending admin approval.',
            user: {
                id: newUser.id,
                username: newUser.username,
                is_approved: false
            }
        }));

    } catch (e) {
        r.log('Register error: ' + e.message);
        r.return(500, JSON.stringify({ error: 'Internal server error' }));
    }
}

async function verifyTokenEndpoint(r) {
    try {
        var authResult = await verifyRequest(r);
        
        if (!authResult.success) {
            r.return(401, JSON.stringify({ error: authResult.error }));
            return;
        }

        r.return(200, JSON.stringify({
            success: true,
            user: authResult.user
        }));

    } catch (e) {
        r.log('Token verification error: ' + e.message);
        r.return(500, JSON.stringify({ error: 'Token verification failed' }));
    }
}

export default { 
    generateToken, 
    verifyToken,
    verifyRequest,
    handleLogin, 
    handleRegister,
    verifyTokenEndpoint
};