import { Type, plainToInstance } from 'class-transformer';
import {
  IsEnum,
  IsInt,
  IsOptional,
  IsString,
  IsUrl,
  Max,
  MinLength,
  Min,
  validateSync,
} from 'class-validator';

export enum Environment {
  Development = 'development',
  Production = 'production',
  Test = 'test',
}

export class EnvironmentVariables {
  @IsEnum(Environment)
  NODE_ENV: Environment = Environment.Development;

  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(65535)
  PORT = 3000;

  @IsString()
  PUBLIC_HOST = '127.0.0.1';

  @Type(() => Number)
  @IsInt()
  @Min(1024)
  @Max(65535)
  MATCH_PORT_MIN = 7800;

  @Type(() => Number)
  @IsInt()
  @Min(1024)
  @Max(65535)
  MATCH_PORT_MAX = 7819;

  @IsString()
  MATCH_SERVER_COMMAND: string;

  @IsString()
  MATCH_SERVER_ARGS = '--headless';

  @IsString()
  @MinLength(16)
  MATCH_SECRET: string;

  @IsOptional()
  @IsUrl({ require_tld: false })
  BACKEND_INTERNAL_URL?: string;

  @Type(() => Number)
  @IsInt()
  @Min(1000)
  MATCH_START_TIMEOUT_MS = 15000;

  @Type(() => Number)
  @IsInt()
  @Min(1000)
  MATCH_HEARTBEAT_TIMEOUT_MS = 20000;

  @Type(() => Number)
  @IsInt()
  @Min(1000)
  EMPTY_ROOM_TTL_MS = 90000;
}

export function validate(
  config: Record<string, unknown>,
): EnvironmentVariables {
  const validated = plainToInstance(EnvironmentVariables, config, {
    enableImplicitConversion: true,
  });
  const errors = validateSync(validated, { skipMissingProperties: false });
  if (errors.length > 0) {
    throw new Error(errors.toString());
  }
  if (validated.MATCH_PORT_MIN > validated.MATCH_PORT_MAX) {
    throw new Error('MATCH_PORT_MIN must not be greater than MATCH_PORT_MAX');
  }
  return validated;
}
