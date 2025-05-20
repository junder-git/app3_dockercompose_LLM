#!/usr/bin/env python3
"""
GitHub Connector for DeepSeek-Coder
This module provides functionality to connect to GitHub, fetch repositories and files,
and process them for use with the DeepSeek-Coder LLM.
"""

import os
import re
import json
import base64
import tempfile
import asyncio
import logging
from typing import Dict, List, Optional, Tuple, Union
from urllib.parse import urlparse, unquote

import aiofiles
import httpx
from github import Github, GithubException
from git import Repo, GitCommandError

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("github_connector")

# File extensions to consider as code files
CODE_EXTENSIONS = {
    '.py': 'python',
    '.js': 'javascript',
    '.jsx': 'javascript',
    '.ts': 'typescript',
    '.tsx': 'typescript',
    '.html': 'html',
    '.css': 'css',
    '.scss': 'scss',
    '.java': 'java',
    '.c': 'c',
    '.cpp': 'cpp',
    '.h': 'c',
    '.hpp': 'cpp',
    '.cs': 'csharp',
    '.go': 'go',
    '.rs': 'rust',
    '.rb': 'ruby',
    '.php': 'php',
    '.swift': 'swift',
    '.kt': 'kotlin',
    '.scala': 'scala',
    '.sh': 'bash',
    '.sql': 'sql',
    '.json': 'json',
    '.xml': 'xml',
    '.yaml': 'yaml',
    '.yml': 'yaml',
    '.md': 'markdown',
    '.txt': 'text'
}

# Files to ignore for LLM analysis
IGNORE_PATTERNS = [
    r'\.git/',
    r'node_modules/',
    r'__pycache__/',
    r'\.venv/',
    r'venv/',
    r'\.env',
    r'\.pyc$',
    r'\.pyo$',
    r'\.so$',
    r'\.o$',
    r'\.a$',
    r'\.lib$',
    r'\.dll$',
    r'\.exe$',
    r'\.bin$',
    r'\.obj$',
    r'\.out$',
    r'\.class$',
    r'\.jar$',
    r'\.jpg$',
    r'\.jpeg$',
    r'\.png$',
    r'\.gif$',
    r'\.bmp$',
    r'\.svg$',
    r'\.ico$',
    r'\.pdf$',
    r'\.zip$',
    r'\.tar$',
    r'\.gz$',
    r'\.rar$',
    r'\.7z$'
]

# Maximum file size to process (in bytes)
MAX_FILE_SIZE = 1024 * 1024  # 1MB

