import { type ChildProcess, execFile, spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { promisify } from 'node:util';
import { Inject, Injectable, Logger } from '@nestjs/common';
import type { ConfigType } from '@nestjs/config';
import { matchServersConfig } from '../config/match-servers.config.js';
import {
  MatchServerLauncher,
  type MatchServerProcess,
  type MatchServerSpec,
} from './match-server-launcher.js';

const KILL_GRACE_MS = 5000;
const PROTOCOL_PROBE_TIMEOUT_MS = 30000;
const PROTOCOL_LINE = /^protocol=(\d+)$/m;

@Injectable()
export class ProcessMatchServerLauncher extends MatchServerLauncher {
  constructor(
    @Inject(matchServersConfig.KEY)
    private readonly config: ConfigType<typeof matchServersConfig>,
  ) {
    super();
  }

  launch({ code, port }: MatchServerSpec): MatchServerProcess {
    const child = spawn(
      this.config.command,
      [
        ...this.config.args,
        '--',
        '--server',
        '--fill',
        `--port=${port}`,
        `--room=${code}`,
        `--backend=${this.config.backendUrl}`,
      ],
      {
        env: { ...process.env, MATCH_SECRET: this.config.secret },
        stdio: ['ignore', 'pipe', 'pipe'],
      },
    );
    return new ChildMatchServer(child, new Logger(`Match ${code}`));
  }

  async readProtocol(): Promise<number> {
    const { stdout } = await promisify(execFile)(
      this.config.command,
      [...this.config.args, '--', '--print-protocol'],
      { timeout: PROTOCOL_PROBE_TIMEOUT_MS },
    );
    const match = PROTOCOL_LINE.exec(stdout);
    if (!match) {
      throw new Error(
        `${this.config.command} did not report its game protocol. Is MATCH_SERVER_COMMAND a Skills Wars build?`,
      );
    }
    return Number(match[1]);
  }
}

class ChildMatchServer implements MatchServerProcess {
  private readonly listeners: ((exitCode: number | null) => void)[] = [];
  private exited = false;
  private exitCode: number | null = null;

  constructor(
    private readonly child: ChildProcess,
    logger: Logger,
  ) {
    createInterface({ input: child.stdout! }).on('line', (line) =>
      logger.log(line),
    );
    createInterface({ input: child.stderr! }).on('line', (line) =>
      logger.warn(line),
    );
    // A spawn failure (e.g. missing binary) emits 'error' and may never emit 'exit'.
    child.once('error', (error) => {
      logger.error(`Could not run match server: ${error.message}`);
      this.finish(null);
    });
    child.once('exit', (exitCode) => this.finish(exitCode));
  }

  stop(): void {
    if (this.exited) {
      return;
    }
    this.child.kill('SIGTERM');
    setTimeout(() => {
      if (!this.exited) {
        this.child.kill('SIGKILL');
      }
    }, KILL_GRACE_MS).unref();
  }

  onExit(listener: (exitCode: number | null) => void): void {
    if (this.exited) {
      listener(this.exitCode);
      return;
    }
    this.listeners.push(listener);
  }

  private finish(exitCode: number | null): void {
    if (this.exited) {
      return;
    }
    this.exited = true;
    this.exitCode = exitCode;
    for (const listener of this.listeners) {
      listener(exitCode);
    }
  }
}
