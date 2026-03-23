import { Platform } from "react-native";
import { PasspointError } from "./errors";
import NativePasspointSDK from "./NativePasspointSDK";
import type {
  CertificateInfo,
  InstallResult,
  PasspointConfig,
  RevokeResult,
} from "./types";
import { EapType, PasspointErrorCode } from "./types";

const ENVIRONMENTS: Record<string, string> = {
  production: "https://api.hib.nova.xyz/api/inventory/v1/passpoint/generate",
  staging: "https://api.staging.hib.nova.xyz/api/inventory/v1/passpoint/generate",
  development: "https://api.dev.hib.nova.xyz/api/inventory/v1/passpoint/generate",
};

function resolveEndpoint(env: string): string {
  if (env.startsWith("http")) return env;
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
 * await sdk.install('user-123');
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

    const endpoint = resolveEndpoint(config.environment ?? "production");
    const eapType = config.eapType ?? EapType.TLS;

    NativePasspointSDK.configure(
      config.apiKey,
      endpoint,
      eapType,
      config.serverCaCertPem ?? null,
      config.keychainAccessGroup ?? null,
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
   * Install a Passpoint WiFi profile for the given user.
   *
   * This generates an RSA keypair, creates a CSR, sends it to the Helium
   * Passpoint API, and installs the returned certificate as a Passpoint
   * (Hotspot 2.0) WiFi profile on the device.
   *
   * @param userIdentifier - Unique identifier for this subscriber.
   */
  async install(userIdentifier: string): Promise<InstallResult> {
    this.ensureConfigured();

    if (!userIdentifier || userIdentifier.trim().length === 0) {
      throw new PasspointError(
        PasspointErrorCode.INVALID_CONFIG,
        "userIdentifier is required and must be a non-empty string.",
      );
    }

    try {
      const json = await NativePasspointSDK.install(userIdentifier);
      return JSON.parse(json) as InstallResult;
    } catch (error) {
      throw PasspointError.fromNative(error);
    }
  }

  /**
   * Check if a Passpoint profile is currently installed on this device.
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
   * Get detailed information about the installed certificate.
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
   * Revoke the installed certificate and remove the Passpoint profile.
   *
   * This calls the server-side revocation API first, then removes the
   * local profile and cleans up stored keys and certificates.
   *
   * @throws {PasspointError} with code `CERTIFICATE_NOT_FOUND` if no profile is installed.
   * @throws {PasspointError} with code `REVOCATION_FAILED` if the server call fails.
   */
  async revoke(): Promise<RevokeResult> {
    this.ensureConfigured();

    try {
      const json = await NativePasspointSDK.revoke();
      return JSON.parse(json) as RevokeResult;
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