class GithubConnector:
    """
    GitHub Connector for DeepSeek-Coder
    Handles fetching and processing code from GitHub repositories and files
    """
    
    def __init__(self, access_token: Optional[str] = None):
        """
        Initialize GitHub connector
        
        Args:
            access_token: GitHub personal access token for authentication (optional)
        """
        self.access_token = access_token
        self.github = Github(access_token) if access_token else Github()
        self.temp_dir = tempfile.mkdtemp(prefix="deepseek_github_")
        
    async def parse_github_url(self, url: str) -> Dict:
        """
        Parse a GitHub URL to extract repository, file path, and other information
        
        Args:
            url: GitHub URL to parse
            
        Returns:
            Dictionary with parsed information
        """
        parsed_url = urlparse(url)
        
        if 'github.com' not in parsed_url.netloc:
            raise ValueError("Not a valid GitHub URL")
        
        path_parts = [p for p in parsed_url.path.split('/') if p]
        
        if len(path_parts) < 2:
            raise ValueError("Invalid GitHub URL: missing owner or repository")
        
        owner = path_parts[0]
        repo_name = path_parts[1]
        
        result = {
            "owner": owner,
            "repo": repo_name,
            "type": "repository",
            "url": url,
            "branch": "main"  # Default branch
        }
        
        # Check if there's a specific branch, file or directory specified
        if len(path_parts) > 3 and path_parts[2] in ('blob', 'tree'):
            result["branch"] = path_parts[3]
            
            if path_parts[2] == 'blob':
                result["type"] = "file"
                result["file_path"] = '/'.join(path_parts[4:])
            elif path_parts[2] == 'tree':
                result["type"] = "directory"
                result["dir_path"] = '/'.join(path_parts[4:])
        
        return result
    
    async def fetch_repository(self, owner: str, repo_name: str, 
                              branch: Optional[str] = None, 
                              path: Optional[str] = None) -> Dict:
        """
        Fetch repository or specific path within a repository
        
        Args:
            owner: Repository owner
            repo_name: Repository name
            branch: Branch name (optional)
            path: Path within repository (optional)
            
        Returns:
            Dictionary with repository information and content
        """
        try:
            repo = self.github.get_repo(f"{owner}/{repo_name}")
            
            # If no branch specified, use default branch
            if not branch:
                branch = repo.default_branch
            
            result = {
                "owner": owner,
                "repo": repo_name,
                "description": repo.description,
                "stars": repo.stargazers_count,
                "forks": repo.forks_count,
                "branch": branch,
                "content": {}
            }
            
            # If path is specified, fetch only that path
            if path:
                try:
                    content = repo.get_contents(path, ref=branch)
                    if isinstance(content, list):  # It's a directory
                        result["content"] = await self._process_directory_contents(repo, content, branch)
                    else:  # It's a file
                        file_content = await self._get_file_content(repo, content, branch)
                        if file_content:
                            result["content"] = {path: file_content}
                except GithubException as e:
                    logger.error(f"Error fetching path {path}: {e}")
                    result["error"] = f"Error fetching path: {str(e)}"
            else:
                # Fetch the repository structure
                try:
                    contents = repo.get_contents("", ref=branch)
                    result["content"] = await self._process_directory_contents(repo, contents, branch)
                except GithubException as e:
                    logger.error(f"Error fetching repository structure: {e}")
                    result["error"] = f"Error fetching repository: {str(e)}"
            
            return result
            
        except GithubException as e:
            logger.error(f"GitHub API error: {e}")
            raise ValueError(f"GitHub API error: {str(e)}")
    
    async def _process_directory_contents(self, repo, contents, branch):
        """Process and filter contents of a directory"""
        result = {}
        dirs_to_process = []
        
        for content in contents:
            if self._should_ignore(content.path):
                continue
                
            if content.type == "dir":
                dirs_to_process.append(content.path)
            elif content.type == "file":
                file_content = await self._get_file_content(repo, content, branch)
                if file_content:
                    result[content.path] = file_content
        
        # Process subdirectories
        for dir_path in dirs_to_process:
            try:
                subdir_contents = repo.get_contents(dir_path, ref=branch)
                subdir_result = await self._process_directory_contents(repo, subdir_contents, branch)
                result.update(subdir_result)
            except GithubException as e:
                logger.warning(f"Error processing directory {dir_path}: {e}")
        
        return result
    
    async def _get_file_content(self, repo, content, branch):
        """Get and process file content if it's a relevant code file"""
        # Skip files that are too large
        if content.size > MAX_FILE_SIZE:
            logger.info(f"Skipping large file: {content.path} ({content.size} bytes)")
            return None
        
        # Check if it's a code file we want to process
        _, ext = os.path.splitext(content.path.lower())
        if ext not in CODE_EXTENSIONS:
            return None
            
        try:
            file_content = content.decoded_content.decode('utf-8')
            return {
                "content": file_content,
                "language": CODE_EXTENSIONS.get(ext, "text"),
                "size": content.size,
                "url": content.html_url
            }
        except (UnicodeDecodeError, AttributeError) as e:
            logger.warning(f"Error decoding file {content.path}: {e}")
            return None
    
    def _should_ignore(self, path):
        """Check if a path should be ignored based on patterns"""
        for pattern in IGNORE_PATTERNS:
            if re.search(pattern, path):
                return True
        return False
    
    async def clone_repository(self, owner: str, repo_name: str, 
                             branch: Optional[str] = None) -> str:
        """
        Clone a GitHub repository to local filesystem
        
        Args:
            owner: Repository owner
            repo_name: Repository name
            branch: Branch name (optional)
            
        Returns:
            Path to cloned repository
        """
        repo_url = f"https://github.com/{owner}/{repo_name}.git"
        repo_dir = os.path.join(self.temp_dir, f"{owner}_{repo_name}")
        
        try:
            # Clone the repository
            if self.access_token:
                # Use token in URL for authentication
                auth_url = f"https://{self.access_token}@github.com/{owner}/{repo_name}.git"
                repo = Repo.clone_from(auth_url, repo_dir)
            else:
                repo = Repo.clone_from(repo_url, repo_dir)
            
            # Checkout specific branch if specified
            if branch:
                repo.git.checkout(branch)
                
            logger.info(f"Repository cloned to {repo_dir}")
            return repo_dir
            
        except GitCommandError as e:
            logger.error(f"Git error while cloning repository: {e}")
            raise ValueError(f"Error cloning repository: {str(e)}")
    
    async def fetch_file(self, owner: str, repo_name: str, file_path: str, 
                        branch: Optional[str] = None) -> Dict:
        """
        Fetch a specific file from GitHub
        
        Args:
            owner: Repository owner
            repo_name: Repository name
            file_path: Path to file within repository
            branch: Branch name (optional)
            
        Returns:
            Dictionary with file information and content
        """
        try:
            repo = self.github.get_repo(f"{owner}/{repo_name}")
            
            # If no branch specified, use default branch
            if not branch:
                branch = repo.default_branch
            
            try:
                content = repo.get_contents(file_path, ref=branch)
                
                # Check if it's a code file we want to process
                _, ext = os.path.splitext(file_path.lower())
                language = CODE_EXTENSIONS.get(ext, "text")
                
                if content.size > MAX_FILE_SIZE:
                    return {
                        "error": f"File too large ({content.size} bytes)"
                    }
                
                try:
                    decoded_content = content.decoded_content.decode('utf-8')
                    
                    return {
                        "owner": owner,
                        "repo": repo_name,
                        "file_path": file_path,
                        "branch": branch,
                        "size": content.size,
                        "content": decoded_content,
                        "language": language,
                        "url": content.html_url
                    }
                    
                except UnicodeDecodeError:
                    return {
                        "error": "Cannot decode binary file"
                    }
                    
            except GithubException as e:
                logger.error(f"Error fetching file {file_path}: {e}")
                return {
                    "error": f"Error fetching file: {str(e)}"
                }
                
        except GithubException as e:
            logger.error(f"GitHub API error: {e}")
            raise ValueError(f"GitHub API error: {str(e)}")
    
    async def fetch_from_url(self, url: str, max_files: int = 50) -> Dict:
        """
        Fetch content from a GitHub URL
        
        Args:
            url: GitHub URL
            max_files: Maximum number of files to fetch
            
        Returns:
            Dictionary with fetched content and metadata
        """
        try:
            parsed = await self.parse_github_url(url)
            
            if parsed["type"] == "file":
                return await self.fetch_file(
                    parsed["owner"], 
                    parsed["repo"], 
                    parsed["file_path"], 
                    branch=parsed.get("branch")
                )
            elif parsed["type"] == "directory":
                return await self.fetch_repository(
                    parsed["owner"], 
                    parsed["repo"], 
                    branch=parsed.get("branch"), 
                    path=parsed.get("dir_path", "")
                )
            else:  # Repository
                # Start by fetching basic repository structure
                repo_info = await self.fetch_repository(
                    parsed["owner"], 
                    parsed["repo"], 
                    branch=parsed.get("branch")
                )
                
                # Limit the number of files
                if len(repo_info["content"]) > max_files:
                    # Keep only the first max_files
                    limited_content = {}
                    count = 0
                    for path, content in repo_info["content"].items():
                        limited_content[path] = content
                        count += 1
                        if count >= max_files:
                            break
                    
                    repo_info["content"] = limited_content
                    repo_info["truncated"] = True
                    repo_info["total_files"] = len(repo_info["content"])
                
                return repo_info
                
        except ValueError as e:
            logger.error(f"Error processing GitHub URL {url}: {e}")
            return {
                "error": str(e),
                "url": url
            }
    
    async def get_repository_summary(self, owner: str, repo_name: str) -> Dict:
        """
        Get summary information about a repository
        
        Args:
            owner: Repository owner
            repo_name: Repository name
            
        Returns:
            Dictionary with repository summary information
        """
        try:
            repo = self.github.get_repo(f"{owner}/{repo_name}")
            
            # Count files by language
            language_stats = {}
            try:
                languages = repo.get_languages()
                for lang, bytes_count in languages.items():
                    language_stats[lang] = bytes_count
            except GithubException:
                pass
            
            return {
                "name": repo.name,
                "owner": owner,
                "full_name": repo.full_name,
                "description": repo.description,
                "stars": repo.stargazers_count,
                "forks": repo.forks_count,
                "watchers": repo.watchers_count,
                "default_branch": repo.default_branch,
                "created_at": repo.created_at.isoformat() if repo.created_at else None,
                "updated_at": repo.updated_at.isoformat() if repo.updated_at else None,
                "language": repo.language,
                "languages": language_stats,
                "topics": repo.topics,
                "url": repo.html_url,
                "api_url": repo.url
            }
            
        except GithubException as e:
            logger.error(f"GitHub API error: {e}")
            raise ValueError(f"GitHub API error: {str(e)}")
    
    def cleanup(self):
        """Clean up temporary files"""
        import shutil
        try:
            shutil.rmtree(self.temp_dir)
            logger.info(f"Cleaned up temporary directory: {self.temp_dir}")
        except Exception as e:
            logger.error(f"Error cleaning up temporary directory: {e}")


