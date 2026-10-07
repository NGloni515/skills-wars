import { timingSafeEqual } from 'node:crypto';
import {
  type CanActivate,
  type ExecutionContext,
  Inject,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import type { ConfigType } from '@nestjs/config';
import type { Request } from 'express';
import { matchServersConfig } from '../config/match-servers.config.js';

export const MATCH_SECRET_HEADER = 'x-match-secret';

@Injectable()
export class MatchSecretGuard implements CanActivate {
  private readonly expected: Buffer;

  constructor(
    @Inject(matchServersConfig.KEY)
    config: ConfigType<typeof matchServersConfig>,
  ) {
    this.expected = Buffer.from(config.secret);
  }

  canActivate(context: ExecutionContext): boolean {
    const header = context
      .switchToHttp()
      .getRequest<Request>()
      .header(MATCH_SECRET_HEADER);
    const provided = Buffer.from(header ?? '');
    if (
      provided.length !== this.expected.length ||
      !timingSafeEqual(provided, this.expected)
    ) {
      throw new UnauthorizedException();
    }
    return true;
  }
}
