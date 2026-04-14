# Troubleshooting — common first-run friction

Vibbey should recognize these symptoms and guide the user to the fix.

## "Claude Code isn't responding / says not authenticated"

Run `claude auth login` in a terminal. It'll open a browser for Anthropic sign-in. After auth, `claude --version` should report the version without errors.

## "Ollama is down / chat doesn't work locally"

```bash
systemctl status ollama   # check the service
systemctl restart ollama  # restart if dead
ollama list               # see pulled models
ollama pull gemma3:4b     # if no models, pull the default
```

## "Docker says permission denied"

You need to be in the `docker` group. Run:
```bash
sudo usermod -aG docker $USER
```
Then **log out and log back in** (or reboot). The group change doesn't apply to the current session.

## "GitHub CLI says not authenticated"

```bash
gh auth login
```
Follow the prompts — choose GitHub.com, HTTPS, "Login with web browser." Paste the one-time code when asked.

## "Vibbey is slow to respond"

By default Vibbey uses Groq (cloud, fast) with Ollama fallback (local, slower). If Groq is down or your bootstrap token is burned, she falls back to local Ollama which is slower. Options:
- **Get your own free Groq key** at console.groq.com/keys, paste into Vibbey's chat when she asks
- **Wait for the local model** — it's slower but private
- **Pull a smaller model**: `ollama pull gemma3:4b` (2.6 GB, fastest)

## "I don't see Vibbey / she's not in the corner"

The autostart fires on first login only. To re-trigger:
```bash
rm ~/.vibeos/first-run-complete
# Then log out + log back in, OR run manually:
python3 -m clippy
```

## "Vibbey can't find the model / '404 model not found'"

```bash
ollama list                       # see what's pulled
ollama pull gemma3:4b             # pull the default
# Then refresh Vibbey's chat — she auto-detects available models
```

## "Low disk space"

```bash
df -h ~                           # check
docker system prune -a            # clean Docker (careful: wipes unused images)
ollama list                       # see models
ollama rm <model-name>            # remove a model you don't use
```

## "How do I update VibeOS / Claude / Ollama?"

```bash
# System packages
sudo apt update && sudo apt upgrade -y

# Claude Code
npm install -g @anthropic-ai/claude-code@latest

# Ollama (self-updating script)
curl -fsSL https://ollama.com/install.sh | sh
```

## "Firefox / my browser won't launch from Vibbey"

Vibbey opens URLs via `xdg-open`. If that's misconfigured:
```bash
xdg-mime default firefox.desktop x-scheme-handler/http
xdg-mime default firefox.desktop x-scheme-handler/https
```

## Emergency escape

If Vibbey is stuck or broken, you can always:
- Close the widget (click the chat pill's close area or kill `python3 -m clippy`)
- Delete the first-run marker to re-trigger: `rm ~/.vibeos/first-run-complete`
- Reinstall from scratch: `bash <(curl -fsSL https://vibeos.dev/install.sh)` (or wherever the install script lives)
