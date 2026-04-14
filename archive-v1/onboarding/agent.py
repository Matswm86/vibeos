"""Ollama conversation client — stdlib only, streaming support."""

import json
import sys
import urllib.request
import urllib.error
from dataclasses import dataclass, field

OLLAMA_URL = "http://localhost:11434"
DEFAULT_MODEL = "gemma3:4b"


@dataclass
class OllamaAgent:
    model: str = DEFAULT_MODEL
    system_prompt: str = ""
    history: list = field(default_factory=list)

    def set_system(self, prompt: str) -> None:
        """Set or replace the system prompt."""
        self.system_prompt = prompt

    def chat(self, user_message: str) -> str:
        """Send a message, stream the response, return full text."""
        self.history.append({"role": "user", "content": user_message})

        messages = []
        if self.system_prompt:
            messages.append({"role": "system", "content": self.system_prompt})
        messages.extend(self.history)

        payload = json.dumps({
            "model": self.model,
            "messages": messages,
            "stream": True,
        }).encode()

        req = urllib.request.Request(
            f"{OLLAMA_URL}/api/chat",
            data=payload,
            headers={"Content-Type": "application/json"},
        )

        full_response = []
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                for line in resp:
                    if not line.strip():
                        continue
                    chunk = json.loads(line)
                    if chunk.get("done"):
                        break
                    token = chunk.get("message", {}).get("content", "")
                    if token:
                        sys.stdout.write(token)
                        sys.stdout.flush()
                        full_response.append(token)
        except urllib.error.URLError as e:
            error_msg = f"\n[Ollama error: {e}]"
            sys.stdout.write(error_msg)
            full_response.append(error_msg)

        sys.stdout.write("\n")
        sys.stdout.flush()

        assistant_text = "".join(full_response)
        self.history.append({"role": "assistant", "content": assistant_text})
        return assistant_text

    def generate_no_input(self, context_message: str) -> str:
        """Generate a response from context alone (no user input needed).

        Used for steps where the agent speaks first (welcome, verify, handoff).
        """
        return self.chat(context_message)

    def clear_history(self) -> None:
        """Reset conversation history (system prompt preserved)."""
        self.history.clear()


def check_ollama() -> bool:
    """Check if Ollama is running and responsive."""
    try:
        req = urllib.request.Request(f"{OLLAMA_URL}/api/tags")
        with urllib.request.urlopen(req, timeout=5):
            return True
    except (urllib.error.URLError, OSError):
        return False


def check_model(model: str = DEFAULT_MODEL) -> bool:
    """Check if the specified model is available locally."""
    try:
        req = urllib.request.Request(f"{OLLAMA_URL}/api/tags")
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read())
            names = [m.get("name", "") for m in data.get("models", [])]
            return any(model in name for name in names)
    except (urllib.error.URLError, OSError, json.JSONDecodeError):
        return False
