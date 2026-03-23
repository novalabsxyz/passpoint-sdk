import { PasspointErrorCode } from "./types";

/**
 * Error thrown by all Passpoint SDK operations.
 *
 * Use `error.code` to programmatically handle specific failure modes:
 *
 * ```typescript
 * try {
 *   await passpoint.install(userId);
 * } catch (e) {
 *   if (e instanceof PasspointError) {
 *     switch (e.code) {
 *       case PasspointErrorCode.PERMISSION_DENIED:
 *         // prompt user to grant location permission
 *         break;
 *       case PasspointErrorCode.PROFILE_INSTALL_CANCELLED:
 *         // user dismissed the OS dialog
 *         break;
 *     }
 *   }
 * }
 * ```
 */
export class PasspointError extends Error {
  /** Machine-readable error code for programmatic handling. */
  readonly code: PasspointErrorCode;

  /** The original native error, if available. */
  readonly nativeError?: unknown;

  constructor(code: PasspointErrorCode, message: string, nativeError?: unknown) {
    super(message);
    this.name = "PasspointError";
    this.code = code;
    this.nativeError = nativeError;
  }

  /**
   * Wrap a native module rejection into a typed PasspointError.
   * Native modules reject with `{ code: string, message: string }`.
   */
  static fromNative(error: unknown): PasspointError {
    if (error instanceof PasspointError) return error;

    const native = error as { code?: string; message?: string } | undefined;
    const code = Object.values(PasspointErrorCode).includes(
      native?.code as PasspointErrorCode,
    )
      ? (native?.code as PasspointErrorCode)
      : PasspointErrorCode.UNKNOWN;
    const message = native?.message ?? "An unknown error occurred";

    return new PasspointError(code, message, error);
  }
}
