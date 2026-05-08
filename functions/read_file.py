import os
import json

def execute(args):
    """
    Reads the content of a file.
    Args: JSON string {"path": "file_path"} or plain string "file_path"
    """
    try:
        # Handle both JSON args and plain strings
        try:
            data = json.loads(args)
            path = data.get("path", args)
        except:
            path = args.strip()
            
        if not os.path.exists(path):
            return f"Error: File not found at {path}"
            
        with open(path, 'r', encoding='utf-8') as f:
            content = f.read()
            
        # Truncate if too long to prevent context overflow
        if len(content) > 10000:
            return content[:10000] + "\n...[TRUNCATED]"
        return content
    except Exception as e:
        return f"Error reading file: {str(e)}"
