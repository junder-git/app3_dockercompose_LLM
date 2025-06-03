# quart-app/blueprints/github.py
from quart import Blueprint, request, jsonify, session
import aiohttp
import base64
from .auth import login_required

github_bp = Blueprint('github', __name__)

@github_bp.route('/api/github/connect', methods=['POST'])
@login_required
async def connect_github():
    """Store GitHub token for the user"""
    data = await request.get_json()
    token = data.get('token')

    if not token:
        return jsonify({'error': 'Token required'}), 400

    # Verify token by making a test request
    async with aiohttp.ClientSession() as session_http:
        headers = {'Authorization': f'token {token}'}
        async with session_http.get('https://api.github.com/user', headers=headers) as resp:
            if resp.status != 200:
                return jsonify({'error': 'Invalid token'}), 401

            user_data = await resp.json()

    # Store token in session (in production, use secure storage)
    session['github_token'] = token
    session['github_username'] = user_data['login']

    return jsonify({
        'success': True,
        'username': user_data['login']
    })

@github_bp.route('/api/github/repos', methods=['GET'])
@login_required
async def list_repos():
    """List user's GitHub repositories"""
    token = session.get('github_token')
    if not token:
        return jsonify({'error': 'GitHub not connected'}), 401

    async with aiohttp.ClientSession() as session_http:
        headers = {'Authorization': f'token {token}'}
        async with session_http.get('https://api.github.com/user/repos?per_page=100', headers=headers) as resp:
            if resp.status != 200:
                return jsonify({'error': 'Failed to fetch repos'}), 500

            repos = await resp.json()

    return jsonify({
        'repos': [{'name': r['full_name'], 'default_branch': r['default_branch']} for r in repos]
    })

@github_bp.route('/api/github/repo/<path:repo_path>/files', methods=['GET'])
@login_required
async def list_repo_files(repo_path):
    """List files in a repository"""
    token = session.get('github_token')
    if not token:
        return jsonify({'error': 'GitHub not connected'}), 401

    path = request.args.get('path', '')

    async with aiohttp.ClientSession() as session_http:
        headers = {'Authorization': f'token {token}'}
        url = f'https://api.github.com/repos/{repo_path}/contents/{path}'

        async with session_http.get(url, headers=headers) as resp:
            if resp.status != 200:
                return jsonify({'error': 'Failed to fetch files'}), 500

            files = await resp.json()

    return jsonify({
        'files': [{'name': f['name'], 'type': f['type'], 'path': f['path']} for f in files]
    })

@github_bp.route('/api/github/repo/<path:repo_path>/file', methods=['GET'])
@login_required
async def get_file_content(repo_path):
    """Get content of a specific file"""
    token = session.get('github_token')
    if not token:
        return jsonify({'error': 'GitHub not connected'}), 401

    file_path = request.args.get('path')
    if not file_path:
        return jsonify({'error': 'File path required'}), 400

    async with aiohttp.ClientSession() as session_http:
        headers = {'Authorization': f'token {token}'}
        url = f'https://api.github.com/repos/{repo_path}/contents/{file_path}'

        async with session_http.get(url, headers=headers) as resp:
            if resp.status != 200:
                return jsonify({'error': 'Failed to fetch file'}), 500

            data = await resp.json()

            # Decode base64 content
            content = base64.b64decode(data['content']).decode('utf-8')

    return jsonify({
        'content': content,
        'name': data['name'],
        'path': data['path']
    })

@github_bp.route('/api/github/disconnect', methods=['POST'])
@login_required
async def disconnect_github():
    """Remove GitHub connection"""
    session.pop('github_token', None)
    session.pop('github_username', None)
    return jsonify({'success': True})