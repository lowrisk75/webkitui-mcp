#!/usr/bin/env node
import { createInterface } from "node:readline";
import { stdin, stdout } from "node:process";
import { LinuxMCPServer } from "./server.js";

const server = new LinuxMCPServer();
const input = createInterface({ input: stdin, crlfDelay: Infinity });

for await (const line of input) {
  if (line.trim() === "") continue;
  const response = await server.handleLine(line);
  if (response !== null) stdout.write(`${response}\n`);
}

await server.shutdown();
