use pyo3::prelude::*;
use std::fs;
use std::path::Path;

pub fn init_python() -> PyResult<()> {
    pyo3::prepare_freethreaded_python();
    Ok(())
}

pub fn save_ai_function(name: &str, code: &str) -> std::io::Result<()> {
    let functions_dir = Path::new("functions");
    if !functions_dir.exists() {
        fs::create_dir_all(functions_dir)?;
    }
    let file_path = functions_dir.join(format!("{}.py", name));
    fs::write(file_path, code)
}

pub fn call_ai_function(name: &str, args: &str) -> PyResult<String> {
    Python::with_gil(|py| {
        let functions_dir = Path::new("functions");
        let script_path = functions_dir.join(format!("{}.py", name));
        let code = fs::read_to_string(script_path)?;
        
        // Load as a module
        let module = PyModule::from_code_bound(py, &code, &format!("{}.py", name), name)?;
        let func = module.getattr("execute")?; // Using 'execute' as standard entry point
        let result: String = func.call1((args,))?.extract()?;
        Ok(result)
    })
}

// Auto-skill saving (Hermes style) would be a higher-level logic 
// that decides when to save a code snippet as a function.
