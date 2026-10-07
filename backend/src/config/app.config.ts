import { registerAs } from '@nestjs/config';
import { validate } from './env.validation.js';

export const appConfig = registerAs('app', () => {
  const env = validate(process.env);
  return {
    environment: env.NODE_ENV,
    port: env.PORT,
  };
});
