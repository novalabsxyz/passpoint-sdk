import { Platform } from "react-native";
import { PasspointError } from "./errors";
import NativePasspointSDK from "./NativePasspointSDK";
import type {
  CertificateInfo,
  InstallResult,
  PasspointConfig,
  RemoteProfileStatus,
  RemoveResult,
} from "./types";
import { EapType, PasspointErrorCode } from "./types";

const ENVIRONMENTS: Record<string, string> = {
  production: "https://api.prod.hib.nova.xyz/api/inventory/v1",
  development: "https://api-dev.dev.hib.nova.xyz/api/inventory/v1",
  poc: "https://api.dev.hib.nova.xyz/api/inventory/v1",
};

function resolveBaseUrl(env: string): string {
  if (env.startsWith("http")) return env.replace(/\/+$/, "");
  return ENVIRONMENTS[env] ?? ENVIRONMENTS.production;
}

/**
 * Core Helium Passpoint SDK class.
 *
 * Use this directly for imperative access, or use `<PasspointProvider>` +
 * `usePasspoint()` for React integration.
 *
 * ```typescript
 * const sdk = PasspointSDK.configure({ apiKey: 'your-key' });
 * await sdk.install('subscriber-123');
 * ```
 */
export class PasspointSDK {
  private static instance: PasspointSDK | null = null;
  private configured = false;

  private constructor() {}

  /**
   * Initialize the SDK with your configuration.
   * Call this once at app startup (or use `<PasspointProvider>` instead).
   *
   * @returns The singleton SDK instance.
   * @throws {PasspointError} with code `PLATFORM_NOT_SUPPORTED` on web.
   * @throws {PasspointError} with code `INVALID_CONFIG` if apiKey is empty.
   */
  static configure(config: PasspointConfig): PasspointSDK {
    if (Platform.OS !== "ios" && Platform.OS !== "android") {
      throw new PasspointError(
        PasspointErrorCode.PLATFORM_NOT_SUPPORTED,
        `Passpoint is not supported on ${Platform.OS}. Only iOS and Android are supported.`,
      );
    }

    if (!config.apiKey || config.apiKey.trim().length === 0) {
      throw new PasspointError(
        PasspointErrorCode.INVALID_CONFIG,
        "apiKey is required and must be a non-empty string.",
      );
    }

    const instance = PasspointSDK.instance ?? new PasspointSDK();
    PasspointSDK.instance = instance;

    const baseUrl = resolveBaseUrl(config.environment ?? "production");
    const eapType = config.eapType ?? EapType.TLS;

    NativePasspointSDK.configure(
      config.apiKey,
      baseUrl,
      eapType,
      config.serverCaCertPem ?? null,
      config.keychainAccessGroup ?? null,
      config.presetId ?? null,
    );

    instance.configured = true;
    return instance;
  }

  /**
   * Get the current SDK instance.
   * @throws {PasspointError} with code `NOT_CONFIGURED` if `configure()` hasn't been called.
   */
  static getInstance(): PasspointSDK {
    if (!PasspointSDK.instance?.configured) {
      throw new PasspointError(
        PasspointErrorCode.NOT_CONFIGURED,
        "PasspointSDK.configure() must be called before getInstance(). " +
          "Wrap your app in <PasspointProvider> or call PasspointSDK.configure() at startup.",
      );
    }
    return PasspointSDK.instance;
  }

  /**
   * Install a Passpoint WiFi profile for the given subscriber.
   *
   * This generates an RSA keypair, creates a CSR, sends it to the Helium
   * Passpoint API, and installs the returned certificate as a Passpoint
   * (Hotspot 2.0) WiFi profile on the device.
   *
   * @param subscriberId - Partner-defined subscriber identifier. Opaque to the
   *   SDK; the server uses it to associate this certificate with the subscriber
   *   and will revoke any prior certificate issued for the same `subscriberId`.
   */
  async install(subscriberId: string): Promise<InstallResult> {
    this.ensureConfigured();

    if (!subscriberId || subscriberId.trim().length === 0) {
      throw new PasspointError(
        PasspointErrorCode.INVALID_CONFIG,
        "subscriberId is required and must be a non-empty string.",
      );
    }

    try {
      const json = await NativePasspointSDK.install(subscriberId);
      return JSON.parse(json) as InstallResult;
    } catch (error) {
      throw PasspointError.fromNative(error);
    }
  }

  /**
   * Check if a Passpoint profile is currently installed on this device
   * (local keychain/keystore check — does not contact the server).
   *
   * Use {@link getRemoteStatus} to reconcile with server-side state.
   */
  async isInstalled(): Promise<boolean> {
    this.ensureConfigured();

    try {
      return await NativePasspointSDK.isInstalled();
    } catch (error) {
      throw PasspointError.fromNative(error);
    }
  }

  /**
   * Get detailed information about the locally installed certificate.
   *
   * Returns `{ isInstalled: false, ... }` if no profile is installed
   * (does not throw).
   */
  async getCertificateInfo(): Promise<CertificateInfo> {
    this.ensureConfigured();

    try {
      const json = await NativePasspointSDK.getCertificateInfo();
      return JSON.parse(json) as CertificateInfo;
    } catch (error) {
      throw PasspointError.fromNative(error);
    }
  }

  /**
   * Query the Helium API for the server-side profile status of a subscriber.
   *
   * Unlike {@link isInstalled}, this hits the network and reflects the
   * server's view — useful for detecting revocation or verifying that an
   * install succeeded end-to-end.
   *
   * @param subscriberId - The same identifier passed to {@link install}.
   * @returns The server's profile record, or `null` if the server has no
   *   active profile for this subscriber (HTTP 404).
   * @throws {PasspointError} on network or API errors.
   */
  async getRemoteStatus(subscriberId: string): Promise<RemoteProfileStatus | null> {
    this.ensureConfigured();

    if (!subscriberId || subscriberId.trim().length === 0) {
      throw new PasspointError(
        PasspointErrorCode.INVALID_CONFIG,
        "subscriberId is required and must be a non-empty string.",
      );
    }

    try {
      const json = await NativePasspointSDK.getRemoteStatus(subscriberId);
      const parsed = JSON.parse(json);
      return parsed as RemoteProfileStatus | null;
    } catch (error) {
      throw PasspointError.fromNative(error);
    }
  }

  /**
   * Remove the installed Passpoint profile and clean up stored keys
   * and certificates from the device.
   *
   * @throws {PasspointError} with code `CERTIFICATE_NOT_FOUND` if no profile is installed.
   * @throws {PasspointError} with code `REMOVE_FAILED` if the removal fails.
   */
  async remove(): Promise<RemoveResult> {
    this.ensureConfigured();

    try {
      const json = await NativePasspointSDK.remove();
      return JSON.parse(json) as RemoveResult;
    } catch (error) {
      throw PasspointError.fromNative(error);
    }
  }

  /** @internal Reset singleton for testing. Do not use in production. */
  static _reset(): void {
    PasspointSDK.instance = null;
  }

  private ensureConfigured(): void {
    if (!this.configured) {
      throw new PasspointError(
        PasspointErrorCode.NOT_CONFIGURED,
        "PasspointSDK.configure() must be called before using the SDK.",
      );
    }
  }
}
