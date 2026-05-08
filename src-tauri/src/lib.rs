pub mod python_env;
pub mod context_translator;
pub mod ai_core;

use tauri::{AppHandle, Manager, Runtime};
use crate::ai_core::AgentConfig;

#[tauri::command]
async fn ask_xenon(app: tauri::AppHandle, prompt: String, config: AgentConfig) -> Result<String, String> {
    let agent = ai_core::XenonAgent::new(config);
    agent.process(&app, &prompt).await.map_err(|e| e.to_string())
}

#[tauri::command]
fn init_xenon_env() -> Result<Option<AgentConfig>, String> {
    python_env::init_python().map_err(|e| e.to_string())?;
    
    // Attempt to load existing config
    if let Ok(config_str) = std::fs::read_to_string("config.json") {
        if let Ok(config) = serde_json::from_str::<AgentConfig>(&config_str) {
            return Ok(Some(config));
        }
    }
    Ok(None)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_fs::init())
        .invoke_handler(tauri::generate_handler![ask_xenon, init_xenon_env])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
