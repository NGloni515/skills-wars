import {
  Body,
  Controller,
  HttpCode,
  HttpStatus,
  Inject,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import type { ConfigType } from '@nestjs/config';
import { Throttle, minutes } from '@nestjs/throttler';
import { matchServersConfig } from '../config/match-servers.config.js';
import { CreateRoomDto } from './dto/create-room.dto.js';
import { RoomCodeParamsDto } from './dto/room-code-params.dto.js';
import { RoomConnectionDto } from './dto/room-connection.dto.js';
import { GameProtocolGuard } from './game-protocol.guard.js';
import type { Room } from './room.js';
import { RoomsService } from './rooms.service.js';

@UseGuards(GameProtocolGuard)
@Controller('rooms')
export class RoomsController {
  constructor(
    private readonly rooms: RoomsService,
    @Inject(matchServersConfig.KEY)
    private readonly config: ConfigType<typeof matchServersConfig>,
  ) {}

  @Post()
  @Throttle({ default: { limit: 5, ttl: minutes(1) } })
  async create(@Body() dto: CreateRoomDto): Promise<RoomConnectionDto> {
    return this.connection(await this.rooms.create(dto.visibility));
  }

  @Post('quick-play')
  @HttpCode(HttpStatus.OK)
  @Throttle({ default: { limit: 10, ttl: minutes(1) } })
  async quickPlay(): Promise<RoomConnectionDto> {
    return this.connection(await this.rooms.quickPlay());
  }

  @Post(':code/join')
  @HttpCode(HttpStatus.OK)
  async join(@Param() { code }: RoomCodeParamsDto): Promise<RoomConnectionDto> {
    return this.connection(await this.rooms.join(code));
  }

  private connection(room: Room): RoomConnectionDto {
    return RoomConnectionDto.from(room, this.config.publicHost);
  }
}
