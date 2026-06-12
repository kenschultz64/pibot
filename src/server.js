import express from "express";
import fs from "node:fs";
import path from "node:path";
import {
  AuthStorage,
  createAgentSession,
  ModelRegistry,
  SessionManager,
} from "@earendil-works/pi-coding-agent";

const PORT = Number(process.env.PORT ?? 11435);
const HOST = process.env.HOST ?? "127.0.0.1";
const WORKSPACE = process.env.PI_WORKSPACE ?? process.cwd();
const BRIDGE_API_KEY = process.env.PI_BRIDGE_API_KEY;
const FILE_DOWNLOAD_KEY = process.env.PI_FILE_DOWNLOAD_KEY;
const MODEL_ID = process.env.PI_OPENWEBUI_MODEL ?? "pi-agent";
const PUBLIC_BASE_URL = process.env.PI_PUBLIC_BASE_URL ?? `http://${HOST}:${PORT}`;
const SHOW_PROGRESS = parseBoolean(process.env.PI_SHOW_PROGRESS, true);
const PI_PROVIDER = process.env.PI_PROVIDER;
const PI_MODEL = process.env.PI_MODEL;

// Safe default. To allow editing/executing commands, set:
// PI_TOOLS=read,bash,edit,write,grep,find,ls
const DEFAULT_TOOLS = ["read", "grep", "find", "ls"];
const tools = parseTools(process.env.PI_TOOLS);

const authStorage = AuthStorage.create();
const modelRegistry = ModelRegistry.create(authStorage);
const app = express();

app.use(express.json({ limit: "25mb" }));

app.use((req, res, next) => {
  if (!BRIDGE_API_KEY) return next();
  const token = requestToken(req);
  const isFileDownload = req.path.startsWith("/files/");

  if (token === BRIDGE_API_KEY || (isFileDownload && FILE_DOWNLOAD_KEY && token === FILE_DOWNLOAD_KEY)) {
    return next();
  }

  return res.status(401).json({ error: { message: "Unauthorized" } });
});

app.get("/health", (_req, res) => {
  res.json({ ok: true, workspace: WORKSPACE, tools: tools ?? "default" });
});

app.get(/^\/files\/(.+)$/, (req, res) => {
  const relativePath = decodeURIComponent(req.params[0]);
  const root = path.resolve(WORKSPACE);
  const filePath = path.resolve(root, relativePath);

  if (filePath !== root && !filePath.startsWith(root + path.sep)) {
    return res.status(403).json({ error: { message: "Forbidden path" } });
  }

  res.download(filePath, (error) => {
    if (error && !res.headersSent) {
      res.status(404).json({ error: { message: "File not found" } });
    }
  });
});

app.get("/v1/models", (_req, res) => {
  res.json({
    object: "list",
    data: [
      {
        id: MODEL_ID,
        object: "model",
        created: 0,
        owned_by: "pi",
      },
    ],
  });
});

app.post("/v1/chat/completions", async (req, res) => {
  const body = req.body ?? {};
  const stream = Boolean(body.stream);
  const prompt = messagesToPrompt(body.messages ?? []);

  if (!prompt.trim()) {
    return res.status(400).json({ error: { message: "No prompt provided" } });
  }

  if (stream) return handleStreamingCompletion(req, res, prompt);
  return handleBlockingCompletion(req, res, prompt);
});

// Simple webhook relay for integrations that post `{ message, context }` instead
// of the OpenAI-compatible chat/completions payload.
app.post("/webhook", async (req, res) => {
  const { message, context } = req.body ?? {};
  const prompt = webhookPayloadToPrompt(message, context);

  if (!prompt.trim()) {
    return res.status(400).json({ error: { message: "No message provided" } });
  }

  let session;
  let output = "";

  try {
    ({ session } = await createPiSession());
    session.subscribe((event) => {
      const delta = textDeltaFromEvent(event);
      if (delta) output += delta;
    });

    await session.prompt(prompt);

    res.status(200).json({
      response: output,
      source: "Pi-Core-Relay",
    });
  } catch (error) {
    sendJsonError(res, error);
  } finally {
    session?.dispose?.();
  }
});

async function createPiSession() {
  const model = resolveConfiguredModel();

  return createAgentSession({
    cwd: WORKSPACE,
    sessionManager: SessionManager.inMemory(WORKSPACE),
    authStorage,
    modelRegistry,
    ...(model ? { model } : {}),
    ...(tools ? { tools } : {}),
  });
}

