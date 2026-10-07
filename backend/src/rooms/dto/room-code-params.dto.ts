import { Transform } from 'class-transformer';
import { Matches } from 'class-validator';
import { ROOM_CODE_PATTERN } from '../room-code.js';

export class RoomCodeParamsDto {
  @Transform(({ value }) =>
    typeof value === 'string' ? value.trim().toUpperCase() : value,
  )
  @Matches(ROOM_CODE_PATTERN, { message: 'code must be a 4-letter room code' })
  code: string;
}
