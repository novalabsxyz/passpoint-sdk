/**
 * Configuration for the Helium Passpoint SDK.
 * Pass this to `<PasspointProvider>` or `PasspointSDK.configure()`.
 */
export interface PasspointConfig {
  /** Partner API key issued by Helium. */
  apiKey: string;

  /**
   * API environment. Defaults to `'production'`.
   * Use `'staging'` or `'development'` for testing, or pass a full URL
   * for a custom endpoint.
   */
  environment?: "production" | "staging" | "development" | (string & {});

  /**
   * EAP authentication type. Defaults to `EapType.TLS` (13).
   * Most partners should not change this.
   */
  eapType?: EapType;

  /**
   * Custom server CA certificate in PEM format.
   * If omitted, the SDK uses the bundled ISRG Root X1 certificate.
   */
  serverCaCertPem?: string;

  /**
   * iOS only. Keychain access group for sharing certificates with NetworkExtension.
   * Must match an access group in your app's entitlements.
   *
   * Format: `<TEAM_ID>.com.apple.networkextensionsharing`
   *
   * If omitted, the SDK will not set an access group on keychain items,
   * which may cause Passpoint profile installation to fail on iOS.
   */
  keychainAccessGroup?: string;
}

/** EAP authentication types supported by the SDK. */
export enum EapType {
  /** EAP-TLS (certificate-based). This is the default and recommended type. */
  TLS = 13,
  /** EAP-TTLS (tunneled TLS). */
  TTLS = 21,
  /** EAP-PEAP (Protected EAP). */
  PEAP = 25,
}

/** Structured error codes returned by all SDK operations. */
export enum PasspointErrorCode {
  // --- Configuration ---
  /** SDK has not been configured. Call PasspointSDK.configure() or use <PasspointProvider> first. */
  NOT_CONFIGURED = "NOT_CONFIGURED",
  /** The provided API key is invalid or malformed. */
  INVALID_API_KEY = "INVALID_API_KEY",
  /** The provided configuration is invalid. */
  INVALID_CONFIG = "INVALID_CONFIG",

  // --- Platform ---
  /** Passpoint is not supported on this platform (e.g. web). */
  PLATFORM_NOT_SUPPORTED = "PLATFORM_NOT_SUPPORTED",
  /** Passpoint requires a physical device; simulators are not supported. */
  SIMULATOR_NOT_SUPPORTED = "SIMULATOR_NOT_SUPPORTED",
  /** Required entitlements are missing (iOS: HotspotConfiguration capability). */
  MISSING_ENTITLEMENTS = "MISSING_ENTITLEMENTS",
  /** Location permission was denied. Android requires ACCESS_FINE_LOCATION for Passpoint. */
  PERMISSION_DENIED = "PERMISSION_DENIED",

  // --- Keypair / CSR ---
  /** Failed to generate the RSA keypair. */
  KEYPAIR_GENERATION_FAILED = "KEYPAIR_GENERATION_FAILED",
  /** Failed to generate the Certificate Signing Request. */
  CSR_GENERATION_FAILED = "CSR_GENERATION_FAILED",

  // --- Network / API ---
  /** A network error occurred while contacting the Passpoint API. */
  NETWORK_ERROR = "NETWORK_ERROR",
  /** The Passpoint API returned an error response. */
  API_ERROR = "API_ERROR",
  /** The API key was rejected (HTTP 401/403). */
  API_UNAUTHORIZED = "API_UNAUTHORIZED",
  /** The API rate limit was exceeded. */
  API_RATE_LIMITED = "API_RATE_LIMITED",

  // --- Certificate ---
  /** Failed to parse the certificate returned by the API. */
  CERTIFICATE_PARSE_FAILED = "CERTIFICATE_PARSE_FAILED",
  /** Failed to save the certificate to the device keychain/keystore. */
  CERTIFICATE_SAVE_FAILED = "CERTIFICATE_SAVE_FAILED",
  /** No certificate is currently installed on this device. */
  CERTIFICATE_NOT_FOUND = "CERTIFICATE_NOT_FOUND",
  /** Failed to build a TLS identity from the saved certificate and key. */
  IDENTITY_LOAD_FAILED = "IDENTITY_LOAD_FAILED",

  // --- Profile ---
  /** Failed to install the Passpoint WiFi profile. */
  PROFILE_INSTALL_FAILED = "PROFILE_INSTALL_FAILED",
  /** The user cancelled the profile installation OS dialog. */
  PROFILE_INSTALL_CANCELLED = "PROFILE_INSTALL_CANCELLED",
  /** No Passpoint profile is installed on this device. */
  PROFILE_NOT_FOUND = "PROFILE_NOT_FOUND",
  /** Failed to remove the Passpoint profile. */
  PROFILE_REMOVE_FAILED = "PROFILE_REMOVE_FAILED",

  // --- Revocation ---
  /** The server-side certificate revocation call failed. */
  REVOCATION_FAILED = "REVOCATION_FAILED",

  // --- Android-specific ---
  /** The Android WifiManager service is not available. */
  WIFI_MANAGER_UNAVAILABLE = "WIFI_MANAGER_UNAVAILABLE",
  /** The app has been disallowed from adding network suggestions by the user. */
  NETWORK_SUGGESTION_DISALLOWED = "NETWORK_SUGGESTION_DISALLOWED",
  /** The app has exceeded the maximum number of network suggestions. */
  NETWORK_SUGGESTION_LIMIT = "NETWORK_SUGGESTION_LIMIT",

  // --- Generic ---
  /** An unknown error occurred. Check the `nativeError` property for details. */
  UNKNOWN = "UNKNOWN",
}

/** Information about the currently installed Passpoint certificate. */
export interface CertificateInfo {
  /** Whether a Passpoint profile is currently installed and active. */
  isInstalled: boolean;
  /** Certificate expiration date (ISO 8601), or `null` if not installed. */
  expiresAt: string | null;
  /** Certificate subject CN, or `null` if not installed. */
  subject: string | null;
  /** Domain name from the Passpoint profile, or `null` if not installed. */
  domain: string | null;
  /** Human-readable name of the profile, or `null` if not installed. */
  friendlyName: string | null;
}

/** Result of a successful `install()` call. */
export interface InstallResult {
  success: true;
}

/** Result of a successful `revoke()` call. */
export interface RevokeResult {
  success: true;
}
