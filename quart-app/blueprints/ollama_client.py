# ollama_client.py
import os
import json
import asyncio
import aiohttp
from typing import List, Dict
from .utils import sanitize_html

# AI Model configuration
OLLAMA_URL = os.environ.get('OLLAMA_URL', 'http://ollama:11434')
DEFAULT_MODEL = os.environ.get('OLLAMA_MODEL', 'deepseek-coder-v2:16b')

def get_active_model():
    """Get the active model name from the init script"""
    try:
        with open('/tmp/active_model', 'r') as f:
            return f.read().strip()
    except:
        return DEFAULT_MODEL

OLLAMA_MODEL = get_active_model()
MODEL_TEMPERATURE = float(os.environ.get('MODEL_TEMPERATURE', '0.7'))
MODEL_TOP_P = float(os.environ.get('MODEL_TOP_P', '0.9'))
MODEL_MAX_TOKENS = int(os.environ.get('MODEL_MAX_TOKENS', '2048'))
MODEL_TIMEOUT = int(os.environ.get('MODEL_TIMEOUT', '300'))

def clean_message_content(content: str, aggressive_clean: bool = False) -> str:
    """Clean message content from BOS tokens and other artifacts"""
    if not content:
        return ""
    
    cleaned = content.strip()
    
    # Only do aggressive cleaning on input, not on streaming output
    if aggressive_clean:
        # Remove common BOS/EOS tokens that might appear in content
        tokens_to_remove = [
            '<|begin_of_text|>', '<|end_of_text|>',
            '<|im_start|>', '<|im_end|>',
            '<|endoftext|>', '<|startoftext|>',
            '<s>', '</s>',
            '[INST]', '[/INST]',
            '<BOS>', '<EOS>',
            '<<SYS>>', '<</SYS>>',
        ]
        
        for token in tokens_to_remove:
            cleaned = cleaned.replace(token, '').strip()
    else:
        # Light cleaning for output - only remove tokens that are clearly system tokens
        # and appear at the start or end of content
        if cleaned.startswith('<|im_start|>'):
            cleaned = cleaned[12:].strip()
        if cleaned.endswith('<|im_end|>'):
            cleaned = cleaned[:-11].strip()
        if cleaned.startswith('<|begin_of_text|>'):
            cleaned = cleaned[17:].strip()
        if cleaned.endswith('<|end_of_text|>'):
            cleaned = cleaned[:-15].strip()
    
    return cleaned

async def get_ai_response(prompt: str, ws, chat_history: List[Dict] = None) -> str:
    """Get response from Ollama AI model with streaming and chat history"""
    full_response = ""
    
    # Send typing indicator
    await ws.send_json({'type': 'typing', 'status': 'start'})
    
    try:
        # Clean the input prompt aggressively
        cleaned_prompt = clean_message_content(prompt, aggressive_clean=True)
        
        # Build messages array for chat endpoint
        messages = []
        
        # Add chat history as messages (cleaned)
        if chat_history:
            for msg in chat_history[-8:]:  # Reduced to 8 messages for better performance
                role = msg.get('role')
                content = clean_message_content(msg.get('content', ''), aggressive_clean=True)
                if role in ['user', 'assistant'] and content:  # Only include valid roles with content
                    messages.append({
                        'role': role,
                        'content': content
                    })
        
        # Add current user message
        messages.append({
            'role': 'user',
            'content': cleaned_prompt
        })
        
        timeout = aiohttp.ClientTimeout(total=MODEL_TIMEOUT)
        async with aiohttp.ClientSession(timeout=timeout) as session:
            # Enhanced payload with better token handling
            payload = {
                'model': OLLAMA_MODEL,
                'messages': messages,
                'stream': True,
                'options': {
                    'temperature': MODEL_TEMPERATURE,
                    'top_p': MODEL_TOP_P,
                    'num_predict': MODEL_MAX_TOKENS,
                    'num_ctx': 4096,
                    'repeat_penalty': 1.1,
                    'mirostat': 0,  # Disable mirostat as it can cause issues
                    # Reduced stop tokens - only essential ones
                    'stop': ['<|im_end|>', '<|endoftext|>'],
                    # Prevent the model from generating special tokens
                    'penalize_newline': False,
                    'top_k': 40
                }
            }
            
            async with session.post(f'{OLLAMA_URL}/api/chat', json=payload) as response:
                if response.status != 200:
                    error_text = await response.text()
                    print(f"Ollama API error {response.status}: {error_text}")
                    await ws.send_json({
                        'type': 'error',
                        'message': f'AI service error (HTTP {response.status}). Please try again.'
                    })
                    return ""

                chunk_buffer = ""
                async for line in response.content:
                    if line:
                        try:
                            # Handle potential incomplete JSON chunks
                            line_str = line.decode('utf-8').strip()
                            if not line_str:
                                continue
                                
                            chunk_buffer += line_str
                            
                            # Try to parse complete JSON objects
                            while chunk_buffer:
                                try:
                                    chunk = json.loads(chunk_buffer)
                                    chunk_buffer = ""  # Reset buffer on successful parse
                                    
                                    # Handle chat API response format
                                    if 'message' in chunk and 'content' in chunk['message']:
                                        chunk_text = chunk['message']['content']
                                        
                                        # Light cleaning for streaming chunks - don't be too aggressive
                                        cleaned_chunk = clean_message_content(chunk_text, aggressive_clean=False)
                                        
                                        # Send chunks even if they seem small (could be punctuation, etc.)
                                        if cleaned_chunk:
                                            full_response += cleaned_chunk
                                            # Stream each chunk to client
                                            await ws.send_json({
                                                'type': 'stream',
                                                'content': cleaned_chunk
                                            })
                                    
                                    # Check if generation is complete
                                    if chunk.get('done', False):
                                        break
                                        
                                except json.JSONDecodeError:
                                    # If we can't parse, might be incomplete - wait for more data
                                    if len(chunk_buffer) > 10000:  # Prevent infinite buffer growth
                                        print(f"Discarding large unparseable buffer: {chunk_buffer[:100]}...")
                                        chunk_buffer = ""
                                    break
                                    
                        except Exception as e:
                            print(f"Error processing chunk: {e}")
                            continue
                            
                    # Break if we're done (check periodically)
                    if full_response and chunk_buffer == "":
                        break
                        
    except asyncio.TimeoutError:
        await ws.send_json({
            'type': 'error',
            'message': f'AI response timeout after {MODEL_TIMEOUT}s. Please try again.'
        })
    except Exception as e:
        print(f"Ollama API error: {e}")
        await ws.send_json({
            'type': 'error',
            'message': 'Failed to get AI response. Please check if the AI service is running.'
        })
    finally:
        # Stop typing indicator
        await ws.send_json({'type': 'typing', 'status': 'stop'})
    
    # Final cleanup of the complete response - light cleaning only
    final_response = clean_message_content(full_response, aggressive_clean=False)
    
    return final_response

async def health_check_ollama() -> bool:
    """Check if Ollama service is healthy and responsive"""
    try:
        timeout = aiohttp.ClientTimeout(total=10)
        async with aiohttp.ClientSession(timeout=timeout) as session:
            async with session.get(f'{OLLAMA_URL}/api/tags') as response:
                if response.status == 200:
                    data = await response.json()
                    # Check if our model is available
                    models = [model['name'] for model in data.get('models', [])]
                    return any(OLLAMA_MODEL in model for model in models)
                return False
    except Exception as e:
        print(f"Ollama health check failed: {e}")
        return False