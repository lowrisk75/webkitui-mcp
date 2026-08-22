import { randomUUID } from "node:crypto";
import { LinuxBrowserRuntime, type LinuxRuntimeOptions } from "./runtime.js";
import type { ToolResult } from "./types.js";

const MODERN_VERSION = "2026-07-28";
const LEGACY_VERSION = "2025-06-18";
const CONFIRMATION_TTL_MS = 10 * 60 * 1_000;

interface RPCRequest {
  jsonrpc: "2.0";
  id?: string | number | null;
  method: string;
  params?: Record<string, unknown>;
}

interface PendingConfirmation {
  tool: "browser_navigate" | "browser_act";
  arguments: Record<string, unknown>;
  expiresAt: number;
}

export type RuntimeFactory = (options: LinuxRuntimeOptions) => LinuxBrowserRuntime;

export class LinuxMCPServer {
  private runtime: LinuxBrowserRuntime | null = null;
  private readonly pending = new Map<string, PendingConfirmation>();

  constructor(private readonly runtimeFactory: RuntimeFactory = (options) => new LinuxBrowserRuntime(options)) {}

  async handleLine(line: string): Promise<string | null> {
    let request: RPCRequest;
    try {
      request = JSON.parse(line) as RPCRequest;
    } catch {
      return JSON.stringify(errorResponse(null, -32700, "Parse error"));
    }
    if (request.jsonrpc !== "2.0" || typeof request.method !== "string") {
      return JSON.stringify(errorResponse(request.id ?? null, -32600, "Invalid request"));
    }
    if (request.id === undefined) return null;
    try {
      const modern = isModern(request.params);
      let result: unknown;
      switch (request.method) {
        case "server/discover":
          result = {
            supportedVersions: [MODERN_VERSION],
            serverInfo: { name: "webkitui-mcp-linux", version: "0.1.0" },
            capabilities: { tools: { listChanged: false }, elicitation: { form: {} } },
            instructions: "Ephemeral Linux browser; no persistent profile or raw JavaScript authority.",
          };
          break;
        case "initialize":
          result = {
            protocolVersion: LEGACY_VERSION,
            serverInfo: { name: "webkitui-mcp-linux", version: "0.1.0" },
            capabilities: { tools: { listChanged: false } },
            instructions: "Legacy clients can read tools but cannot confirm navigation or writes.",
          };
          break;
        case "tools/list":
          result = { tools };
          break;
        case "tools/call":
          result = await this.callTool(request.params ?? {}, modern);
          break;
        default:
          return JSON.stringify(errorResponse(request.id ?? null, -32601, "Method not found"));
      }
      return JSON.stringify({ jsonrpc: "2.0", id: request.id, result });
    } catch (error) {
      return JSON.stringify(
        errorResponse(request.id ?? null, -32602, safeError(error)),
      );
    }
  }

  async shutdown(): Promise<void> {
    await this.runtime?.close().catch(() => undefined);
    this.runtime = null;
    this.pending.clear();
  }

  private async callTool(params: Record<string, unknown>, modern: boolean): Promise<unknown> {
    const name = requiredString(params, "name");
    const arguments_ = objectValue(params.arguments, "arguments");
    try {
      switch (name) {
        case "browser_session":
          return await this.sessionTool(arguments_);
        case "browser_navigate":
          return await this.confirmedTool(name, params, arguments_, modern, async () => {
            const runtime = this.runtimeFor(arguments_);
            const observation = await runtime.navigate(
              requiredString(arguments_, "url"),
              optionalInteger(arguments_, "timeout_ms") ?? 30_000,
            );
            return toolResult({ observation });
          });
        case "browser_observe": {
          const observation = await this.runtimeFor(arguments_).observe();
          return toolResult({ observation });
        }
        case "browser_capture": {
          const capture = await this.runtimeFor(arguments_).capture(
            optionalBoolean(arguments_, "full_page") ?? false,
          );
          return toolResult({ capture });
        }
        case "browser_act": {
          const runtime = this.runtimeFor(arguments_);
          if (!runtime.allowWrites) throw new Error("Linux worker is read-only; transactional writes are disabled");
          return await this.confirmedTool(name, params, arguments_, modern, async () => {
            try {
              return toolResult({ receipt: await runtime.act(arguments_) });
            } catch (error) {
              const receipt = (error as { receipt?: unknown }).receipt;
              return toolError(safeError(error), receipt === undefined ? undefined : { receipt });
            }
          });
        }
        case "browser_transaction": {
          const receipt = this.runtimeFor(arguments_).transaction(
            requiredString(arguments_, "receipt_id"),
          );
          return toolResult({ receipt });
        }
        default:
          return toolError("unknown tool");
      }
    } catch (error) {
      if (error instanceof InvalidParamsError) throw error;
      return toolError(safeError(error));
    }
  }

