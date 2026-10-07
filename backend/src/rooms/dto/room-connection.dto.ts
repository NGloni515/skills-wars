import { ROOM_CAPACITY, type Room, RoomVisibility } from '../room.js';

export class RoomConnectionDto {
  code: string;
  host: string;
  port: number;
  visibility: RoomVisibility;
  humans: number;
  capacity: number;

  static from(room: Room, host: string): RoomConnectionDto {
    return {
      code: room.code,
      host,
      port: room.port,
      visibility: room.visibility,
      humans: room.humans,
      capacity: ROOM_CAPACITY,
    };
  }
}
