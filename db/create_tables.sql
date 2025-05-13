# File: create_tables.sql
# Directory: /deepseek-coder-setup/db/

-- Create tables for authentication, user sessions, chat history, and artifacts

-- Users table for authentication
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    email VARCHAR(100) UNIQUE,
    full_name VARCHAR(100),
    is_admin BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP WITH TIME ZONE,
    login_attempts INTEGER DEFAULT 0,
    is_locked BOOLEAN DEFAULT FALSE,
    locked_until TIMESTAMP WITH TIME ZONE
);

-- Create default admin user
INSERT INTO users (username, password_hash, email, is_admin, full_name)
VALUES 
('admin', 
 crypt('admin', gen_salt('bf')), 
 'admin@example.com', 
 TRUE, 
 'System Administrator') 
ON CONFLICT (username) DO NOTHING;

-- Sessions table
CREATE TABLE IF NOT EXISTS sessions (
    id SERIAL PRIMARY KEY,
    session_id VARCHAR(255) UNIQUE NOT NULL,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    data JSONB,
    ip_address VARCHAR(45),
    user_agent TEXT
);

-- Rate limiting table
CREATE TABLE IF NOT EXISTS rate_limits (
    id SERIAL PRIMARY KEY,
    ip_address VARCHAR(45) NOT NULL,
    endpoint VARCHAR(100) NOT NULL,
    request_count INTEGER DEFAULT 1,
    last_request TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (ip_address, endpoint)
);

-- Chat history table
CREATE TABLE IF NOT EXISTS chats (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    is_archived BOOLEAN DEFAULT FALSE
);

-- Chat messages table
CREATE TABLE IF NOT EXISTS messages (
    id SERIAL PRIMARY KEY,
    chat_id INTEGER REFERENCES chats(id) ON DELETE CASCADE NOT NULL,
    role VARCHAR(20) NOT NULL CHECK (role IN ('user', 'assistant')),
    content TEXT NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Artifacts table (storing code/files generated during chat)
CREATE TABLE IF NOT EXISTS artifacts (
    id SERIAL PRIMARY KEY,
    chat_id INTEGER REFERENCES chats(id) ON DELETE CASCADE NOT NULL,
    message_id INTEGER REFERENCES messages(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    content TEXT NOT NULL,
    content_type VARCHAR(100) NOT NULL,
    language VARCHAR(50),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_sessions_session_id ON sessions(session_id);
CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON messages(chat_id);
CREATE INDEX IF NOT EXISTS idx_artifacts_chat_id ON artifacts(chat_id);
CREATE INDEX IF NOT EXISTS idx_artifacts_message_id ON artifacts(message_id);
CREATE INDEX IF NOT EXISTS idx_chats_user_id ON chats(user_id);
CREATE INDEX IF NOT EXISTS idx_rate_limits_ip_endpoint ON rate_limits(ip_address, endpoint);

-- Create helper functions
-- Function to update chat's updated_at timestamp when messages are added
CREATE OR REPLACE FUNCTION update_chat_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE chats SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.chat_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to update chat timestamp
CREATE OR REPLACE TRIGGER trigger_update_chat_timestamp
AFTER INSERT ON messages
FOR EACH ROW
EXECUTE FUNCTION update_chat_timestamp();

-- Function to check rate limit
CREATE OR REPLACE FUNCTION check_rate_limit(
    p_ip_address VARCHAR(45),
    p_endpoint VARCHAR(100),
    p_max_requests INTEGER,
    p_window_seconds INTEGER
) RETURNS BOOLEAN AS $$
DECLARE
    v_last_request TIMESTAMP WITH TIME ZONE;
    v_request_count INTEGER;
    v_window_start TIMESTAMP WITH TIME ZONE;
BEGIN
    -- Set window start time
    v_window_start := CURRENT_TIMESTAMP - (p_window_seconds || ' seconds')::INTERVAL;
    
    -- Get or create rate limit record
    SELECT last_request, request_count INTO v_last_request, v_request_count
    FROM rate_limits
    WHERE ip_address = p_ip_address AND endpoint = p_endpoint;
    
    IF NOT FOUND THEN
        -- First request from this IP for this endpoint
        INSERT INTO rate_limits (ip_address, endpoint, request_count, last_request)
        VALUES (p_ip_address, p_endpoint, 1, CURRENT_TIMESTAMP);
        RETURN TRUE;
    END IF;
    
    -- Check if we need to reset the counter (window passed)
    IF v_last_request < v_window_start THEN
        UPDATE rate_limits
        SET request_count = 1, last_request = CURRENT_TIMESTAMP
        WHERE ip_address = p_ip_address AND endpoint = p_endpoint;
        RETURN TRUE;
    END IF;
    
    -- Increment counter and check limit
    IF v_request_count < p_max_requests THEN
        UPDATE rate_limits
        SET request_count = request_count + 1, last_request = CURRENT_TIMESTAMP
        WHERE ip_address = p_ip_address AND endpoint = p_endpoint;
        RETURN TRUE;
    ELSE
        -- Rate limit exceeded
        RETURN FALSE;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Set permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_user;