  private async sessionTool(arguments_: Record<string, unknown>): Promise<ToolResult> {
    const operation = requiredString(arguments_, "operation");
    if (operation === "open") {
      if (this.runtime !== null) throw new Error("one browser controller is already open");
      const requestedEngine = optionalString(arguments_, "engine");
      if (requestedEngine !== undefined && requestedEngine !== "chromium" && requestedEngine !== "webkit") {
        throw new Error("engine must be chromium or webkit");
      }
      const runtime = this.runtimeFactory(
        requestedEngine === undefined ? {} : { engine: requestedEngine },
      );
      await runtime.open();
      this.runtime = runtime;
      return toolResult(runtime.status());
    }
    const runtime = this.runtimeFor(arguments_);
    if (operation === "status") return toolResult(runtime.status());
    if (operation === "close") {
      await runtime.close();
      this.runtime = null;
      this.pending.clear();
      return toolResult({ session_id: runtime.sessionID, state: "closed" });
    }
    if (operation === "handoff") {
      throw new Error("human handoff is available only through the native Mac backend");
    }
    throw new Error("operation must be open, status, close, or handoff");
  }

  private async confirmedTool(
    tool: "browser_navigate" | "browser_act",
    params: Record<string, unknown>,
    arguments_: Record<string, unknown>,
    modern: boolean,
    dispatch: () => Promise<unknown>,
  ): Promise<unknown> {
    if (!modern) {
      return toolError(`${tool} requires MCP ${MODERN_VERSION} multi-round confirmation`);
    }
    const requestState = optionalString(params, "requestState");
    if (requestState !== undefined) {
      const pending = this.pending.get(requestState);
      this.pending.delete(requestState);
      if (pending === undefined || pending.expiresAt <= Date.now()) {
        throw new InvalidParamsError("requestState is unknown or expired");
      }
      if (pending.tool !== tool || canonicalJSON(pending.arguments) !== canonicalJSON(arguments_)) {
        throw new InvalidParamsError("confirmed arguments changed");
      }
      if (!acceptedConfirmation(params.inputResponses)) {
        return toolError("operation remains unexecuted without explicit confirmation");
      }
      return await dispatch();
    }
    if (params.inputResponses !== undefined) {
      throw new InvalidParamsError("inputResponses requires requestState");
    }
    for (const [key, pending] of this.pending) {
      if (pending.tool === tool) this.pending.delete(key);
    }
    const state = randomUUID();
    this.pending.set(state, {
      tool,
      arguments: structuredClone(arguments_),
      expiresAt: Date.now() + CONFIRMATION_TTL_MS,
    });
    return {
      resultType: "input_required",
      requestState: state,
      inputRequests: {
        confirmation: {
          method: "elicitation/create",
          params: {
            mode: "form",
            message: confirmationMessage(tool, arguments_),
            requestedSchema: {
              type: "object",
              properties: { confirm: { type: "boolean", title: "Execute this exact operation" } },
              required: ["confirm"],
            },
          },
        },
      },
    };
  }

  private runtimeFor(arguments_: Record<string, unknown>): LinuxBrowserRuntime {
    const runtime = this.runtime;
    if (runtime === null) throw new Error("session is not open");
    if (requiredString(arguments_, "session_id") !== runtime.sessionID) {
      throw new Error("unknown session_id");
    }
    return runtime;
  }
}

const tools = [
  {
    name: "browser_session",
    description: "Open, inspect, or close one ephemeral Linux headless session. Human handoff is Mac-only.",
    annotations: { readOnlyHint: false, destructiveHint: false },
    inputSchema: {
      type: "object",
      additionalProperties: false,
      properties: {
        operation: { type: "string", enum: ["open", "status", "close", "handoff"] },
        session_id: { type: "string" },
        engine: { type: "string", enum: ["chromium", "webkit"] },
      },
      required: ["operation"],
    },
  },
  {
    name: "browser_navigate",
    description: "Navigate to one exact public HTTP(S) URL after explicit multi-round confirmation.",
    annotations: { readOnlyHint: false, destructiveHint: false },
    inputSchema: objectSchema({
      session_id: stringSchema(),
      url: stringSchema(),
      timeout_ms: { type: "integer", minimum: 1, maximum: 120000 },
    }, ["session_id", "url"]),
  },
  {
    name: "browser_observe",
    description: "Return a bounded provenance-labelled observation and ephemeral semantic element IDs.",
    annotations: { readOnlyHint: true, destructiveHint: false },
    inputSchema: objectSchema({ session_id: stringSchema() }, ["session_id"]),
  },
  {
    name: "browser_capture",
    description: "Capture a bounded PNG screenshot; full-page height is capped.",
    annotations: { readOnlyHint: true, destructiveHint: false },
    inputSchema: objectSchema(
      { session_id: stringSchema(), full_page: { type: "boolean" } },
      ["session_id"],
    ),
  },
  {
    name: "browser_act",
    description: "Opt-in transactional click or non-sensitive fill with fresh resolution and exact postcondition.",
    annotations: { readOnlyHint: false, destructiveHint: true },
    inputSchema: objectSchema(
      {
        session_id: stringSchema(),
        kind: { type: "string", enum: ["click", "fill"] },
        observation_id: stringSchema(),
        element_id: stringSchema(),
        text: { type: "string" },
        expected_url: { type: "string" },
        expected_text: { type: "string" },
      },
      ["session_id", "kind", "observation_id", "element_id"],
    ),
  },
  {
    name: "browser_transaction",
    description: "Read a transaction receipt. Indeterminate actions are never automatically replayed.",
    annotations: { readOnlyHint: true, destructiveHint: false },
    inputSchema: objectSchema(
      { session_id: stringSchema(), receipt_id: stringSchema() },
      ["session_id", "receipt_id"],
    ),
  },
] as const;

