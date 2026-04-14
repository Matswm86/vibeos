// Vibbey — Three.js scene + chat UI
// MVP: load clippy.glb, idle bob animation via root transform, chat bubble
// wired to /api/chat proxy. The GLB has zero baked clips, so we animate the
// root node directly. Bone animations are v0.5 work.

import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

window.__vibbeyAlive = true;

const statusEl = document.getElementById('status');
const bubbleEl = document.getElementById('speech-bubble');
const bubbleText = document.getElementById('bubble-text');
const inputEl = document.getElementById('chat-input');
const sendEl = document.getElementById('chat-send');
const canvas = document.getElementById('scene');
const aboutLink = document.getElementById('about-link');
const aboutModal = document.getElementById('about-modal');
const aboutClose = document.getElementById('about-close');
const installBtn = document.getElementById('install-btn');
const container = document.getElementById('scene-container');

// ── Scene setup ────────────────────────────────────────────
const scene = new THREE.Scene();
scene.background = null; // transparent — CSS grid shows through

const camera = new THREE.PerspectiveCamera(
  45,
  container.clientWidth / container.clientHeight,
  0.1,
  100,
);
camera.position.set(0, 1.5, 3.2);
camera.lookAt(0, 1.35, 0);

const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true });
renderer.setSize(container.clientWidth, container.clientHeight);
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));

// ── Lighting — neon rim lights on a flat-shaded model ─────
const ambient = new THREE.AmbientLight(0x6a4a8f, 0.55);
scene.add(ambient);

const magentaLight = new THREE.DirectionalLight(0xff2ecf, 1.15);
magentaLight.position.set(-2.5, 3, 2);
scene.add(magentaLight);

const cyanLight = new THREE.DirectionalLight(0x01f9ff, 0.95);
cyanLight.position.set(2.5, 1, 2);
scene.add(cyanLight);

const topFill = new THREE.DirectionalLight(0xffffff, 0.28);
topFill.position.set(0, 5, 1);
scene.add(topFill);

// ── Model load ─────────────────────────────────────────────
let clippyRoot = null;
let clippyBaseY = 0;
const VIBBEY_LIFT = 0.55;
const loader = new GLTFLoader();

loader.load(
  '/clippy.glb',
  (gltf) => {
    clippyRoot = gltf.scene;

    const box = new THREE.Box3().setFromObject(clippyRoot);
    const size = box.getSize(new THREE.Vector3());
    const center = box.getCenter(new THREE.Vector3());
    const maxDim = Math.max(size.x, size.y, size.z);
    const targetHeight = 2.0;
    const scale = targetHeight / maxDim;

    clippyRoot.scale.setScalar(scale);
    clippyRoot.position.x -= center.x * scale;
    clippyRoot.position.y -= center.y * scale - targetHeight / 2 - VIBBEY_LIFT;
    clippyRoot.position.z -= center.z * scale;

    clippyBaseY = clippyRoot.position.y;
    scene.add(clippyRoot);

    statusEl.textContent = 'online';
    statusEl.classList.add('online');
    showBubble(
      "Hi! I'm Vibbey, your nostalgic local-AI guide. " +
      "Looks like you're almost set up — want the 2-minute tour?"
    );
  },
  undefined,
  (err) => {
    console.error('[vibbey] GLB load failed', err);
    statusEl.textContent = 'model failed to load';
    statusEl.classList.add('error');
    showBubble(
      "I couldn't load my 3D model. Check that clippy.glb is installed " +
      "at /usr/share/vibeos/vibbey/static/clippy.glb and try again."
    );
  },
);

// ── Idle animation ────────────────────────────────────────
const clock = new THREE.Clock();

function animate() {
  requestAnimationFrame(animate);
  const t = clock.getElapsedTime();
  if (clippyRoot) {
    clippyRoot.position.y = clippyBaseY + Math.sin(t * 1.2) * 0.045;
    clippyRoot.rotation.y = Math.sin(t * 0.55) * 0.18;
    clippyRoot.rotation.z = Math.sin(t * 0.9) * 0.03;
  }
  renderer.render(scene, camera);
}
animate();

