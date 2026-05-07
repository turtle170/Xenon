import os
import shutil
from pathlib import Path

def execute(args):
    """
    Import browser data from standard locations into a Playwright user data dir.
    Args: 'chrome' or 'edge'
    """
    browser = args.lower()
    app_data = Path(os.getenv('LOCALAPPDATA'))
    
    target_dir = Path("browser_data") / browser
    target_dir.mkdir(parents=True, exist_ok=True)
    
    if browser == "chrome":
        source = app_data / "Google" / "Chrome" / "User Data" / "Default"
    elif browser == "edge":
        source = app_data / "Microsoft" / "Edge" / "User Data" / "Default"
    else:
        return f"Browser {browser} not supported."
        
    if not source.exists():
        return f"Source {source} not found."
        
    # Copy essential files (cookies, history, etc.)
    # This is a simplified version
    essential_files = ["Cookies", "History", "Login Data", "Web Data"]
    for f in essential_files:
        src_file = source / f
        if src_file.exists():
            shutil.copy2(src_file, target_dir / f)
            
    return f"Data imported from {browser} to {target_dir}"
