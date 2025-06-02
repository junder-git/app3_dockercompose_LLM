# ollama_client.py - Using Official Ollama Python Library
import os
import asyncio
from typing import List, Dict
from ollama import AsyncClient, ResponseError

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

# Create async client
client = AsyncClient(host=OLLAMA_URL)

async def get_ai_response(prompt: str, ws, chat_history: List[Dict] = None) -> str:
    """Get response from Ollama AI model with streaming and chat history"""
    full_response = ""
    
    # Send typing indicator
    await ws.send_json({'type': 'typing', 'status': 'start'})
    
    try:
        # Build messages array for chat
        messages = []
        
        # Add chat history (keep it simple - no cleaning)
        if chat_history:
            for msg in chat_history[-8:]:  # Last 8 messages for context
                role = msg.get('role')
                content = msg.get('content', '').strip()
                if role in ['user', 'assistant'] and content:
                    messages.append({
                        'role': role,
                        'content': content
                    })
        
        # Add current user message
        messages.append({
            'role': 'user',
            'content': prompt.strip()
        })
        
        # Configure options
        options = {
            'temperature': MODEL_TEMPERATURE,
            'top_p': MODEL_TOP_P,
            'num_predict': MODEL_MAX_TOKENS,
            'num_ctx': 4096,
            'repeat_penalty': 1.1,
        }
        
        # Use async streaming chat
        stream = await client.chat(
            model=OLLAMA_MODEL,
            messages=messages,
            stream=True,
            options=options
        )
        
        # Process streaming response
        async for chunk in stream:
            if 'message' in chunk and 'content' in chunk['message']:
                chunk_text = chunk['message']['content']
                
                if chunk_text:  # Send any non-empty chunk
                    full_response += chunk_text
                    # Stream each chunk to client
                    await ws.send_json({
                        'type': 'stream',
                        'content': chunk_text
                    })
        
    except ResponseError as e:
        print(f"Ollama ResponseError: {e.error}")
        await ws.send_json({
            'type': 'error',
            'message': f'AI model error: {e.error}'
        })
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
    
    return full_response.strip()

async def health_check_ollama() -> bool:
    """Check if Ollama service is healthy and responsive"""
    try:
        # Use the official library's list method to check health
        models = await client.list()
        
        # Check if our model is available
        available_models = [model['name'] for model in models.get('models', [])]
        return any(OLLAMA_MODEL in model for model in available_models)
        
    except Exception as e:
        print(f"Ollama health check failed: {e}")
        return False

async def get_available_models() -> List[str]:
    """Get list of available models"""
    try:
        models = await client.list()
        return [model['name'] for model in models.get('models', [])]
    except Exception as e:
        print(f"Failed to get available models: {e}")
        return []

async def test_model_response(model_name: str = None) -> Dict:
    """Test a quick response from the model"""
    if model_name is None:
        model_name = OLLAMA_MODEL
        
    try:
        response = await client.chat(
            model=model_name,
            messages=[{'role': 'user', 'content': 'Hello, please respond with just "API test successful"'}],
            stream=False,
            options={'num_predict': 20, 'temperature': 0.1}
        )
        
        return {
            'success': True,
            'response': response['message']['content'],
            'model': model_name
        }
    except Exception as e:
        return {
            'success': False,
            'error': str(e),
            'model': model_name
        }