function resolveConfiguredModel() {
  if (!PI_PROVIDER && !PI_MODEL) return undefined;

  let provider = PI_PROVIDER;
  let modelId = PI_MODEL;

  if (!provider && modelId?.includes("/")) {
    const parts = modelId.split("/");
    provider = parts.shift();
    modelId = parts.join("/");
  }

  if (!provider || !modelId) {
    throw new Error("Set both PI_PROVIDER and PI_MODEL, or set PI_MODEL as provider/model-id.");
  }

  const model = modelRegistry.find(provider, modelId);
  if (!model) {
    throw new Error(`Pi model not found: ${provider}/${modelId}`);
  }
  return model;
}

async function handleBlockingCompletion(req, res, prompt) {
  const completionId = `chatcmpl-pi-${Date.now()}`;
  let session;
  let output = "";

  try {
    ({ session } = await createPiSession());
    session.subscribe((event) => {
      const delta = textDeltaFromEvent(event);
      if (delta) output += delta;
    });

    await session.prompt(prompt);

    res.json({
      id: completionId,
      object: "chat.completion",
      created: Math.floor(Date.now() / 1000),
      model: req.body?.model ?? MODEL_ID,
      choices: [
        {
          index: 0,
          message: { role: "assistant", content: output },
          finish_reason: "stop",
        },
      ],
    });
  } catch (error) {
    sendJsonError(res, error);
  } finally {
    session?.dispose?.();
  }
}

async function handleStreamingCompletion(req, res, prompt) {
  const completionId = `chatcmpl-pi-${Date.now()}`;
  let session;

  res.writeHead(200, {
    "Content-Type": "text/event-stream; charset=utf-8",
    "Cache-Control": "no-cache, no-transform",
    Connection: "keep-alive",
    "X-Accel-Buffering": "no",
  });

  const writeSse = (data) => res.write(`data: ${JSON.stringify(data)}\n\n`);
  const model = req.body?.model ?? MODEL_ID;

  writeSse({
    id: completionId,
    object: "chat.completion.chunk",
    created: Math.floor(Date.now() / 1000),
    model,
    choices: [{ index: 0, delta: { role: "assistant" }, finish_reason: null }],
  });

  try {
    ({ session } = await createPiSession());

    req.on("close", () => {
      if (!res.writableEnded) session?.abort?.().catch(() => {});
    });

    session.subscribe((event) => {
      const delta = textDeltaFromEvent(event) || progressDeltaFromEvent(event);
      if (!delta || res.writableEnded) return;
      writeSse({
        id: completionId,
        object: "chat.completion.chunk",
        created: Math.floor(Date.now() / 1000),
        model,
        choices: [{ index: 0, delta: { content: delta }, finish_reason: null }],
      });
    });

    await session.prompt(prompt);

    if (!res.writableEnded) {
      writeSse({
        id: completionId,
        object: "chat.completion.chunk",
        created: Math.floor(Date.now() / 1000),
        model,
        choices: [{ index: 0, delta: {}, finish_reason: "stop" }],
      });
      res.write("data: [DONE]\n\n");
      res.end();
    }
  } catch (error) {
    if (!res.writableEnded) {
      writeSse({ error: { message: errorMessage(error), type: "pi_bridge_error" } });
      res.write("data: [DONE]\n\n");
      res.end();
    }
  } finally {
    session?.dispose?.();
  }
}

function textDeltaFromEvent(event) {
  if (
    event?.type === "message_update" &&
    event.assistantMessageEvent?.type === "text_delta"
  ) {
    return event.assistantMessageEvent.delta ?? "";
  }
  return "";
}

function progressDeltaFromEvent(event) {
  if (!SHOW_PROGRESS) return "";

  if (event?.type === "agent_start") return "\n\n⏳ Pi is working...\n";
  if (event?.type === "tool_execution_start") {
    return `\n\n🔧 Running tool: ${event.toolName ?? "unknown"}...\n`;
  }
  if (event?.type === "tool_execution_end") {
    const name = event.toolName ?? "tool";
    return event.isError ? `\n⚠️ ${name} finished with an error.\n` : `\n✅ ${name} finished.\n`;
  }
  if (event?.type === "compaction_start") return "\n\n🧹 Compacting context...\n";
  if (event?.type === "auto_retry_start") return "\n\n🔁 Retrying request...\n";

  return "";
}

