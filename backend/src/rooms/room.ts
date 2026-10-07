import type { MatchServerProcess } from '../match-servers/match-server-launcher.js';

export enum RoomVisibility {
  Public = 'public',
  Private = 'private',
}

export const ROOM_CAPACITY = 6;

export class Room {
  humans = 0;
  bots = 0;
  ready = false;
  lastHeartbeatAt: number;
  lastOccupiedAt: number;
  readonly started: Promise<void>;
  private reservations: number[] = [];
  private resolveStarted!: () => void;
  private rejectStarted!: (error: Error) => void;

  constructor(
    readonly code: string,
    readonly visibility: RoomVisibility,
    readonly port: number,
    readonly server: MatchServerProcess,
    now: number,
  ) {
    this.lastHeartbeatAt = now;
    this.lastOccupiedAt = now;
    this.started = new Promise<void>((resolve, reject) => {
      this.resolveStarted = resolve;
      this.rejectStarted = reject;
    });
    // Nobody may be awaiting startup when a room fails; avoid an unhandled rejection.
    this.started.catch(() => undefined);
  }

  occupancy(now: number): number {
    this.reservations = this.reservations.filter((expiry) => expiry > now);
    return this.humans + this.reservations.length;
  }

  hasSeat(now: number): boolean {
    return this.occupancy(now) < ROOM_CAPACITY;
  }

  reserveSeat(now: number, holdMs: number): void {
    this.reservations.push(now + holdMs);
    this.lastOccupiedAt = now;
  }

  recordHeartbeat(humans: number, bots: number, now: number): void {
    const arrived = humans - this.humans;
    if (arrived > 0) {
      this.reservations.splice(0, arrived);
    }
    if (humans > 0 || this.humans > 0) {
      this.lastOccupiedAt = now;
    }
    this.humans = humans;
    this.bots = bots;
    this.lastHeartbeatAt = now;
    if (!this.ready) {
      this.ready = true;
      this.resolveStarted();
    }
  }

  fail(reason: string): void {
    this.rejectStarted(new Error(reason));
  }

  isAbandoned(now: number, ttlMs: number): boolean {
    return this.occupancy(now) === 0 && now - this.lastOccupiedAt > ttlMs;
  }

  isUnresponsive(now: number, timeoutMs: number): boolean {
    return this.ready && now - this.lastHeartbeatAt > timeoutMs;
  }
}
