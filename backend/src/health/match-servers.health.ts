import { Inject, Injectable } from '@nestjs/common';
import { HealthIndicatorService } from '@nestjs/terminus';
import { GAME_PROTOCOL } from '../match-servers/game-protocol.js';
import { PortPool } from '../match-servers/port-pool.js';
import { RoomsService } from '../rooms/rooms.service.js';

@Injectable()
export class MatchServersHealthIndicator {
  constructor(
    private readonly indicators: HealthIndicatorService,
    private readonly rooms: RoomsService,
    private readonly ports: PortPool,
    @Inject(GAME_PROTOCOL) private readonly protocol: number,
  ) {}

  check(key: string) {
    return this.indicators.check(key).up({
      rooms: this.rooms.count,
      freeSlots: this.ports.available,
      protocol: this.protocol,
    });
  }
}
