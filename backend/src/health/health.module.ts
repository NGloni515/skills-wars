import { Module } from '@nestjs/common';
import { TerminusModule } from '@nestjs/terminus';
import { MatchServersModule } from '../match-servers/match-servers.module.js';
import { RoomsModule } from '../rooms/rooms.module.js';
import { HealthController } from './health.controller.js';
import { MatchServersHealthIndicator } from './match-servers.health.js';

@Module({
  imports: [TerminusModule, RoomsModule, MatchServersModule],
  controllers: [HealthController],
  providers: [MatchServersHealthIndicator],
})
export class HealthModule {}
