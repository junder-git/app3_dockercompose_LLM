# ollama_client.py
import os
import json
import asyncio
import aiohttp
from typing import List, Dict
from .utils import sanitize_html

# AI Model configuration
OLLAMA_URL = os.environ.get('OLLAMA_URL', 'http://ollama:11434')
OLLAMA_MODEL = os.environ.get('OLLAMA_MODEL', 'deepseek-coder-v2:16b')
MODEL_TEMPERATURE = float(os.environ.get('MODEL_TEMPERATURE', '0.7'))
MODEL_TOP_P = float(os.environ.get('MODEL_TOP_P', '0.9'))
MODEL_MAX_TOKENS = int(os.environ.get('MODEL_MAX_TOKENS', '2048'))
MODEL_TIMEOUT = int(os.environ.get('MODEL_TIMEOUT', '300'))

async def get_ai_response(prompt: str, ws, chat_history: List[Dict] = None) -> str:
    """Get response from Ollama AI model with streaming and chat history"""
    full_response = ""
    
    # Send typing indicator
    await ws.send_json({'type': 'typing', 'status': 'start'})
    
    try:
        # Build messages array for chat endpoint (avoids BOS token issues)
        messages = []
        
        # Add chat history as messages
        if chat_history:
            for msg in chat_history[-10:]:  # Last 10 messages for context
                role = msg.get('role')
                content = msg.get('content', '')
                if role in ['user', 'assistant']:  # Only include valid roles
                    messages.append({
                        'role': role,
                        'content': content
                    })
        
        # Add current user message
        messages.append({
            'role': 'user',
            'content': prompt
        })
        
        timeout = aiohttp.ClientTimeout(total=MODEL_TIMEOUT)
        async with aiohttp.ClientSession(timeout=timeout) as session:
            # Use chat endpoint instead of generate to avoid BOS token issues
            async with session.post(
                f'{OLLAMA_URL}/api/chat',
                json={
                    'model': OLLAMA_MODEL,
                    'messages': messages,
                    'stream': True,
                    'options': {
                        'temperature': MODEL_TEMPERATURE,
                        'top_p': MODEL_TOP_P,
                        'num_predict': MODEL_MAX_TOKENS,
                        'num_ctx': 4096,
                        'repeat_penalty': 1.1,
                        'mirostat': 2,  # Better coherence
                        'mirostat_tau': 5.0,
                        'mirostat_eta': 0.1,
                        'stop': ['<|im_end|>', '<|endoftext|>']  # Common stop tokens
                    }
                }
            ) as response:
                if response.status != 200:
                    error_text = await response.text()
                    print(f"Ollama API error {response.status}: {error_text}")
                    await ws.send_json({
                        'type': 'error',
                        'message': f'AI service error (HTTP {response.status}). Please try again.'
                    })
                    return ""

                async for line in response.content:
                    if line:
                        try:
                            chunk = json.loads(line)
                            
                            # Handle chat API response format
                            if 'message' in chunk and 'content' in chunk['message']:
                                chunk_text = chunk['message']['content']
                                full_response += chunk_text
                                # Stream each chunk to client
                                await ws.send_json({
                                    'type': 'stream',
                                    'content': chunk_text
                                })
                                
                            if chunk.get('done', False):
                                break
                                
                        except json.JSONDecodeError:
                            continue
                        
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
    
    # Clean up the response
    for stop_token in ['<|im_end|>', '<|endoftext|>']:
        if full_response.endswith(stop_token):
            full_response = full_response[:-len(stop_token)]
    
    return full_response.strip()