function messagesToPrompt(messages) {
  if (!Array.isArray(messages)) return "";

  return [basePromptHints(), ...messages]
    .map((message) => {
      if (typeof message === "string") return message;
      const role = message?.role ?? "user";
      const content = normalizeContent(message?.content);
      if (!content.trim()) return "";
      if (role === "system") return `System instruction:\n${content}`;
      if (role === "assistant") return `Previous assistant message:\n${content}`;
      if (role === "tool") return `Tool result:\n${content}`;
      return `User:\n${content}`;
    })
    .filter(Boolean)
    .join("\n\n---\n\n");
}

function webhookPayloadToPrompt(message, context) {
  const content = normalizeContent(message);
  const contextText = normalizeContent(context);
  const contextBlock = contextText.trim() ? `Webhook context:\n${contextText}` : "";
  const userBlock = content.trim() ? `User:\n${content}` : "";

  return [basePromptHints(), contextBlock, userBlock]
    .filter(Boolean)
    .join("\n\n---\n\n");
}

function basePromptHints() {
  const downloadHint = FILE_DOWNLOAD_KEY
    ? `If you create a file for the user, include its workspace-relative path and a download link in this exact format: ${PUBLIC_BASE_URL}/files/RELATIVE_FILE_PATH?key=${FILE_DOWNLOAD_KEY}`
    : `If you create a file for the user, include its workspace-relative path. Do not invent download links unless a file-download key is configured.`;

  return `${downloadHint}\n\n${workspaceDirectoryHint()}`;
}

function workspaceDirectoryHint() {
  const root = path.resolve(WORKSPACE);
  let entries;

  try {
    entries = listDirectorySnapshot(root, 2, 200);
  } catch (error) {
    return `Workspace root: ${root}\nWorkspace directory snapshot unavailable: ${errorMessage(error)}`;
  }

  return `Workspace root: ${root}\nCurrent workspace directory snapshot:\n${entries || "(empty)"}`;
}

function listDirectorySnapshot(dir, maxDepth, maxEntries, prefix = "") {
  if (maxEntries <= 0 || maxDepth < 0) return "";

  const children = fs
    .readdirSync(dir, { withFileTypes: true })
    .filter((entry) => ![".git", "node_modules"].includes(entry.name))
    .sort((a, b) => Number(b.isDirectory()) - Number(a.isDirectory()) || a.name.localeCompare(b.name));

  const lines = [];
  for (const child of children) {
    if (lines.length >= maxEntries) break;
    const marker = child.isDirectory() ? "/" : "";
    lines.push(`${prefix}${child.name}${marker}`);
    if (child.isDirectory() && maxDepth > 0) {
      const nested = listDirectorySnapshot(path.join(dir, child.name), maxDepth - 1, maxEntries - lines.length, `${prefix}${child.name}/`);
      if (nested) lines.push(...nested.split("\n"));
    }
  }
  return lines.slice(0, maxEntries).join("\n");
}

function normalizeContent(content) {
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    return content
      .map((part) => {
        if (typeof part === "string") return part;
        if (part?.type === "text") return part.text ?? "";
        if (part?.type === "image_url") return "[image_url omitted by pi-openwebui-bridge]";
        return JSON.stringify(part);
      })
      .join("\n");
  }
  if (content == null) return "";
  return String(content);
}

function requestToken(req) {
  const auth = req.header("authorization") ?? "";
  return auth.replace(/^Bearer\s+/i, "") || String(req.query.key ?? "");
}

function parseTools(value) {
  if (!value) return DEFAULT_TOOLS;
  const normalized = value.trim().toLowerCase();
  if (normalized === "default") return undefined;
  if (normalized === "none") return [];
  return value
    .split(",")
    .map((tool) => tool.trim())
    .filter(Boolean);
}

function parseBoolean(value, fallback) {
  if (value == null || value === "") return fallback;
  return ["1", "true", "yes", "on"].includes(String(value).toLowerCase());
}

function sendJsonError(res, error) {
  const status = res.headersSent ? undefined : 500;
  const payload = { error: { message: errorMessage(error), type: "pi_bridge_error" } };
  if (status) return res.status(status).json(payload);
  res.end();
}

function errorMessage(error) {
  return error instanceof Error ? error.message : String(error);
}

app.listen(PORT, HOST, () => {
  console.log(`Pi OpenWebUI bridge listening on http://${HOST}:${PORT}`);
  console.log(`OpenAI-compatible base URL: http://${HOST}:${PORT}/v1`);
  console.log(`Workspace: ${WORKSPACE}`);
  console.log(`Tools: ${tools?.join(",") || "pi default"}`);
});
