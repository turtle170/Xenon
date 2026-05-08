import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import "./App.css";

interface Message {
  role: "user" | "xenon";
  content: string;
}

interface AgentConfig {
  provider: string;
  api_key?: string;
  model: string;
  local_server?: string;
}

const PROVIDERS = [
  "OpenAI",
  "Anthropic",
  "Gemini",
  "DeepSeek",
  "Llama (Local)"
];

function App() {
  const [messages, setMessages] = useState<Message[]>([
    { role: "xenon", content: "Hello. I am Xenon. System initialized. Select provider to begin." }
  ]);
  const [input, setInput] = useState("");
  const [config, setConfig] = useState<AgentConfig>({
    provider: "OpenAI",
    model: "gpt-4o",
    api_key: ""
  });
  const [showSettings, setShowSettings] = useState(false);
  const [isLoading, setIsLoading] = useState(false);

  useEffect(() => {
    invoke("init_xenon_env").then((loadedConfig: any) => {
      if (loadedConfig) {
        setConfig(loadedConfig);
        setMessages([{ role: "xenon", content: `System ready. Connected via ${loadedConfig.provider}.` }]);
      }
    }).catch(console.error);
  }, []);

  async function handleSend() {
    if (!input.trim() || isLoading) return;

    const userMsg: Message = { role: "user", content: input };
    setMessages(prev => [...prev, userMsg]);
    setInput("");
    setIsLoading(true);

    try {
      const response: string = await invoke("ask_xenon", { prompt: input, config });
      setMessages(prev => [...prev, { role: "xenon", content: response }]);
    } catch (error) {
      setMessages(prev => [...prev, { role: "xenon", content: "Error: " + error }]);
    } finally {
      setIsLoading(false);
    }
  }

  return (
    <div className="container">
      <div className="sidebar">
        <h2 onClick={() => setShowSettings(!showSettings)}>XENON {showSettings ? "×" : "⚙"}</h2>
        {showSettings && (
          <div className="settings">
            <label>Provider</label>
            <select value={config.provider} onChange={(e) => setConfig({ ...config, provider: e.target.value })}>
              {PROVIDERS.map(p => <option key={p} value={p}>{p}</option>)}
            </select>
            
            <label>Model</label>
            <input value={config.model} onChange={(e) => setConfig({ ...config, model: e.target.value })} />
            
            <label>API Key</label>
            <input type="password" value={config.api_key} onChange={(e) => setConfig({ ...config, api_key: e.target.value })} />
          </div>
        )}
      </div>
      
      <div className="main">
        <div className="chat-container">
          {messages.map((msg, i) => (
            <div key={i} className={`message ${msg.role}`}>
              <div className="label">{msg.role.toUpperCase()}</div>
              <div className="text">{msg.content}</div>
            </div>
          ))}
          {isLoading && <div className="message xenon"><div className="text">Processing...</div></div>}
        </div>
        <div className="input-container">
          <input
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && handleSend()}
            placeholder="Talk to Xenon..."
            disabled={isLoading}
          />
          <button onClick={handleSend} disabled={isLoading}>Send</button>
        </div>
      </div>
    </div>
  );
}

export default App;