# HTTP API client for non-authenticated GitHub access
class GithubHttpClient:
    """
    HTTP client for accessing GitHub API and raw content
    Useful for when we don't need authentication or want to avoid rate limits
    """
    
    def __init__(self):
        """Initialize the HTTP client"""
        self.base_api_url = "https://api.github.com"
        self.raw_content_url = "https://raw.githubusercontent.com"
        self.headers = {
            "Accept": "application/vnd.github+json",
            "User-Agent": "DeepSeek-Coder-GitHub-Connector"
        }
    
    async def fetch_repository_info(self, owner: str, repo: str) -> Dict:
        """Fetch repository information using the GitHub API"""
        async with httpx.AsyncClient() as session:
            url = f"{self.base_api_url}/repos/{owner}/{repo}"
            async with session.get(url, headers=self.headers) as response:
                if response.status == 200:
                    return await response.json()
                else:
                    error_text = await response.text()
                    logger.error(f"Error fetching repository info: {error_text}")
                    return {"error": f"Error: {response.status} - {error_text}"}
    
    async def fetch_raw_file(self, owner: str, repo: str, branch: str, file_path: str) -> str:
        """Fetch raw file content from GitHub"""
        async with httpx.AsyncClient() as session:
            url = f"{self.raw_content_url}/{owner}/{repo}/{branch}/{file_path}"
            async with session.get(url, headers=self.headers) as response:
                if response.status == 200:
                    return await response.text()
                else:
                    error_text = await response.text()
                    logger.error(f"Error fetching raw file: {error_text}")
                    return None
    
    async def fetch_directory_contents(self, owner: str, repo: str, path: str = "", branch: str = None) -> List:
        """Fetch directory contents from GitHub API"""
        async with httpx.AsyncClient() as session:
            url = f"{self.base_api_url}/repos/{owner}/{repo}/contents/{path}"
            if branch:
                url += f"?ref={branch}"
                
            async with session.get(url, headers=self.headers) as response:
                if response.status == 200:
                    return await response.json()
                else:
                    error_text = await response.text()
                    logger.error(f"Error fetching directory contents: {error_text}")
                    return []


