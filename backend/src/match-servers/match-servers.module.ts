import { Logger, Module } from '@nestjs/common';
import { GAME_PROTOCOL } from './game-protocol.js';
import { MatchServerLauncher } from './match-server-launcher.js';
import { PortPool } from './port-pool.js';
import { ProcessMatchServerLauncher } from './process-match-server-launcher.js';

@Module({
  providers: [
    PortPool,
    { provide: MatchServerLauncher, useClass: ProcessMatchServerLauncher },
    {
      provide: GAME_PROTOCOL,
      inject: [MatchServerLauncher],
      useFactory: async (launcher: MatchServerLauncher) => {
        const protocol = await launcher.readProtocol();
        new Logger('MatchServers').log(
          `Match servers speak game protocol ${protocol}`,
        );
        return protocol;
      },
    },
  ],
  exports: [PortPool, MatchServerLauncher, GAME_PROTOCOL],
})
export class MatchServersModule {}
