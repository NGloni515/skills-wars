import {
  type CanActivate,
  type ExecutionContext,
  HttpException,
  Inject,
  Injectable,
} from '@nestjs/common';
import type { Request } from 'express';
import { GAME_PROTOCOL } from '../match-servers/game-protocol.js';

export const GAME_PROTOCOL_HEADER = 'x-game-protocol';
const UPGRADE_REQUIRED = 426;

@Injectable()
export class GameProtocolGuard implements CanActivate {
  constructor(@Inject(GAME_PROTOCOL) private readonly protocol: number) {}

  canActivate(context: ExecutionContext): boolean {
    const header = context
      .switchToHttp()
      .getRequest<Request>()
      .header(GAME_PROTOCOL_HEADER);
    if (Number(header) !== this.protocol) {
      throw new HttpException(
        {
          statusCode: UPGRADE_REQUIRED,
          message: 'This version of the game cannot play on these servers',
          protocol: this.protocol,
        },
        UPGRADE_REQUIRED,
      );
    }
    return true;
  }
}
