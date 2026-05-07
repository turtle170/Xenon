import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import "./App.css";

interface Message {
  role: "user" | "xenon";
  content: string;
}

function App() {
  const [messages, setMessages] = useState<Message[]>([
    { role: "xenon", content: "Hello. I am Xenon. Direct and autonomous. How can I assist?" }
  ]);
  const [input, setInput] = useState("");

  async function handleSend() {
    if (!input.trim()) return;

    const userMsg: Message = { role: "user", content: input };
    setMessages(prev => [...prev, userMsg]);
    setInput("");

    try {
      const response: string = await invoke("ask_xenon", { prompt: input });
      setMessages(prev => [...prev, { role: "xenon", content: response }]);
    } catch (error) {
      setMessages(prev => [...prev, { role: "xenon", content: "Error: " + error }]);
    }
  }

  return (
    <div className="container">
      <div className="chat-container">
        {messages.map((msg, i) => (
          <div key={i} className={`message ${msg.role}`}>
            {msg.content}
          </div>
        ))}
      </div>
      <div className="input-container">
        <input
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && handleSend()}
          placeholder="Type a message..."
        />
        <button onClick={handleSend}>Send</button>
      </div>
    </div>
  );
}

export default App;
