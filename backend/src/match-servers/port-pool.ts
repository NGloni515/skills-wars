import { Inject, Injectable } from '@nestjs/common';
import type { ConfigType } from '@nestjs/config';
import { matchServersConfig } from '../config/match-servers.config.js';

@Injectable()
export class PortPool {
  private readonly free: number[] = [];

  constructor(
    @Inject(matchServersConfig.KEY)
    config: ConfigType<typeof matchServersConfig>,
  ) {
    for (let port = config.portMin; port <= config.portMax; port++) {
      this.free.push(port);
    }
  }

  get available(): number {
    return this.free.length;
  }

  take(): number | undefined {
    return this.free.shift();
  }

  release(port: number): void {
    if (!this.free.includes(port)) {
      this.free.push(port);
    }
  }
}
