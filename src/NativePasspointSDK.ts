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
   */
  configure(
    apiKey: string,
    endpoint: string,
    eapType: number,
    serverCaCertPem: string | null,
    keychainAccessGroup: string | null,
  ): void;

  /**
   * Generate keypair, create CSR, call API, install Passpoint profile.
   * @returns JSON-encoded InstallResult
   */
  install(userIdentifier: string): Promise<string>;

  /**
   * Check if a Passpoint profile is currently installed.
   */
  isInstalled(): Promise<boolean>;

  /**
   * Get details about the installed certificate.
   * @returns JSON-encoded CertificateInfo
   */
  getCertificateInfo(): Promise<string>;

  /**
   * Remove the local Passpoint profile and clean up stored certificates.
   * @returns JSON-encoded RemoveResult
   */
  remove(): Promise<string>;

  /** @internal Debug diagnostics — returns raw native state as JSON. */
  debug(): Promise<string>;
}

export default NativeModules.HeliumPasspointSDK as Spec;
