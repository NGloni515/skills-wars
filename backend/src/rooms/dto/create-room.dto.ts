import { IsEnum, IsOptional } from 'class-validator';
import { RoomVisibility } from '../room.js';

export class CreateRoomDto {
  @IsOptional()
  @IsEnum(RoomVisibility)
  visibility: RoomVisibility = RoomVisibility.Private;
}
