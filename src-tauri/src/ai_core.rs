use crate::python_env;
use crate::context_translator;
use serde::{Deserialize, Serialize};
use reqwest::Client;
use serde_json::json;

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

    pub async fn process(&self, prompt: &str) -> anyhow::Result<String> {
        let system_prompt = "You are Xenon. Direct. Autonomous. No slack. \
            If you need a tool you don't have, output CODE: <python code> to create it. \
            Always define an 'execute(args)' function in your code. \
            Otherwise, answer directly.";

        let url = match self.config.provider.as_str() {
            "OpenAI" => "https://api.openai.com/v1/chat/completions",
            "DeepSeek" => "https://api.deepseek.com/chat/completions",
            "Llama (Local)" => &self.config.local_server.clone().unwrap_or("http://localhost:8080/v1/chat/completions".to_string()),
            _ => "https://api.openai.com/v1/chat/completions", // Default fallback
        };

        let api_key = self.config.api_key.clone().unwrap_or_default();

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

        let res_json: serde_json::Value = response.json().await?;
        let content = res_json["choices"][0]["message"]["content"].as_str().unwrap_or("No response").to_string();

        if content.contains("CODE:") {
            // Basic parsing of code
            let code = content.split("CODE:").nth(1).unwrap_or("").trim();
            let skill_name = format!("skill_{}", uuid::Uuid::new_v4().simple());
            python_env::save_ai_function(&skill_name, code)?;
            
            // Execute the newly created skill
            let result = python_env::call_ai_function(&skill_name, prompt).map_err(|e| anyhow::anyhow!(e))?;
            return Ok(format!("[Skill Created: {}]\n{}", skill_name, result));
        }

        Ok(content)
    }
}
