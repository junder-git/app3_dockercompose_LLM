# Add these imports at the top with the other imports in app.py
import re
import json
from urllib.parse import urlparse, unquote
from github_connector import GithubConnector, format_code_for_llm, summarize_repository_for_llm

# Add this with the environment variables section
GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "")  # Optional GitHub token for higher rate limits

# Add these routes to app.py (place them before the last line that has the if __name__ == "__main__" block)

@app.route("/github-import", methods=["GET", "POST"])
@login_required
async def github_import():
    """Page to import code from GitHub"""
    user_id = current_user.user_id
    error = None
    success = None
    
    # Get user info
    async with db_pool.acquire() as conn:
        user = await conn.fetchrow(
            "SELECT username, full_name, is_admin FROM users WHERE id = $1",
            user_id
        )
    
    if request.method == "POST":
        form = await request.form
        github_url = form.get("github_url", "").strip()
        chat_title = form.get("chat_title", "").strip()
        
        if not github_url:
            error = "GitHub URL is required"
        elif not is_valid_github_url(github_url):
            error = "Invalid GitHub URL format"
        else:
            # Create a new chat for the GitHub import
            if not chat_title:
                # Generate a title based on the URL
                chat_title = generate_title_from_github_url(github_url)
            
            # Create a new chat
            async with db_pool.acquire() as conn:
                chat_id = await conn.fetchval(
                    """
                    INSERT INTO chats (user_id, title)
                    VALUES ($1, $2)
                    RETURNING id
                    """,
                    user_id, chat_title
                )
            
            # Redirect to process this in the background via websocket
            return redirect(url_for("github_process", chat_id=chat_id, url=github_url))
    
    return await render_template(
        "github_import.html",
        user=user,
        error=error,
        success=success
    )

@app.route("/github-process/<int:chat_id>")
@login_required
async def github_process(chat_id):
    """Page to process a GitHub URL import"""
    user_id = current_user.user_id
    github_url = request.args.get("url", "")
    
    # Verify that the chat belongs to the user
    async with db_pool.acquire() as conn:
        chat = await conn.fetchrow(
            "SELECT id, title FROM chats WHERE id = $1 AND user_id = $2",
            chat_id, user_id
        )
        
        if not chat:
            return redirect(url_for("index"))
        
        # Get user info
        user = await conn.fetchrow(
            "SELECT username, full_name, is_admin FROM users WHERE id = $1",
            user_id
        )
    
    if not github_url:
        return redirect(url_for("chat", chat_id=chat_id))
    
    return await render_template(
        "github_process.html",
        user=user,
        chat=chat,
        github_url=github_url
    )

