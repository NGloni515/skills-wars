import { Module } from '@nestjs/common';
import { MatchServersModule } from '../match-servers/match-servers.module.js';
import { GameProtocolGuard } from './game-protocol.guard.js';
import { MatchHeartbeatController } from './match-heartbeat.controller.js';
import { MatchSecretGuard } from './match-secret.guard.js';
import { RoomsController } from './rooms.controller.js';
import { RoomsService } from './rooms.service.js';

@Module({
  imports: [MatchServersModule],
  controllers: [RoomsController, MatchHeartbeatController],
  providers: [RoomsService, MatchSecretGuard, GameProtocolGuard],
  exports: [RoomsService],
})
export class RoomsModule {}
