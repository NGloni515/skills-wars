import { IsInt, Max, Min } from 'class-validator';

export class HeartbeatDto {
  @IsInt()
  @Min(0)
  @Max(16)
  humans: number;

  @IsInt()
  @Min(0)
  @Max(16)
  bots: number;
}