@app.websocket("/ws/github/<int:chat_id>")
@login_required
async def ws_github(chat_id):
    """WebSocket endpoint for GitHub import processing"""
    user_id = current_user.user_id
    
    # Verify that the chat belongs to the user
    async with db_pool.acquire() as conn:
        chat = await conn.fetchrow(
            "SELECT id FROM chats WHERE id = $1 AND user_id = $2",
            chat_id, user_id
        )
        
        if not chat:
            return
    
    await websocket.accept()
    
    try:
        # Get the GitHub URL from the client
        message_data = await websocket.receive_json()
        github_url = message_data.get("github_url", "").strip()
        
        if not github_url or not is_valid_github_url(github_url):
            await websocket.send_json({
                "type": "error",
                "error": "Invalid GitHub URL"
            })
            return
        
        # Send status update
        await websocket.send_json({
            "type": "status",
            "message": "Connecting to GitHub..."
        })
        
        # Initialize GitHub connector with optional token
        github = GithubConnector(access_token=GITHUB_TOKEN if GITHUB_TOKEN else None)
        
        try:
            # Parse the GitHub URL
            await websocket.send_json({
                "type": "status",
                "message": "Parsing GitHub URL..."
            })
            
            parsed_url = await github.parse_github_url(github_url)
            
            # Send status update
            await websocket.send_json({
                "type": "status",
                "message": f"Fetching content from GitHub: {parsed_url['owner']}/{parsed_url['repo']}..."
            })
            
            # Fetch content from GitHub
            result = await github.fetch_from_url(github_url, max_files=30)
            
            if "error" in result:
                await websocket.send_json({
                    "type": "error",
                    "error": result["error"]
                })
                return
            
            # Send status update
            await websocket.send_json({
                "type": "status",
                "message": "Processing repository content..."
            })
            
            # Get repository summary
            repo_summary = await github.get_repository_summary(
                parsed_url["owner"],
                parsed_url["repo"]
            )
            
            # Format summary for LLM
            summary_text = await summarize_repository_for_llm(repo_summary)
            
            # Format code for LLM with size limit
            code_text = await format_code_for_llm(result["content"], context_limit=12000)
            
            # Create initial message with repository summary
            async with db_pool.acquire() as conn:
                user_msg_id = await conn.fetchval(
                    """
                    INSERT INTO messages (chat_id, role, content) 
                    VALUES ($1, $2, $3) 
                    RETURNING id
                    """,
                    chat_id, "user", f"Import from GitHub: {github_url}\n\n{summary_text}"
                )
            
            # Send confirmation of user message
            await websocket.send_json({
                "type": "message",
                "id": user_msg_id,
                "role": "user",
                "content": f"Import from GitHub: {github_url}",
                "timestamp": datetime.now().strftime("%H:%M")
            })
            
            # Send status update
            await websocket.send_json({
                "type": "status",
                "message": "Sending to DeepSeek-Coder for analysis..."
            })
            
            # Prepare system prompt
            system_prompt = """You are DeepSeek-Coder, an AI assistant specialized in code analysis. 
            You are examining a GitHub repository that has been imported. 
            Please analyze the code and provide a detailed summary including:
            1. The overall purpose of the repository
            2. Key components and their functionality
            3. The architecture and how components interact
            4. Any notable patterns, libraries, or technologies used
            5. Potential areas for improvement or issues
            
            Be thorough yet concise in your analysis."""
            
            # Build the prompt
            prompt = system_prompt + "\n\n"
            prompt += f"GitHub Repository Information:\n{summary_text}\n\n"
            prompt += f"Code Files:\n{code_text}\n\n"
            prompt += "Please provide a comprehensive analysis of this repository:"
            
            # Get currently selected model
            model = session.get("selected_model", MODEL_NAME)
            
            # Send to Ollama for analysis
            try:
                # Stream response from Ollama
                async with httpx.AsyncClient(timeout=300.0) as client:  # Increase timeout for large repos
                    response = await client.post(
                        f"http://{OLLAMA_HOST}:{OLLAMA_PORT}/api/generate",
                        json={
                            "model": model,
                            "prompt": prompt,
                            "stream": True
                        },
                        headers={"Content-Type": "application/json"},
                    )
                    
                    # Create assistant message in database
                    async with db_pool.acquire() as conn:
                        assistant_msg_id = await conn.fetchval(
                            """
                            INSERT INTO messages (chat_id, role, content) 
                            VALUES ($1, $2, $3) 
                            RETURNING id
                            """,
                            chat_id, "assistant", ""
                        )
                    
                    # Start with empty response
                    full_response = ""
                    
                    # Process streaming response
                    buffer = b""
                    async for chunk in response.aiter_bytes():
                        buffer += chunk
                        
                        # Process complete JSON objects
                        while b"\n" in buffer:
                            line, buffer = buffer.split(b"\n", 1)
                            if line.strip():
                                try:
                                    chunk_data = json.loads(line)
                                    if "response" in chunk_data:
                                        token = chunk_data["response"]
                                        full_response += token
                                        
                                        # Send token to client
                                        await websocket.send_json({
                                            "type": "token",
                                            "token": token,
                                            "id": assistant_msg_id
                                        })
                                        
                                        # If done flag is True, break
                                        if chunk_data.get("done", False):
                                            break
                                except json.JSONDecodeError:
                                    continue
                    
                    # Update the complete message in the database
                    async with db_pool.acquire() as conn:
                        await conn.execute(
                            "UPDATE messages SET content = $1 WHERE id = $2",
                            full_response, assistant_msg_id
                        )
                    
                    # Store repository files as artifacts
                    for file_path, file_info in result["content"].items():
                        if isinstance(file_info, dict) and "content" in file_info:
                            # Skip files that are too large or not text
                            if len(file_info["content"]) > 100000:  # Skip files larger than 100KB
                                continue
                            
                            # Only store actual code files
                            language = file_info.get("language", "")
                            if not language or language == "text":
                                continue
                            
                            # Create artifact title (use just the filename part)
                            filename = file_path.split("/")[-1]
                            title = f"{filename} (GitHub)"
                            
                            # Save artifact to database
                            async with db_pool.acquire() as conn:
                                artifact_id = await conn.fetchval(
                                    """
                                    INSERT INTO artifacts 
                                    (chat_id, message_id, title, content, content_type, language) 
                                    VALUES ($1, $2, $3, $4, $5, $6) 
                                    RETURNING id
                                    """,
                                    chat_id, assistant_msg_id, title,
                                    file_info["content"], "text/plain", language
                                )
                            
                            # Notify client about new artifact
                            await websocket.send_json({
                                "type": "artifact",
                                "id": artifact_id,
                                "title": title,
                                "language": language,
                                "created_at": datetime.now().strftime("%Y-%m-%d %H:%M")
                            })
                    
                    # Send completion message
                    await websocket.send_json({
                        "type": "complete",
                        "id": assistant_msg_id,
                        "role": "assistant",
                        "content": full_response,
                        "timestamp": datetime.now().strftime("%H:%M")
                    })
                    
            except Exception as e:
                print(f"Error processing with Ollama: {e}")
                await websocket.send_json({
                    "type": "error",
                    "error": str(e)
                })
                
        except Exception as e:
            print(f"GitHub error: {e}")
            await websocket.send_json({
                "type": "error",
                "error": f"GitHub error: {str(e)}"
            })
        finally:
            # Cleanup
            github.cleanup()
            
    except Exception as e:
        print(f"WebSocket error: {e}")
        await websocket.send_json({
            "type": "error",
            "error": f"Error: {str(e)}"
        })

# Helper functions for GitHub URL processing
def is_valid_github_url(url):
    """Check if a URL is a valid GitHub URL"""
    try:
        parsed = urlparse(url)
        return (
            parsed.netloc == "github.com" and
            len(parsed.path.strip("/").split("/")) >= 2
        )
    except:
        return False

def generate_title_from_github_url(url):
    """Generate a chat title from a GitHub URL"""
    try:
        parsed = urlparse(url)
        path_parts = parsed.path.strip("/").split("/")
        
        if len(path_parts) >= 2:
            owner = path_parts[0]
            repo = path_parts[1]
            
            # Check if there's a specific file or directory
            if len(path_parts) > 3 and path_parts[2] in ("blob", "tree"):
                if len(path_parts) > 4:
                    path_suffix = "/".join(path_parts[4:])
                    if len(path_suffix) > 30:
                        path_suffix = path_suffix[:27] + "..."
                    return f"{owner}/{repo}: {path_suffix}"
                else:
                    return f"{owner}/{repo}"
            else:
                return f"{owner}/{repo}"
        else:
            return "GitHub Import"
    except:
        return "GitHub Import"