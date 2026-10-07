import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { APP_GUARD } from '@nestjs/core';
import { ThrottlerGuard, ThrottlerModule, minutes } from '@nestjs/throttler';
import { appConfig } from './config/app.config.js';
import { validate } from './config/env.validation.js';
import { matchServersConfig } from './config/match-servers.config.js';
import { HealthModule } from './health/health.module.js';
import { RoomsModule } from './rooms/rooms.module.js';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      validate,
      load: [appConfig, matchServersConfig],
    }),
    ThrottlerModule.forRoot([{ ttl: minutes(1), limit: 60 }]),
    RoomsModule,
    HealthModule,
  ],
  providers: [{ provide: APP_GUARD, useClass: ThrottlerGuard }],
})
export class AppModule {}