// ── Resize handling ────────────────────────────────────────
window.addEventListener('resize', () => {
  const w = container.clientWidth;
  const h = container.clientHeight;
  camera.aspect = w / h;
  camera.updateProjectionMatrix();
  renderer.setSize(w, h);
});

// ── Chat UI ────────────────────────────────────────────────
function showBubble(text) {
  bubbleText.textContent = text;
  bubbleEl.classList.remove('hidden');
}

const SYSTEM_PROMPT = (
  "You are Vibbey, VibeOS's friendly Clippy-lineage Linux assistant. " +
  "You are not Claude. Claude Code takes over after onboarding. Keep replies " +
  "to 2-3 sentences. Be warm, slightly cheeky, never corporate. Never use " +
  "walls of text. When you want to run a system command, include " +
  "[[RUN: tool_id]] or [[RUN: tool_id arg]] on its own line in your reply — " +
  "the UI will ask the user to confirm before executing."
);

// ── Config + tier detection ─────────────────────────────────
// Fetched on load from /api/config: active model name from vibbey.conf.
// Also fetched from /api/tier: backend tier + tool list.
let ACTIVE_MODEL = 'qwen2.5:3b';  // updated by detectConfig()
let ACTIVE_TIER = 'unknown';
let AVAILABLE_TOOLS = new Map();

async function detectConfig() {
  try {
    const resp = await fetch('/api/config');
    if (!resp.ok) return;
    const data = await resp.json();
    if (data.model) ACTIVE_MODEL = data.model;
    ACTIVE_TIER = data.tier || 'unknown';
    console.log(`[vibbey] config model=${ACTIVE_MODEL} tier=${ACTIVE_TIER}`);
  } catch (e) {
    console.warn('[vibbey] config detect failed', e);
  }
}

async function detectTier() {
  try {
    const resp = await fetch('/api/tier');
    if (!resp.ok) return;
    const data = await resp.json();
    ACTIVE_TIER = data.tier || ACTIVE_TIER;
    AVAILABLE_TOOLS = new Map((data.tools || []).map((t) => [t.id, t]));
    const groqModel = data.default_groq_model || 'llama-3.3-70b';
    const tierLabel = {
      byo_key: `groq · ${groqModel}`,
      bootstrap: `groq · bootstrap`,
      ollama: `ollama · ${ACTIVE_MODEL}`,
      unknown: 'detecting…',
    }[ACTIVE_TIER] || ACTIVE_TIER;
    if (statusEl) {
      statusEl.textContent = `online · ${tierLabel}`;
    }
    console.log(`[vibbey] tier=${ACTIVE_TIER}, ${AVAILABLE_TOOLS.size} tools available`);
  } catch (e) {
    console.warn('[vibbey] tier detect failed', e);
  }
}

// ── Model auto-detect (Ollama) ─────────────────────────────
// Verifies the server-configured model is actually pulled in Ollama.
// Falls back to the first available chat model if not.
const EMBED_MARKERS = ['bge-', 'embed', 'nomic-embed'];

function isChatCapable(name) {
  const lower = (name || '').toLowerCase();
  return !EMBED_MARKERS.some((marker) => lower.includes(marker));
}

async function detectModel() {
  try {
    const resp = await fetch('/api/models');
    if (!resp.ok) {
      console.warn('[vibbey] /api/models returned', resp.status);
      return;
    }
    const data = await resp.json();
    const models = data.models || [];
    const chatModels = models.filter((m) => isChatCapable(m.name));
    if (chatModels.length === 0) {
      console.warn('[vibbey] no chat-capable models pulled — chat will fail');
      return;
    }
    // Prefer the server-configured model; fall back to first available.
    const preferred = chatModels.find((m) => m.name === ACTIVE_MODEL);
    ACTIVE_MODEL = (preferred || chatModels[0]).name;
    console.log(`[vibbey] using ollama model: ${ACTIVE_MODEL}`);
    if (ACTIVE_TIER === 'ollama' && statusEl.classList.contains('online')) {
      statusEl.textContent = `online · ollama · ${ACTIVE_MODEL}`;
    }
  } catch (e) {
    console.warn('[vibbey] model detect failed, using configured model', e);
  }
}

