import json

def execute(args):
    """
    Requests a resource burst for the XenonVM sandbox.
    Args: JSON string {"cpu": 80, "ram": 8, "time": 300}
    """
    try:
        data = json.loads(args)
        cpu = data.get("cpu", 80)
        ram = data.get("ram", 8)
        time = data.get("time", 300)
        
        # This function prints a specific tag that the Rust backend intercepts
        print(f"VMALLOC: {{\"cpu\": {cpu}, \"ram\": {ram}, \"time\": {time}}}")
        return f"Resource burst request sent: {cpu}% CPU, {ram}GB RAM for {time}s."
    except Exception as e:
        return f"Error in vmalloc skill: {str(e)}"
