export interface MatchServerSpec {
  code: string;
  port: number;
}

export interface MatchServerProcess {
  stop(): void;
  onExit(listener: (exitCode: number | null) => void): void;
}

export abstract class MatchServerLauncher {
  abstract launch(spec: MatchServerSpec): MatchServerProcess;
  abstract readProtocol(): Promise<number>;
}
