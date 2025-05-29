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

def clean_message_content(content: str) -> str:
    """Clean message content from BOS tokens and other artifacts"""
    if not content:
        return ""
    
    # Remove common BOS/EOS tokens that might appear in content
    tokens_to_remove = [
        '<|begin_of_text|>', '<|end_of_text|>',
        '<|im_start|>', '<|im_end|>',
        '<|endoftext|>', '<|startoftext|>',
        '<s>', '</s>',
        '[INST]', '[/INST]',
        '<BOS>', '<EOS>',
        '<<SYS>>', '<</SYS>>',
        # Add any other tokens you notice causing issues
    ]
    
    cleaned = content.strip()
    for token in tokens_to_remove:
        cleaned = cleaned.replace(token, '').strip()
    
    return cleaned

async def get_ai_response(prompt: str, ws, chat_history: List[Dict] = None) -> str:
    """Get response from Ollama AI model with streaming and chat history"""
    full_response = ""
    
    # Send typing indicator
    await ws.send_json({'type': 'typing', 'status': 'start'})
    
    try:
        # Clean the input prompt
        cleaned_prompt = clean_message_content(prompt)
        
        # Build messages array for chat endpoint
        messages = []
        
        # Add chat history as messages (cleaned)
        if chat_history:
            for msg in chat_history[-8:]:  # Reduced to 8 messages for better performance
                role = msg.get('role')
                content = clean_message_content(msg.get('content', ''))
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
                    'mirostat': 2,
                    'mirostat_tau': 5.0,
                    'mirostat_eta': 0.1,
                    # Enhanced stop tokens to prevent BOS token issues
                    'stop': [
                        '<|im_end|>', '<|endoftext|>', '<|end_of_text|>',
                        '<|begin_of_text|>', '<s>', '</s>',
                        '[INST]', '[/INST]', '<<SYS>>', '<</SYS>>',
                        '<BOS>', '<EOS>'
                    ],
                    # Prevent the model from generating special tokens
                    'penalize_newline': False,
                    'top_k': 40,
                    'typical_p': 1.0,
                    'min_p': 0.05
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
                                        
                                        # Clean the chunk text
                                        cleaned_chunk = clean_message_content(chunk_text)
                                        
                                        if cleaned_chunk:  # Only send non-empty chunks
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
    
    # Final cleanup of the complete response
    final_response = clean_message_content(full_response)
    
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