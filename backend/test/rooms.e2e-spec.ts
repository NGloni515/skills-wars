import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module.js';
import { configureApp } from '../src/app.setup.js';
import {
  MatchServerLauncher,
  type MatchServerProcess,
  type MatchServerSpec,
} from '../src/match-servers/match-server-launcher.js';
import { GAME_PROTOCOL_HEADER } from '../src/rooms/game-protocol.guard.js';
import { MATCH_SECRET_HEADER } from '../src/rooms/match-secret.guard.js';
import { ROOM_CODE_PATTERN } from '../src/rooms/room-code.js';
import { RoomsService } from '../src/rooms/rooms.service.js';

const SECRET = process.env.MATCH_SECRET!;
const PROTOCOL = 3;

class FakeMatchServer implements MatchServerProcess {
  stopped = false;
  private listeners: ((exitCode: number | null) => void)[] = [];

  stop(): void {
    this.stopped = true;
    setImmediate(() => this.listeners.forEach((listener) => listener(0)));
  }

  onExit(listener: (exitCode: number | null) => void): void {
    this.listeners.push(listener);
  }
}

class FakeLauncher extends MatchServerLauncher {
  launched: (MatchServerSpec & { server: FakeMatchServer })[] = [];
  bootsUp = true;
  heartbeat?: (code: string) => Promise<unknown>;

  launch(spec: MatchServerSpec): MatchServerProcess {
    const server = new FakeMatchServer();
    this.launched.push({ ...spec, server });
    if (this.bootsUp) {
      setTimeout(() => void this.heartbeat?.(spec.code), 20);
    }
    return server;
  }

  readProtocol(): Promise<number> {
    return Promise.resolve(PROTOCOL);
  }
}

describe('Rooms (e2e)', () => {
  let app: INestApplication;
  let launcher: FakeLauncher;

  const play = (path: string) =>
    request(app.getHttpServer())
      .post(path)
      .set(GAME_PROTOCOL_HEADER, String(PROTOCOL));

  const heartbeat = (code: string, humans: number, bots: number) =>
    request(app.getHttpServer())
      .post(`/v1/internal/rooms/${code}/heartbeat`)
      .set(MATCH_SECRET_HEADER, SECRET)
      .send({ humans, bots });

  beforeEach(async () => {
    launcher = new FakeLauncher();
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(MatchServerLauncher)
      .useValue(launcher)
      .compile();
    app = moduleRef.createNestApplication();
    configureApp(app);
    await app.init();
    launcher.heartbeat = async (code) => await heartbeat(code, 0, 6);
  });

  afterEach(async () => {
    await app.close();
  });

  it('creates a private room and lets friends join with its code', async () => {
    const created = await play('/v1/rooms').send({}).expect(201);
    expect(created.body).toMatchObject({
      host: 'play.example.test',
      port: 7800,
      visibility: 'private',
      capacity: 6,
    });
    expect(created.body.code).toMatch(ROOM_CODE_PATTERN);
    expect(launcher.launched).toHaveLength(1);

    const joined = await play(
      `/v1/rooms/${created.body.code.toLowerCase()}/join`,
    ).expect(200);
    expect(joined.body.code).toBe(created.body.code);
    expect(joined.body.port).toBe(7800);
  });

  it('rejects unknown and malformed room codes', async () => {
    await play('/v1/rooms/ZZZZ/join').expect(404);
    await play('/v1/rooms/AB1/join').expect(400);
    await play('/v1/rooms').send({ visibility: 'secret' }).expect(400);
  });

  it('quick play fills public rooms before opening new ones', async () => {
    const first = await play('/v1/rooms/quick-play').expect(200);
    const second = await play('/v1/rooms/quick-play').expect(200);
    expect(first.body.visibility).toBe('public');
    expect(second.body.code).toBe(first.body.code);

    await heartbeat(first.body.code, 6, 0).expect(204);
    await play(`/v1/rooms/${first.body.code}/join`).expect(409);
    const third = await play('/v1/rooms/quick-play').expect(200);
    expect(third.body.code).not.toBe(first.body.code);

    await play('/v1/rooms').expect(503);
  });

  it('protects heartbeats with the shared secret', async () => {
    const room = await play('/v1/rooms').expect(201);
    await request(app.getHttpServer())
      .post(`/v1/internal/rooms/${room.body.code}/heartbeat`)
      .send({ humans: 1, bots: 5 })
      .expect(401);
    await request(app.getHttpServer())
      .post(`/v1/internal/rooms/${room.body.code}/heartbeat`)
      .set(MATCH_SECRET_HEADER, 'wrong-secret-0123456789')
      .send({ humans: 1, bots: 5 })
      .expect(401);
    await heartbeat(room.body.code, -1, 5).expect(400);
    await heartbeat('QQQQ', 1, 5).expect(404);
  });

  it('gives up on match servers that never report in', async () => {
    launcher.bootsUp = false;
    await play('/v1/rooms').expect(503);
    expect(launcher.launched[0].server.stopped).toBe(true);
  });

  it('closes empty rooms and frees their port', async () => {
    const room = await play('/v1/rooms').expect(201);
    const rooms = app.get(RoomsService);
    rooms.reap(Date.now() + 10 * 60 * 1000);
    expect(launcher.launched[0].server.stopped).toBe(true);
    await play(`/v1/rooms/${room.body.code}/join`).expect(404);
    await new Promise((resolve) => setImmediate(resolve));

    const health = await request(app.getHttpServer())
      .get('/health')
      .expect(200);
    expect(health.body.details.matchServers).toMatchObject({
      rooms: 0,
      freeSlots: 2,
      protocol: PROTOCOL,
    });
  });

  it('turns away games that speak another protocol', async () => {
    for (const header of [undefined, '2', '4', 'abc']) {
      const call = request(app.getHttpServer()).post('/v1/rooms/quick-play');
      const response = await (
        header ? call.set(GAME_PROTOCOL_HEADER, header) : call
      ).expect(426);
      expect(response.body.protocol).toBe(PROTOCOL);
    }
    expect(launcher.launched).toHaveLength(0);
  });
});
