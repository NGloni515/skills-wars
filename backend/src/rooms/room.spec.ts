import type { MatchServerProcess } from '../match-servers/match-server-launcher.js';
import { ROOM_CAPACITY, Room, RoomVisibility } from './room.js';

const server: MatchServerProcess = {
  stop: () => undefined,
  onExit: () => undefined,
};

describe('Room', () => {
  it('holds reserved seats until the player shows up or the hold expires', () => {
    const room = new Room('ABCD', RoomVisibility.Public, 7800, server, 0);
    room.reserveSeat(0, 1000);
    room.reserveSeat(0, 1000);
    expect(room.occupancy(500)).toBe(2);

    room.recordHeartbeat(1, 5, 600);
    expect(room.occupancy(600)).toBe(2);

    expect(room.occupancy(1500)).toBe(1);
  });

  it('is full once humans and pending joins reach capacity', () => {
    const room = new Room('ABCD', RoomVisibility.Public, 7800, server, 0);
    room.recordHeartbeat(ROOM_CAPACITY - 1, 1, 0);
    expect(room.hasSeat(0)).toBe(true);
    room.reserveSeat(0, 1000);
    expect(room.hasSeat(0)).toBe(false);
  });

  it('counts as abandoned only after staying empty past the ttl', () => {
    const room = new Room('ABCD', RoomVisibility.Private, 7800, server, 0);
    room.recordHeartbeat(2, 4, 1000);
    room.recordHeartbeat(0, 6, 2000);
    expect(room.isAbandoned(2500, 1000)).toBe(false);
    expect(room.isAbandoned(3500, 1000)).toBe(true);
  });

  it('resolves startup on the first heartbeat', async () => {
    const room = new Room('ABCD', RoomVisibility.Private, 7800, server, 0);
    room.recordHeartbeat(0, 6, 10);
    await expect(room.started).resolves.toBeUndefined();
    expect(room.ready).toBe(true);
  });
});
