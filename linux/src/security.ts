import { isIP } from "node:net";
import { Resolver } from "node:dns/promises";

const blockedIPv4Ranges: Array<[number, number]> = [
  [ipv4("0.0.0.0"), ipv4("0.255.255.255")],
  [ipv4("10.0.0.0"), ipv4("10.255.255.255")],
  [ipv4("100.64.0.0"), ipv4("100.127.255.255")],
  [ipv4("127.0.0.0"), ipv4("127.255.255.255")],
  [ipv4("169.254.0.0"), ipv4("169.254.255.255")],
  [ipv4("172.16.0.0"), ipv4("172.31.255.255")],
  [ipv4("192.0.0.0"), ipv4("192.0.0.255")],
  [ipv4("192.0.2.0"), ipv4("192.0.2.255")],
  [ipv4("192.168.0.0"), ipv4("192.168.255.255")],
  [ipv4("198.18.0.0"), ipv4("198.19.255.255")],
  [ipv4("198.51.100.0"), ipv4("198.51.100.255")],
  [ipv4("203.0.113.0"), ipv4("203.0.113.255")],
  [ipv4("224.0.0.0"), ipv4("255.255.255.255")],
];

export interface NetworkPolicyOptions {
  allowedSubresourceOrigins?: ReadonlySet<string>;
  resolver?: AddressResolver;
}

export interface AddressResolver {
  resolve4(hostname: string): Promise<string[]>;
  resolve6(hostname: string): Promise<string[]>;
}

export interface ResolvedAddress {
  address: string;
  family: 4 | 6;
}

export class NetworkPolicy {
  private readonly resolver: AddressResolver;
  private readonly allowedSubresourceOrigins: ReadonlySet<string>;

  constructor(options: NetworkPolicyOptions = {}) {
    const systemResolver = new Resolver();
    this.resolver = options.resolver ?? {
      resolve4: async (hostname) => await systemResolver.resolve4(hostname),
      resolve6: async (hostname) => await systemResolver.resolve6(hostname),
    };
    this.allowedSubresourceOrigins = options.allowedSubresourceOrigins ?? new Set();
  }

  parseNavigationURL(raw: string): URL {
    const url = new URL(raw);
    if (url.protocol !== "https:" && url.protocol !== "http:") {
      throw new Error("only http and https navigation is allowed");
    }
    if (url.username || url.password) throw new Error("URL credentials are forbidden");
    if (url.hostname.endsWith(".local") || url.hostname === "localhost") {
      throw new Error("local navigation targets are forbidden");
    }
    return url;
  }

  async assertPublicURL(url: URL): Promise<void> {
    await this.resolvePublicAddresses(url.hostname);
  }

  async resolvePublicAddresses(rawHost: string): Promise<ResolvedAddress[]> {
    const host = rawHost.replace(/^\[|\]$/g, "");
    const kind = isIP(host);
    if (kind !== 0) {
      if (!isPublicAddress(host)) throw new Error("private or reserved address is forbidden");
      return [{ address: host, family: kind as 4 | 6 }];
    }
    const [v4, v6] = await Promise.all([
      this.resolver.resolve4(host).catch(() => []),
      this.resolver.resolve6(host).catch(() => []),
    ]);
    const answers: ResolvedAddress[] = [
      ...v4.map((address) => ({ address, family: 4 as const })),
      ...v6.map((address) => ({ address, family: 6 as const })),
    ];
    if (answers.length === 0 || answers.some(({ address }) => !isPublicAddress(address))) {
      throw new Error("hostname resolved to a private or reserved address");
    }
    return answers;
  }

  async authorizeRequest(
    raw: string,
    approvedTopLevelOrigin: string | null,
    isNavigation: boolean,
  ): Promise<void> {
    const url = this.parseNavigationURL(raw);
    await this.assertPublicURL(url);
    if (approvedTopLevelOrigin === null) throw new Error("no approved top-level origin");
    if (url.origin === approvedTopLevelOrigin) return;
    if (!isNavigation && this.allowedSubresourceOrigins.has(url.origin)) return;
    throw new Error("cross-origin request is outside the session capability");
  }