function isModern(params: Record<string, unknown> | undefined): boolean {
  const meta = params?._meta;
  if (meta === undefined) return false;
  const object = objectValue(meta, "_meta");
  const requested = object["io.modelcontextprotocol/protocolVersion"];
  if (requested === undefined) return false;
  if (requested !== MODERN_VERSION) throw new Error(`unsupported protocol version ${String(requested)}`);
  const capabilities = object["io.modelcontextprotocol/clientCapabilities"];
  if (typeof capabilities !== "object" || capabilities === null) {
    throw new Error("modern requests require client capabilities metadata");
  }
  return true;
}

function acceptedConfirmation(value: unknown): boolean {
  if (typeof value !== "object" || value === null) return false;
  const confirmation = (value as Record<string, unknown>).confirmation;
  if (typeof confirmation !== "object" || confirmation === null) return false;
  const object = confirmation as Record<string, unknown>;
  if (object.action !== "accept") return false;
  const content = object.content;
  return (
    typeof content === "object" &&
    content !== null &&
    (content as Record<string, unknown>).confirm === true
  );
}

function confirmationMessage(tool: string, arguments_: Record<string, unknown>): string {
  if (tool === "browser_navigate") return `Allow exact navigation to ${String(arguments_.url)}?`;
  return `Allow exact ${String(arguments_.kind)} on ${String(arguments_.element_id)}?`;
}

function toolResult(structuredContent: unknown): ToolResult {
  return {
    content: [{ type: "text", text: JSON.stringify(structuredContent) }],
    structuredContent,
  };
}

function toolError(message: string, structuredContent?: unknown): ToolResult {
  return {
    content: [{ type: "text", text: message }],
    ...(structuredContent === undefined ? {} : { structuredContent }),
    isError: true,
  };
}

function errorResponse(id: string | number | null, code: number, message: string) {
  return { jsonrpc: "2.0", id, error: { code, message } };
}

function objectValue(value: unknown, name: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error(`${name} must be an object`);
  }
  return value as Record<string, unknown>;
}

function requiredString(object: Record<string, unknown>, key: string): string {
  const value = object[key];
  if (typeof value !== "string" || value === "") throw new Error(`${key} must be a non-empty string`);
  return value;
}

function optionalString(object: Record<string, unknown>, key: string): string | undefined {
  const value = object[key];
  if (value === undefined) return undefined;
  if (typeof value !== "string" || value === "") throw new Error(`${key} must be a non-empty string`);
  return value;
}

function optionalInteger(object: Record<string, unknown>, key: string): number | undefined {
  const value = object[key];
  if (value === undefined) return undefined;
  if (!Number.isInteger(value)) throw new Error(`${key} must be an integer`);
  return value as number;
}

function optionalBoolean(object: Record<string, unknown>, key: string): boolean | undefined {
  const value = object[key];
  if (value === undefined) return undefined;
  if (typeof value !== "boolean") throw new Error(`${key} must be a boolean`);
  return value;
}

function canonicalJSON(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonicalJSON).join(",")}]`;
  if (typeof value === "object" && value !== null) {
    return `{${Object.keys(value as Record<string, unknown>)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonicalJSON((value as Record<string, unknown>)[key])}`)
      .join(",")}}`;
  }
  return JSON.stringify(value);
}

function safeError(error: unknown): string {
  return error instanceof Error ? error.message.slice(0, 500) : "unknown server error";
}

function stringSchema() {
  return { type: "string", minLength: 1 };
}

function objectSchema(properties: Record<string, unknown>, required: string[]) {
  return { type: "object", additionalProperties: false, properties, required };
}

class InvalidParamsError extends Error {}