# Utility functions
async def format_code_for_llm(code_files: Dict[str, Dict], context_limit: int = 8000) -> str:
    """
    Format code files for LLM processing with optional truncation
    
    Args:
        code_files: Dictionary of file paths and their content
        context_limit: Maximum characters for context
        
    Returns:
        Formatted code string for LLM
    """
    result = []
    total_chars = 0
    truncated = False
    
    for file_path, file_info in code_files.items():
        if not isinstance(file_info, dict) or "content" not in file_info:
            continue
            
        content = file_info["content"]
        language = file_info.get("language", "text")
        
        file_text = f"FILE: {file_path}\n"
        file_text += f"LANGUAGE: {language}\n"
        file_text += "CONTENT:\n```" + language + "\n"
        file_text += content + "\n```\n\n"
        
        # Check if we need to truncate
        if total_chars + len(file_text) > context_limit:
            truncated = True
            available_chars = context_limit - total_chars - 100  # Leave room for truncation message
            if available_chars > 200:  # Only add if we can include a meaningful chunk
                truncated_content = content[:available_chars] + "...[truncated]"
                file_text = f"FILE: {file_path}\n"
                file_text += f"LANGUAGE: {language}\n"
                file_text += "CONTENT (truncated):\n```" + language + "\n"
                file_text += truncated_content + "\n```\n\n"
                result.append(file_text)
                total_chars += len(file_text)
            break
        else:
            result.append(file_text)
            total_chars += len(file_text)
    
    if truncated:
        result.append("\n[Content was truncated due to size limitations]\n")
    
    return "".join(result)

async def summarize_repository_for_llm(repo_info: Dict) -> str:
    """
    Create a summary of a repository for LLM context
    
    Args:
        repo_info: Repository information dictionary
        
    Returns:
        Formatted repository summary string
    """
    summary = f"# Repository Summary: {repo_info.get('full_name', '')}\n\n"
    
    # Basic information
    summary += f"- **Description**: {repo_info.get('description', 'No description')}\n"
    summary += f"- **Main Language**: {repo_info.get('language', 'Unknown')}\n"
    summary += f"- **Stars**: {repo_info.get('stars', 0)}\n"
    summary += f"- **Forks**: {repo_info.get('forks', 0)}\n"
    
    # Languages
    if languages := repo_info.get('languages', {}):
        total_bytes = sum(languages.values())
        summary += "\n## Language Distribution:\n"
        for lang, bytes_count in languages.items():
            percentage = (bytes_count / total_bytes) * 100
            summary += f"- {lang}: {percentage:.1f}%\n"
    
    # Topics
    if topics := repo_info.get('topics', []):
        summary += "\n## Topics:\n"
        summary += ", ".join(topics)
        summary += "\n"
    
    # Last update
    if updated_at := repo_info.get('updated_at'):
        summary += f"\nLast updated: {updated_at}\n"
    
    # Repository URL
    summary += f"\nRepository URL: {repo_info.get('url', '')}\n"
    
    return summary