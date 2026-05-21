/**
 * pixel-agent relay — Cloudflare Worker
 *
 * Routes:
 *   GET /connect/{pairingCode}  (Mac istemcisi WebSocket upgrade)
 *   GET /listen/{pairingCode}   (iOS istemcisi WebSocket upgrade)
 *
 * Aynı pairingCode'a sahip iki taraf WebSocket'leri Durable Object içinde eşleşir;
 * mesajlar tek-yön (mac→ios veya ios→mac) forward edilir. Karşı taraf yoksa
 * mesaj 30 saniye boyunca buffer'da tutulur (max 200 frame).
 */

export interface Env {
  RELAY_SESSIONS: DurableObjectNamespace;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const segments = url.pathname.split('/').filter(Boolean);

    if (segments.length === 2 && (segments[0] === 'connect' || segments[0] === 'listen')) {
      const pairingCode = segments[1];
      if (!/^[A-Z0-9]{6}$/.test(pairingCode)) {
        return new Response('Invalid pairing code', { status: 400 });
      }
      const objectID = env.RELAY_SESSIONS.idFromName(pairingCode);
      const stub = env.RELAY_SESSIONS.get(objectID);
      return stub.fetch(request);
    }

    return new Response('pixel-agent relay v0.1.0', {
      status: 200,
      headers: { 'content-type': 'text/plain' },
    });
  },
};

type Role = 'mac' | 'ios';

interface BufferedFrame {
  to: Role;
  data: string;
  ts: number;
}

export class RelaySession {
  private state: DurableObjectState;
  private sockets: Map<Role, WebSocket> = new Map();
  private buffer: BufferedFrame[] = [];

  private readonly MAX_BUFFER = 200;
  private readonly BUFFER_TTL_MS = 30_000;

  constructor(state: DurableObjectState) {
    this.state = state;
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const segments = url.pathname.split('/').filter(Boolean);
    const role: Role = segments[0] === 'connect' ? 'mac' : 'ios';

    if (request.headers.get('Upgrade') !== 'websocket') {
      return new Response('Expected WebSocket upgrade', { status: 426 });
    }

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    server.accept();

    const existing = this.sockets.get(role);
    if (existing) {
      try { existing.close(1000, 'replaced'); } catch { /* noop */ }
    }
    this.sockets.set(role, server);

    this.flushBuffer(role);

    server.addEventListener('message', (event: MessageEvent) => {
      if (typeof event.data !== 'string') return;
      const data = event.data;
      const target: Role = role === 'mac' ? 'ios' : 'mac';
      const targetSocket = this.sockets.get(target);
      if (targetSocket) {
        try {
          targetSocket.send(data);
        } catch {
          this.enqueue(target, data);
        }
      } else {
        this.enqueue(target, data);
      }
    });

    server.addEventListener('close', () => {
      if (this.sockets.get(role) === server) {
        this.sockets.delete(role);
      }
    });

    server.addEventListener('error', () => {
      if (this.sockets.get(role) === server) {
        this.sockets.delete(role);
      }
    });

    return new Response(null, { status: 101, webSocket: client });
  }

  private enqueue(to: Role, data: string) {
    this.buffer.push({ to, data, ts: Date.now() });
    if (this.buffer.length > this.MAX_BUFFER) {
      this.buffer = this.buffer.slice(-this.MAX_BUFFER);
    }
  }

  private flushBuffer(arrivedRole: Role) {
    const socket = this.sockets.get(arrivedRole);
    if (!socket) return;
    const now = Date.now();
    const remaining: BufferedFrame[] = [];
    for (const frame of this.buffer) {
      if (frame.to !== arrivedRole) {
        remaining.push(frame);
        continue;
      }
      if (now - frame.ts > this.BUFFER_TTL_MS) continue;
      try {
        socket.send(frame.data);
      } catch {
        remaining.push(frame);
      }
    }
    this.buffer = remaining;
  }
}
