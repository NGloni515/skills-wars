import {
  ConflictException,
  Inject,
  Injectable,
  Logger,
  NotFoundException,
  type OnApplicationShutdown,
  type OnModuleInit,
  ServiceUnavailableException,
} from '@nestjs/common';
import type { ConfigType } from '@nestjs/config';
import { matchServersConfig } from '../config/match-servers.config.js';
import {
  MatchServerLauncher,
  type MatchServerProcess,
} from '../match-servers/match-server-launcher.js';
import { PortPool } from '../match-servers/port-pool.js';
import { Room, RoomVisibility } from './room.js';
import { generateRoomCode } from './room-code.js';

const REAP_INTERVAL_MS = 5000;
const SEAT_HOLD_MS = 30000;
const CODE_ATTEMPTS = 20;

@Injectable()
export class RoomsService implements OnModuleInit, OnApplicationShutdown {
  private readonly logger = new Logger(RoomsService.name);
  private readonly rooms = new Map<string, Room>();
  private reaper?: NodeJS.Timeout;

  constructor(
    @Inject(matchServersConfig.KEY)
    private readonly config: ConfigType<typeof matchServersConfig>,
    private readonly launcher: MatchServerLauncher,
    private readonly ports: PortPool,
  ) {}

  onModuleInit(): void {
    this.reaper = setInterval(() => this.reap(Date.now()), REAP_INTERVAL_MS);
    this.reaper.unref();
  }

  onApplicationShutdown(): void {
    clearInterval(this.reaper);
    for (const room of this.rooms.values()) {
      this.close(room, 'backend shutting down');
    }
  }

  get count(): number {
    return this.rooms.size;
  }

  async create(visibility: RoomVisibility): Promise<Room> {
    const room = this.open(visibility);
    room.reserveSeat(Date.now(), SEAT_HOLD_MS);
    await this.whenStarted(room);
    return room;
  }

  async join(code: string): Promise<Room> {
    const room = this.rooms.get(code);
    if (!room) {
      throw new NotFoundException(`Room ${code} does not exist`);
    }
    const now = Date.now();
    if (!room.hasSeat(now)) {
      throw new ConflictException(`Room ${code} is full`);
    }
    room.reserveSeat(now, SEAT_HOLD_MS);
    await this.whenStarted(room);
    return room;
  }

  async quickPlay(): Promise<Room> {
    const now = Date.now();
    const candidates = [...this.rooms.values()]
      .filter((room) => room.visibility === RoomVisibility.Public)
      .filter((room) => room.hasSeat(now))
      .sort((a, b) => b.occupancy(now) - a.occupancy(now));
    const room = candidates[0] ?? this.open(RoomVisibility.Public);
    room.reserveSeat(now, SEAT_HOLD_MS);
    await this.whenStarted(room);
    return room;
  }

  recordHeartbeat(code: string, humans: number, bots: number): void {
    const room = this.rooms.get(code);
    if (!room) {
      throw new NotFoundException(`Room ${code} does not exist`);
    }
    room.recordHeartbeat(humans, bots, Date.now());
  }

  reap(now: number): void {
    for (const room of this.rooms.values()) {
      if (room.isUnresponsive(now, this.config.heartbeatTimeoutMs)) {
        this.close(room, 'stopped sending heartbeats');
      } else if (room.isAbandoned(now, this.config.emptyRoomTtlMs)) {
        this.close(room, 'empty');
      }
    }
  }

  private open(visibility: RoomVisibility): Room {
    const code = this.uniqueCode();
    const port = this.ports.take();
    if (port === undefined) {
      throw new ServiceUnavailableException(
        'All match servers are busy, try again soon',
      );
    }
    let server: MatchServerProcess;
    try {
      server = this.launcher.launch({ code, port });
    } catch (error) {
      this.ports.release(port);
      throw error;
    }
    const room = new Room(code, visibility, port, server, Date.now());
    this.rooms.set(code, room);
    server.onExit((exitCode) => {
      // Only free the port once the process is gone, or the next room could fail to bind it.
      this.ports.release(port);
      this.close(room, `match server exited (${exitCode ?? 'no code'})`);
    });
    this.logger.log(`Room ${code} (${visibility}) opening on port ${port}`);
    return room;
  }

  private close(room: Room, reason: string): void {
    if (this.rooms.get(room.code) !== room) {
      return;
    }
    this.rooms.delete(room.code);
    room.fail(reason);
    room.server.stop();
    this.logger.log(`Room ${room.code} closed: ${reason}`);
  }

  private async whenStarted(room: Room): Promise<void> {
    if (room.ready) {
      return;
    }
    let timer: NodeJS.Timeout | undefined;
    const timeout = new Promise<never>((_, reject) => {
      timer = setTimeout(
        () => reject(new Error('start timeout')),
        this.config.startTimeoutMs,
      );
    });
    try {
      await Promise.race([room.started, timeout]);
    } catch (error) {
      this.close(room, `failed to start: ${(error as Error).message}`);
      throw new ServiceUnavailableException('The match server failed to start');
    } finally {
      clearTimeout(timer);
    }
  }

  private uniqueCode(): string {
    for (let attempt = 0; attempt < CODE_ATTEMPTS; attempt++) {
      const code = generateRoomCode();
      if (!this.rooms.has(code)) {
        return code;
      }
    }
    throw new ServiceUnavailableException('Could not allocate a room code');
  }
}
