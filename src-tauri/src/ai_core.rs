use crate::python_env;
use crate::vm_manager::VmManager;
use serde::{Deserialize, Serialize};
use reqwest::Client;
use serde_json::json;
use std::fs;
use std::sync::Arc;
use tauri::{AppHandle, Emitter};

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct AgentConfig {
    pub provider: String,
    pub api_key: Option<String>,
    pub model: String,
    pub local_server: Option<String>,
}

pub struct XenonAgent {
    pub config: AgentConfig,
    pub client: Client,
}

impl XenonAgent {
    pub fn new(config: AgentConfig) -> Self {
        Self {
            config,
            client: Client::new(),
        }
    }

    pub fn from_file() -> anyhow::Result<Self> {
        let config_str = fs::read_to_string("config.json")?;
        let config: AgentConfig = serde_json::from_str(&config_str)?;
        Ok(Self::new(config))
    }

    pub async fn process(&self, app: &AppHandle, prompt: &str, vm_manager: &Arc<VmManager>) -> anyhow::Result<String> {
        let _ = app.emit("agent_activity", format!("Processing user prompt: {}...", &prompt[..std::cmp::min(prompt.len(), 20)]));
        
        let system_prompt = "You are Xenon. Direct. Autonomous. No slack. \
            If you need a tool you don't have, output CODE: <python code> to create it. \
            Always define an 'execute(args)' function in your code. \
            You have standard tools: 'read_file', 'write_file', 'vm_shell', and 'vmalloc'. \
            To request a resource burst for the VM, output VMALLOC: {\"cpu\": 80, \"ram\": 8, \"time\": 300}. \
            You have FULL ROOT ACCESS in the XenonVM (Debian 13) sandbox via 'sudo'. \
            Otherwise, answer directly.";

        let url = match self.config.provider.as_str() {
            "OpenAI" => "https://api.openai.com/v1/chat/completions",
            "Anthropic" => "https://api.anthropic.com/v1/chat/completions",
            "Gemini" => "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
            "DeepSeek" => "https://api.deepseek.com/chat/completions",
            "Llama (Local)" => &self.config.local_server.clone().unwrap_or("http://localhost:8080/v1/chat/completions".to_string()),
            _ => "https://api.openai.com/v1/chat/completions", 
        };

        let api_key = self.config.api_key.clone().unwrap_or_default();
        let _ = app.emit("agent_activity", format!("Querying provider: {}", self.config.provider));

        let response = self.client.post(url)
            .header("Authorization", format!("Bearer {}", api_key))
            .json(&json!({
                "model": self.config.model,
                "messages": [
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": prompt}
                ]
            }))
            .send()
            .await?;

        if !response.status().is_success() {
            let error_text = response.text().await?;
            let _ = app.emit("agent_activity", format!("API Error: {}", error_text));
            return Err(anyhow::anyhow!("API Error: {}", error_text));
        }

        let res_json: serde_json::Value = response.json().await?;
        let content = res_json["choices"][0]["message"]["content"].as_str().unwrap_or("No response").to_string();

        if content.contains("VMALLOC:") {
            let json_str = content.split("VMALLOC:").nth(1).unwrap_or("{}").trim();
            if let Ok(alloc_req) = serde_json::from_str::<serde_json::Value>(json_str) {
                let cpu = alloc_req["cpu"].as_i64().unwrap_or(40) as i32;
                let ram = alloc_req["ram"].as_i64().unwrap_or(4) as i32;
                let time = alloc_req["time"].as_u64().unwrap_or(60);
                
                vm_manager.request_allocation(cpu, ram, time);
                let _ = app.emit("agent_activity", format!("Resource Burst Granted: {}% CPU, {}GB RAM for {}s", cpu, ram, time));
            }
        }

        if content.contains("CODE:") {
            let _ = app.emit("agent_activity", "Analyzing generated code block...".to_string());
            let code = content.split("CODE:").nth(1).unwrap_or("").trim();
            let skill_name = format!("skill_{}", uuid::Uuid::new_v4().simple());
            
            let _ = app.emit("agent_activity", format!("Saving new dynamic skill: {}.py", skill_name));
            python_env::save_ai_function(&skill_name, code)?;
            
            let _ = app.emit("agent_activity", format!("Executing {} within local Sandbox...", skill_name));
            let result = python_env::call_ai_function(&skill_name, prompt).map_err(|e| anyhow::anyhow!(e))?;
            
            let _ = app.emit("agent_activity", "Execution complete.".to_string());
            return Ok(format!("[Skill Created: {}]\n{}", skill_name, result));
        }

        let _ = app.emit("agent_activity", "Response received from LLM.".to_string());
        Ok(content)
    }
}
