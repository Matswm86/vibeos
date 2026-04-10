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
camera.position.set(0, 1.2, 3.2);
camera.lookAt(0, 1, 0);

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
    clippyRoot.position.y -= center.y * scale - targetHeight / 2;
    clippyRoot.position.z -= center.z * scale;

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
    clippyRoot.position.y = -0.05 + Math.sin(t * 1.2) * 0.045;
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
  "You run locally via Ollama. You are not Claude. Claude Code takes over " +
  "after onboarding. Keep replies to 2-3 sentences. Be warm, slightly cheeky, " +
  "never play corporate. Never use walls of text."
);

async function sendChat() {
  const msg = inputEl.value.trim();
  if (!msg) return;
  inputEl.value = '';
  sendEl.disabled = true;
  showBubble('…');

  try {
    const resp = await fetch('/api/chat', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: 'gemma3:4b',
        messages: [
          { role: 'system', content: SYSTEM_PROMPT },
          { role: 'user', content: msg },
        ],
      }),
    });

    if (!resp.ok) {
      const err = await resp.json().catch(() => ({}));
      showBubble(
        `Hmm, ${err.error || 'something broke'}. Is Ollama running? Try: ollama serve`
      );
      return;
    }

    const data = await resp.json();
    const reply = data?.message?.content?.trim() || '(empty reply)';
    showBubble(reply);
  } catch (e) {
    showBubble(`Network error: ${e.message}`);
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
