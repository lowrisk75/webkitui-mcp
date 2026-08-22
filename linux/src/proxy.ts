import { randomBytes, timingSafeEqual } from "node:crypto";
import http from "node:http";
import net from "node:net";
import type { Duplex } from "node:stream";
import { NetworkPolicy } from "./security.js";

export interface ProxyEndpoint {
  server: string;
  username: string;
  password: string;
}

export class PinnedHTTPProxy {
  private readonly username = "webkitui";
  private readonly password = randomBytes(32).toString("base64url");
  private readonly sockets = new Set<Duplex>();
  private readonly server: http.Server;
  private endpoint: ProxyEndpoint | null = null;

  constructor(
    private readonly policy: NetworkPolicy,
    private readonly approvedTopLevelOrigin: () => string | null,
  ) {
    this.server = http.createServer((request, response) => {
      void this.handleHTTP(request, response);
    });
    this.server.on("connect", (request, socket, head) => {
      void this.handleConnect(request, socket, head);
    });
    this.server.on("connection", (socket) => {
      this.sockets.add(socket);
      socket.once("close", () => this.sockets.delete(socket));
    });
  }

  async start(): Promise<ProxyEndpoint> {
    if (this.endpoint !== null) return this.endpoint;
    await new Promise<void>((resolve, reject) => {
      this.server.once("error", reject);
      this.server.listen(0, "127.0.0.1", () => {
        this.server.off("error", reject);
        resolve();
      });
    });
    const address = this.server.address();
    if (address === null || typeof address === "string") throw new Error("proxy did not bind TCP");
    this.endpoint = {
      server: `http://127.0.0.1:${address.port}`,
      username: this.username,
      password: this.password,
    };
    return this.endpoint;
  }

  async close(): Promise<void> {
    for (const socket of this.sockets) socket.destroy();
    this.sockets.clear();
    if (!this.server.listening) return;
    await new Promise<void>((resolve) => this.server.close(() => resolve()));
    this.endpoint = null;
  }

  private async handleHTTP(
    request: http.IncomingMessage,
    response: http.ServerResponse,
  ): Promise<void> {
    if (!this.authorized(request.headers["proxy-authorization"])) {
      response.writeHead(407, { "Proxy-Authenticate": 'Basic realm="webkitui"' });
      response.end();
      return;
    }
    try {
      const url = new URL(request.url ?? "");
      if (url.protocol !== "http:") throw new Error("direct proxy requests must use HTTP");
      const target = (
        await this.policy.authorizeProxyURL(url, this.approvedTopLevelOrigin())
      )[0];
      if (target === undefined) throw new Error("no public target address");
      const headers: http.OutgoingHttpHeaders = { ...request.headers, host: url.host };
      delete headers["proxy-authorization"];
      delete headers["proxy-connection"];
      const upstream = http.request({
        host: target.address,
        family: target.family,
        port: url.port === "" ? 80 : Number(url.port),
        method: request.method,
        path: `${url.pathname}${url.search}`,
        headers,
      });
      upstream.once("response", (upstreamResponse) => {
        response.writeHead(upstreamResponse.statusCode ?? 502, upstreamResponse.headers);
        upstreamResponse.pipe(response);
      });
      upstream.once("error", () => {
        if (!response.headersSent) response.writeHead(502);
        response.end();
      });
      request.pipe(upstream);
    } catch {
      response.writeHead(403);
      response.end();
    }
  }

  private async handleConnect(
    request: http.IncomingMessage,
    client: Duplex,
    head: Buffer,
  ): Promise<void> {
    if (!this.authorized(request.headers["proxy-authorization"])) {
      client.end('HTTP/1.1 407 Proxy Authentication Required\r\nProxy-Authenticate: Basic realm="webkitui"\r\n\r\n');
      return;
    }
    try {
      const authority = new URL(`http://${request.url ?? ""}`);
      const port = authority.port === "" ? 443 : Number(authority.port);
      if (!Number.isInteger(port) || port < 1 || port > 65_535) throw new Error("invalid port");
      const target = (
        await this.policy.authorizeConnectAuthority(
          authority.hostname,
          port,
          this.approvedTopLevelOrigin(),
        )
      )[0];
      if (target === undefined) throw new Error("no public target address");
      const upstream = net.connect({ host: target.address, family: target.family, port });
      this.sockets.add(upstream);
      upstream.once("close", () => this.sockets.delete(upstream));
      upstream.once("connect", () => {
        client.write("HTTP/1.1 200 Connection Established\r\n\r\n");
        if (head.length > 0) upstream.write(head);
        client.pipe(upstream);
        upstream.pipe(client);
      });
      upstream.once("error", () => client.destroy());
    } catch {
      client.end("HTTP/1.1 403 Forbidden\r\n\r\n");
    }
  }

  private authorized(header: string | undefined): boolean {
    if (header === undefined) return false;
    const expected = Buffer.from(`Basic ${Buffer.from(`${this.username}:${this.password}`).toString("base64")}`);
    const actual = Buffer.from(header);
    return actual.length === expected.length && timingSafeEqual(actual, expected);
  }
}