// Run startup detections in order: config → tier → model
detectConfig().then(() => detectTier()).then(() => detectModel());

// ── Tool-use marker parsing ────────────────────────────────
const RUN_MARKER_RE = /\[\[RUN:\s*([a-z_][a-z0-9_]*)(?:\s+([^\]]+?))?\s*\]\]/i;

function parseRunMarker(text) {
  const m = RUN_MARKER_RE.exec(text);
  if (!m) return null;
  const toolId = m[1];
  const arg = m[2] ? m[2].trim() : null;
  return {
    toolId,
    arg,
    match: m[0],
    cleanText: text.replace(m[0], '').trim(),
  };
}

async function runTool(toolId, arg) {
  const resp = await fetch('/api/run', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ tool_id: toolId, arg }),
  });
  return await resp.json();
}

function formatToolResult(result) {
  if (result.error) {
    return `[[RESULT: error=${result.error} detail=${result.detail || '?'}]]`;
  }
  const stdout = (result.stdout || '').trim();
  const stderr = (result.stderr || '').trim();
  const exit = result.exit_code;
  let body = `exit=${exit}`;
  if (stdout) body += `\nstdout:\n${stdout}`;
  if (stderr) body += `\nstderr:\n${stderr}`;
  return `[[RESULT: ${result.tool_id}\n${body}]]`;
}

let PENDING_TOOL = null;

const CONVERSATION = [{ role: 'system', content: SYSTEM_PROMPT }];
const MAX_FRONTEND_HISTORY = 20;

function pushConversation(role, content) {
  CONVERSATION.push({ role, content });
  if (CONVERSATION.length > MAX_FRONTEND_HISTORY + 1) {
    const sys = CONVERSATION[0];
    CONVERSATION.splice(0, CONVERSATION.length - MAX_FRONTEND_HISTORY);
    CONVERSATION.unshift(sys);
  }
}

async function postChat(messages) {
  const resp = await fetch('/api/chat', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: ACTIVE_MODEL, messages }),
  });
  if (!resp.ok) {
    const err = await resp.json().catch(() => ({}));
    const e = new Error(err.detail || err.error || `HTTP ${resp.status}`);
    e.kind = err.error;
    throw e;
  }
  return await resp.json();
}

function describeChatError(e) {
  if (e.kind === 'ollama_unreachable') {
    return 'Ollama is down. Start it with: `ollama serve`';
  }
  if (e.kind === 'ollama_error') {
    let hint = e.message || 'Ollama rejected the request';
    if (hint.includes('not found')) {
      hint += `  (try: \`ollama pull ${ACTIVE_MODEL}\`)`;
    }
    return hint;
  }
  return e.message || 'something broke';
}

async function handleVibbeyReply(data) {
  const reply = (data?.message?.content || '').trim() || '(empty reply)';
  pushConversation('assistant', reply);

  const marker = parseRunMarker(reply);
  if (!marker) {
    showBubble(reply);
    return;
  }

  const tool = AVAILABLE_TOOLS.get(marker.toolId);
  if (!tool) {
    showBubble(
      `${marker.cleanText}\n\n(I wanted to run \`${marker.toolId}\` but it's not in my allowlist.)`
    );
    return;
  }

  PENDING_TOOL = { toolId: marker.toolId, arg: marker.arg, description: tool.description };
  const argSuffix = marker.arg ? ` ${marker.arg}` : '';
  showBubble(
    `${marker.cleanText}\n\n[confirm]: run \`${marker.toolId}${argSuffix}\` ` +
    `(${tool.description})? Reply **y** to run, anything else cancels.`
  );
}

