import subprocess
import json
import time

def execute(args):
    """
    Executes a shell command inside the Hyper-V XenonVM sandbox.
    Automatically starts the VM if it's suspended and manages resource scaling.
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
            
        # 1. Ensure VM is running
        check_cmd = ["powershell", "-Command", "Get-VM -Name XenonVM | Select-Object -ExpandProperty State"]
        state_result = subprocess.run(check_cmd, capture_output=True, text=True)
        state = state_result.stdout.strip()
        
        if "Running" not in state:
            print("Starting XenonVM for execution...")
            subprocess.run(["powershell", "-Command", "Start-VM -Name XenonVM"], check=True)
            # Wait for Guest Services to initialize
            time.sleep(5)
            
        # 2. Execute via PowerShell Direct (Requires Guest Services)
        # Note: We use -Credential if needed, but for sandbox we assume root/local admin access configured in installer
        full_cmd = [
            "powershell", "-Command", 
            f"Invoke-Command -VMName XenonVM -ScriptBlock {{ {cmd} }}"
        ]
        
        result = subprocess.run(
            full_cmd,
            capture_output=True,
            text=True
        )
        
        output = result.stdout + result.stderr
        
        # 3. Resource Scaling: We don't save immediately to allow consecutive commands to be fast.
        # Background management (like auto-save after 5 mins) should be handled by the AI core.
            
        return f"[XenonVM Output]\n{output}"
        
    except Exception as e:
        return f"Error executing command in Hyper-V VM: {str(e)}"
