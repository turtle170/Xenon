import os
import json

def execute(args):
    """
    Writes content to a file.
    Args: JSON string {"path": "file_path", "content": "file_content"}
    """
    try:
        data = json.loads(args)
        path = data.get("path")
        content = data.get("content")
        
        if not path or content is None:
            return "Error: Missing 'path' or 'content' in JSON arguments."
            
        # Ensure directory exists
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
            
        with open(path, 'w', encoding='utf-8') as f:
            f.write(content)
            
        return f"Successfully wrote to {path}"
    except json.JSONDecodeError:
        return "Error: Arguments must be a valid JSON object with 'path' and 'content'."
    except Exception as e:
        return f"Error writing file: {str(e)}"
