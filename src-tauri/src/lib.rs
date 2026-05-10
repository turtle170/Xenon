pub mod python_env;
pub mod context_translator;
pub mod ai_core;
pub mod vm_manager;

use std::sync::Arc;
use tauri::{State};
use crate::ai_core::AgentConfig;
use crate::vm_manager::VmManager;

#[tauri::command]
async fn ask_xenon(app: tauri::AppHandle, prompt: String, config: AgentConfig, vm_manager: State<'_, Arc<VmManager>>) -> Result<String, String> {
    let agent = ai_core::XenonAgent::new(config);
    agent.process(&app, &prompt, &vm_manager).await.map_err(|e| e.to_string())
}

#[tauri::command]
fn request_vm_burst(cpu: i32, ram: i32, duration: u64, vm_manager: State<'_, Arc<VmManager>>) -> Result<(), String> {
    vm_manager.request_allocation(cpu, ram, duration);
    Ok(())
}

#[tauri::command]
fn init_xenon_env() -> Result<Option<AgentConfig>, String> {
    python_env::init_python().map_err(|e| e.to_string())?;
    
    if let Ok(config_str) = std::fs::read_to_string("config.json") {
        if let Ok(config) = serde_json::from_str::<AgentConfig>(&config_str) {
            return Ok(Some(config));
        }
    }
    Ok(None)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let vm_manager = Arc::new(VmManager::new("XenonVM".to_string()));
    vm_manager.clone().start_monitoring();

    tauri::Builder::default()
        .manage(vm_manager)
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_fs::init())
        .invoke_handler(tauri::generate_handler![ask_xenon, init_xenon_env, request_vm_burst])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
