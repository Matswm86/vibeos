// Vibbey — Three.js scene + chat UI
// MVP: load clippy.glb, idle bob animation via root transform, chat bubble
// wired to /api/chat proxy. The GLB has zero baked clips, so we animate the
// root node directly. Bone animations are v0.5 work.

import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

const statusEl = document.getElementById('status');
const bubbleEl = document.getElementById('speech-bubble');
const bubbleText = document.getElementById('bubble-text');
const inputEl = document.getElementById('chat-input');
const sendEl = document.getElementById('chat-send');
const canvas = document.getElementById('scene');
const aboutLink = document.getElementById('about-link');
const aboutModal = document.getElementById('about-modal');
const aboutClose = document.getElementById('about-close');
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
// The model has no textures; we lean into it with bold magenta + cyan
// directional lights so the result reads as "neon statue."
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
// Captured at load time so the idle animation can bob around a stable anchor
// instead of clobbering the hand-placed Y coordinate every frame.
let clippyBaseY = 0;

// Vibbey's vertical offset in world space. Positive = floats higher in the
// view, keeping her head up in the 3D scene and away from the text panel.
const VIBBEY_LIFT = 0.55;

const loader = new GLTFLoader();

loader.load(
  '/clippy.glb',
  (gltf) => {
    clippyRoot = gltf.scene;

    // Center + scale to a known frame so different source models behave.
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
      "I couldn't load my 3D model. Check that clippy.glb exists at " +
      "projects/vibeos/clippy.glb and try again."
    );
  },
);

// ── Idle animation ────────────────────────────────────────
// Root-transform only. Gentle bob + sway + micro-tilt. No bones.
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
// Bubble is always in flow under the 3D scene; we just swap the text.
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

// ── Tier detection + tool registry ─────────────────────────
// Fetched on load from /api/tier: current backend (byo_key/bootstrap/ollama)
// + list of allowlisted tools. Used for the status footer + confirming
// [[RUN: ...]] markers against the real allowlist before prompting the user.
let ACTIVE_TIER = 'unknown';
let AVAILABLE_TOOLS = new Map();  // id → {description, accepts_arg}

async function detectTier() {
  try {
    const resp = await fetch('/api/tier');
    if (!resp.ok) return;
    const data = await resp.json();
    ACTIVE_TIER = data.tier || 'unknown';
    AVAILABLE_TOOLS = new Map((data.tools || []).map((t) => [t.id, t]));
    const tierLabel = {
      byo_key: `groq · ${data.default_groq_model || 'llama-3.3-70b'}`,
      bootstrap: `groq · bootstrap`,
      ollama: `ollama · local`,
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

detectTier();

// ── Model auto-detect ──────────────────────────────────────
// Ollama fallback model selection. Used for the `model` field in /api/chat
// payloads; the server ignores it when Groq is active. Fresh VibeOS ISOs
// pull gemma3:4b via install.sh; dev workstations often have others.
let ACTIVE_MODEL = 'gemma3:4b';
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
    // Prefer gemma3:4b if present (matches install.sh default), else first.
    const gemma = chatModels.find((m) => (m.name || '').startsWith('gemma3'));
    ACTIVE_MODEL = (gemma || chatModels[0]).name;
    console.log(`[vibbey] using model: ${ACTIVE_MODEL}`);
    if (statusEl.classList.contains('online')) {
      statusEl.textContent = `online · ${ACTIVE_MODEL}`;
    }
  } catch (e) {
    console.warn('[vibbey] model detect failed, using fallback', e);
  }
}

detectModel();

// ── Tool-use marker parsing ────────────────────────────────
// Vibbey signals command execution by embedding [[RUN: tool_id]] or
// [[RUN: tool_id arg]] in her reply. We extract the first marker, strip it
// from the visible text, and prompt the user for confirmation before
// actually running it via /api/run.
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

// Pending tool confirmation — set when Vibbey asks to run something,
// consumed by the chat input's "yes" / "run" response.
let PENDING_TOOL = null;

// Rolling conversation history on the frontend — so tool-use results can
// feed back into the next /api/chat call as a user message. Capped at ~20
// entries to avoid sending huge histories; server memory handles long-term
// persistence across sessions.
const CONVERSATION = [{ role: 'system', content: SYSTEM_PROMPT }];
const MAX_FRONTEND_HISTORY = 20;

function pushConversation(role, content) {
  CONVERSATION.push({ role, content });
  // Keep system message + last N turns
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
    // Vibbey hallucinated a tool that's not in the allowlist — show the
    // clean text and a short warning so the user knows.
    showBubble(
      `${marker.cleanText}\n\n(I wanted to run \`${marker.toolId}\` but it's not in my allowlist.)`
    );
    return;
  }

  // Stage the confirmation. Vibbey says what she wants to run, input field
  // gets repurposed to "y / yes / run" = go, anything else = cancel.
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

  // Confirmation for a pending tool execution
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

      // Feed the result back to Vibbey for interpretation
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

  // Normal chat turn
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
