import { registerAs } from '@nestjs/config';
import { validate } from './env.validation.js';

export const matchServersConfig = registerAs('matchServers', () => {
  const env = validate(process.env);
  return {
    publicHost: env.PUBLIC_HOST,
    portMin: env.MATCH_PORT_MIN,
    portMax: env.MATCH_PORT_MAX,
    command: env.MATCH_SERVER_COMMAND,
    args: env.MATCH_SERVER_ARGS.split(/\s+/).filter(Boolean),
    secret: env.MATCH_SECRET,
    backendUrl: env.BACKEND_INTERNAL_URL ?? `http://127.0.0.1:${env.PORT}`,
    startTimeoutMs: env.MATCH_START_TIMEOUT_MS,
    heartbeatTimeoutMs: env.MATCH_HEARTBEAT_TIMEOUT_MS,
    emptyRoomTtlMs: env.EMPTY_ROOM_TTL_MS,
  };
});
