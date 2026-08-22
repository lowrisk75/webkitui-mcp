import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { mkdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import path from "node:path";

interface LeaseOwner {
  pid: number;
  processStart: string | null;
  token: string;
}

export class ControllerLease {
  private readonly owner: LeaseOwner;
  private held = false;

  constructor(private readonly lockDirectory: string) {
    this.owner = {
      pid: process.pid,
      processStart: readProcessStart(process.pid),
      token: randomUUID(),
    };
  }

  async acquire(): Promise<void> {
    if (this.held) throw new Error("controller lease is already held");
    const parent = path.dirname(this.lockDirectory);
    const candidate = `${this.lockDirectory}.candidate-${this.owner.token}`;
    await mkdir(parent, { recursive: true, mode: 0o700 });
    await mkdir(candidate, { mode: 0o700 });
    await writeFile(path.join(candidate, "owner.json"), JSON.stringify(this.owner), {
      mode: 0o600,
      flag: "wx",
    });
    try {
      for (let attempt = 0; attempt < 3; attempt += 1) {
        try {
          await rename(candidate, this.lockDirectory);
          this.held = true;
          return;
        } catch (error) {
          if (!alreadyExists(error)) throw error;
          const existing = await readOwner(this.lockDirectory);
          if (existing !== null && ownerIsAlive(existing)) {
            throw new Error("another Linux browser controller is active");
          }
          const stale = `${this.lockDirectory}.stale-${randomUUID()}`;
          try {
            await rename(this.lockDirectory, stale);
            await rm(stale, { recursive: true });
          } catch (staleError) {
            if (!missing(staleError)) throw staleError;
          }
        }
      }
      throw new Error("controller lease changed repeatedly");
    } finally {
      if (!this.held) await rm(candidate, { recursive: true, force: true });
    }
  }

  async release(): Promise<void> {
    if (!this.held) return;
    this.held = false;
    const existing = await readOwner(this.lockDirectory);
    if (existing?.token !== this.owner.token) return;
    const released = `${this.lockDirectory}.released-${this.owner.token}`;
    try {
      await rename(this.lockDirectory, released);
      await rm(released, { recursive: true });
    } catch (error) {
      if (!missing(error)) throw error;
    }
  }
}

function readProcessStart(pid: number): string | null {
  if (process.platform !== "linux") return null;
  try {
    const stat = readFileSync(`/proc/${pid}/stat`, "utf8");
    const closing = stat.lastIndexOf(")");
    if (closing < 0) return null;
    return stat.slice(closing + 2).split(" ")[19] ?? null;
  } catch {
    return null;
  }
}

function ownerIsAlive(owner: LeaseOwner): boolean {
  try {
    process.kill(owner.pid, 0);
  } catch {
    return false;
  }
  if (owner.processStart === null) return true;
  return readProcessStart(owner.pid) === owner.processStart;
}

async function readOwner(directory: string): Promise<LeaseOwner | null> {
  try {
    const value = JSON.parse(await readFile(path.join(directory, "owner.json"), "utf8")) as Partial<LeaseOwner>;
    if (typeof value.pid !== "number" || typeof value.token !== "string") return null;
    return {
      pid: value.pid,
      token: value.token,
      processStart: typeof value.processStart === "string" ? value.processStart : null,
    };
  } catch {
    return null;
  }
}

function alreadyExists(error: unknown): boolean {
  return (error as NodeJS.ErrnoException).code === "EEXIST" || (error as NodeJS.ErrnoException).code === "ENOTEMPTY";
}

function missing(error: unknown): boolean {
  return (error as NodeJS.ErrnoException).code === "ENOENT";
}
