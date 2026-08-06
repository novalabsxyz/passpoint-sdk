import { NativeModules } from "react-native";

/**
 * Native module interface for the Helium Passpoint SDK.
 *
 * Complex return types are serialized as JSON strings across the bridge
 * and deserialized in the TypeScript wrapper (PasspointSDK.ts).
 */
export interface Spec {
  /**
   * Store SDK configuration on the native side.
   * Must be called before any other method.
   *
   * `baseUrl` is the inventory API base (e.g. `https://api.prod.hib.nova.xyz/api/inventory/v1`);
   * the native layer appends `/preset/profile/generate` and `/preset/profile/status`.
   */
  configure(
    apiKey: string,
    baseUrl: string,
    eapType: number,
    serverCaCertPem: string | null,
    keychainAccessGroup: string | null,
    presetId: string | null,
  ): void;

  /**
   * Generate keypair, create CSR, call API, install Passpoint profile.
   * @returns JSON-encoded InstallResult
   */
  install(subscriberId: string): Promise<string>;

  /**
   * Check if a Passpoint profile is currently installed locally — no network.
   *
   * iOS reads the client certificate from the keychain. Android reads a flag
   * the SDK writes on a successful install: `WifiManager` exposes no way to ask
   * whether a specific Passpoint profile is still present, so a profile the
   * user deletes in Settings will still report as installed until the SDK's
   * `remove()` runs.
   */
  isInstalled(): Promise<boolean>;

  /**
   * Get details about the locally installed certificate.
   * @returns JSON-encoded CertificateInfo
   */
  getCertificateInfo(): Promise<string>;

  /**
   * Query the server for the current profile status of a subscriber.
   * @returns JSON-encoded RemoteProfileStatus, or the string `"null"` when the
   *          server has no active profile for this subscriber (HTTP 404).
   */
  getRemoteStatus(subscriberId: string): Promise<string>;

  /**
   * Remove the local Passpoint profile and clean up stored certificates.
   * @returns JSON-encoded RemoveResult
   */
  remove(): Promise<string>;

  /** @internal Debug diagnostics — returns raw native state as JSON. */
  debug(): Promise<string>;
}

export default NativeModules.HeliumPasspointSDK as Spec;