  async authorizeProxyURL(
    url: URL,
    approvedTopLevelOrigin: string | null,
  ): Promise<ResolvedAddress[]> {
    const addresses = await this.resolvePublicAddresses(url.hostname);
    if (approvedTopLevelOrigin === null) throw new Error("no approved top-level origin");
    if (url.origin === approvedTopLevelOrigin) return addresses;
    if (this.allowedSubresourceOrigins.has(url.origin)) return addresses;
    throw new Error("proxy destination is outside the session capability");
  }

  async authorizeConnectAuthority(
    rawHost: string,
    port: number,
    approvedTopLevelOrigin: string | null,
  ): Promise<ResolvedAddress[]> {
    const host = rawHost.replace(/^\[|\]$/g, "");
    const authority = isIP(host) === 6 ? `[${host}]:${port}` : `${host}:${port}`;
    const origin = new URL(`https://${authority}`).origin;
    if (
      approvedTopLevelOrigin === null ||
      (origin !== approvedTopLevelOrigin && !this.allowedSubresourceOrigins.has(origin))
    ) {
      throw new Error("proxy tunnel is outside the session capability");
    }
    return await this.resolvePublicAddresses(host);
  }
}

export function isPublicAddress(address: string): boolean {
  if (isIP(address) === 4) {
    const value = ipv4(address);
    return !blockedIPv4Ranges.some(([lower, upper]) => value >= lower && value <= upper);
  }
  if (isIP(address) !== 6) return false;
  const value = ipv6(address);
  const embeddedPrefix = value >> 32n;
  if (embeddedPrefix === 0n || embeddedPrefix === 0xffffn) {
    const embedded = Number(value & 0xffff_ffffn);
    return isPublicAddress(
      `${(embedded >>> 24) & 255}.${(embedded >>> 16) & 255}.${(embedded >>> 8) & 255}.${embedded & 255}`,
    );
  }
  const blocked: Array<[bigint, number]> = [
    [ipv6("64:ff9b::"), 96],
    [ipv6("64:ff9b:1::"), 48],
    [ipv6("100::"), 64],
    [ipv6("2001::"), 32],
    [ipv6("2001:10::"), 28],
    [ipv6("2001:20::"), 28],
    [ipv6("2001:db8::"), 32],
    [ipv6("2002::"), 16],
    [ipv6("fc00::"), 7],
    [ipv6("fe80::"), 10],
    [ipv6("ff00::"), 8],
  ];
  return !blocked.some(([network, bits]) => inIPv6CIDR(value, network, bits));
}

function ipv4(address: string): number {
  return address.split(".").reduce((value, octet) => value * 256 + Number(octet), 0);
}

function ipv6(address: string): bigint {
  const withoutZone = address.toLowerCase().split("%")[0] ?? "";
  let normalized = withoutZone;
  const dotted = normalized.match(/(\d+\.\d+\.\d+\.\d+)$/)?.[1];
  if (dotted !== undefined) {
    const value = ipv4(dotted);
    normalized = normalized.replace(
      dotted,
      `${((value >>> 16) & 0xffff).toString(16)}:${(value & 0xffff).toString(16)}`,
    );
  }
  const halves = normalized.split("::");
  if (halves.length > 2) throw new Error("invalid IPv6 address");
  const left = halves[0] === "" ? [] : (halves[0]?.split(":") ?? []);
  const right = halves.length === 1 || halves[1] === "" ? [] : (halves[1]?.split(":") ?? []);
  const zeros = 8 - left.length - right.length;
  const parts = [...left, ...Array.from({ length: zeros }, () => "0"), ...right];
  if (parts.length !== 8) throw new Error("invalid IPv6 address");
  return parts.reduce((value, part) => (value << 16n) | BigInt(`0x${part}`), 0n);
}

function inIPv6CIDR(value: bigint, network: bigint, bits: number): boolean {
  const shift = BigInt(128 - bits);
  return value >> shift === network >> shift;
}

export function parseOriginSet(raw: string | undefined): Set<string> {
  if (raw === undefined || raw.trim() === "") return new Set();
  return new Set(
    raw.split(",").map((item) => {
      const url = new URL(item.trim());
      if (url.pathname !== "/" || url.search || url.hash || url.username || url.password) {
        throw new Error("subresource allowlist entries must be bare origins");
      }
      if (url.protocol !== "https:" && url.protocol !== "http:") {
        throw new Error("subresource allowlist origins must use http or https");
      }
      return url.origin;
    }),
  );
}