async function sendChat() {
  const msg = inputEl.value.trim();
  if (!msg) return;
  inputEl.value = '';
  sendEl.disabled = true;

  if (PENDING_TOOL) {
    const confirm = /^(y|yes|run|ok|go)$/i.test(msg);
    const pending = PENDING_TOOL;
    PENDING_TOOL = null;

    if (!confirm) {
      pushConversation('user', `cancelled: ${pending.toolId}`);
      showBubble(`Cancelled. What else can I help with?`);
      sendEl.disabled = false;
      inputEl.focus();
      return;
    }

    showBubble(`Running \`${pending.toolId}\`…`);
    try {
      const result = await runTool(pending.toolId, pending.arg);
      const formatted = formatToolResult(result);
      pushConversation('user', formatted);

      showBubble('…');
      const next = await postChat(CONVERSATION);
      await handleVibbeyReply(next);
    } catch (e) {
      showBubble(`Tool run failed: ${e.message}`);
    } finally {
      sendEl.disabled = false;
      inputEl.focus();
    }
    return;
  }

  pushConversation('user', msg);
  showBubble('…');
  try {
    const data = await postChat(CONVERSATION);
    await handleVibbeyReply(data);
  } catch (e) {
    showBubble(`Hmm, ${describeChatError(e)}`);
  } finally {
    sendEl.disabled = false;
    inputEl.focus();
  }
}

sendEl.addEventListener('click', sendChat);
inputEl.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') sendChat();
});

// ── About modal ────────────────────────────────────────────
aboutLink.addEventListener('click', () => {
  aboutModal.classList.remove('hidden');
});
aboutClose.addEventListener('click', () => {
  aboutModal.classList.add('hidden');
});
aboutModal.addEventListener('click', (e) => {
  if (e.target === aboutModal) aboutModal.classList.add('hidden');
});

// ── Install button (live-session overlay) ─────────────────
async function detectLiveSession() {
  try {
    const r = await fetch('/api/run', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ tool_id: 'is_live_session' }),
    });
    const data = await r.json();
    if (data.exit_code === 0) {
      installBtn.classList.remove('hidden');
      setTimeout(() => {
        if (clippyRoot) {
          showBubble(
            "Hi! Looks like you're trying VibeOS from the live USB. " +
            "When you're ready to install on this machine, click the " +
            "yellow Install VibeOS button up top. I'll walk you through it."
          );
        }
      }, 500);
    }
  } catch (e) {
    console.warn('[vibbey] live-session detect failed', e);
  }
}
detectLiveSession();

installBtn.addEventListener('click', async () => {
  const ok = window.confirm(
    "Launch the VibeOS installer?\n\n" +
    "Calamares will open and walk you through partitioning, user setup, " +
    "and copying VibeOS to your disk. This is reversible until the final " +
    "Install button inside Calamares.\n\n" +
    "I'll stay open here in case you need help."
  );
  if (!ok) return;
  installBtn.disabled = true;
  installBtn.textContent = 'Launching…';
  try {
    const r = await fetch('/api/run', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ tool_id: 'install_vibeos' }),
    });
    const data = await r.json();
    if (data.error) {
      showBubble(`Couldn't launch installer: ${data.detail || data.error}`);
      installBtn.disabled = false;
      installBtn.textContent = 'Install VibeOS';
    } else {
      showBubble(
        "Installer launched! It'll ask for your password (use the live " +
        "session password, usually blank or 'vibeos'). Pick the disk, " +
        "set a username, and I'll be here if you get stuck."
      );
      installBtn.textContent = 'Installer running';
    }
  } catch (e) {
    showBubble(`Launch failed: ${e.message}`);
    installBtn.disabled = false;
    installBtn.textContent = 'Install VibeOS';
  }
});
