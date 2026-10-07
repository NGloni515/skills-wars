import {
  Body,
  Controller,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { SkipThrottle } from '@nestjs/throttler';
import { HeartbeatDto } from './dto/heartbeat.dto.js';
import { RoomCodeParamsDto } from './dto/room-code-params.dto.js';
import { MatchSecretGuard } from './match-secret.guard.js';
import { RoomsService } from './rooms.service.js';

@SkipThrottle()
@UseGuards(MatchSecretGuard)
@Controller('internal/rooms')
export class MatchHeartbeatController {
  constructor(private readonly rooms: RoomsService) {}

  @Post(':code/heartbeat')
  @HttpCode(HttpStatus.NO_CONTENT)
  heartbeat(
    @Param() { code }: RoomCodeParamsDto,
    @Body() { humans, bots }: HeartbeatDto,
  ): void {
    this.rooms.recordHeartbeat(code, humans, bots);
  }
}
