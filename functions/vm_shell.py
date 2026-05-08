import subprocess
import json

def execute(args):
    """
    Executes a shell command inside the XenonVM sandbox with full sudo access.
    Args: JSON string {"command": "apt install -y curl"} or plain string.
    """
    try:
        try:
            data = json.loads(args)
            cmd = data.get("command", args)
        except:
            cmd = args.strip()
            
        if not cmd:
            return "Error: No command provided."
            
        # Execute via WSL on the XenonVM instance as user 'xenon'
        # Since we added NOPASSWD:ALL, we can use 'sudo' freely.
        full_cmd = ["wsl", "-d", "XenonVM", "-u", "xenon", "--", "bash", "-c", cmd]
        
        result = subprocess.run(
            full_cmd,
            capture_output=True,
            text=True,
            shell=True # Required for WSL calls on Windows
        )
        
        output = result.stdout + result.stderr
        
        if not output:
            return f"Command executed successfully (no output). Exit code: {result.returncode}"
            
        return f"[Exit Code: {result.returncode}]\n{output}"
        
    except Exception as e:
        return f"Error executing command in VM: {str(e)}"
