import {
  createContext,
  type ReactNode,
  useCallback,
  useEffect,
  useMemo,
  useState,
} from "react";
import { AppState } from "react-native";
import { PasspointError } from "./errors";
import { PasspointSDK } from "./PasspointSDK";
import type {
  CertificateInfo,
  InstallResult,
  PasspointConfig,
  RevokeResult,
} from "./types";

export interface UsePasspointResult {
  /** Whether a Passpoint profile is currently installed. `null` while loading. */
  isInstalled: boolean | null;

  /** Detailed certificate info. `null` while loading or if not installed. */
  certificateInfo: CertificateInfo | null;

  /** Install a Passpoint profile for the given user. */
  install: (userIdentifier: string) => Promise<InstallResult>;

  /** Remove the installed profile and revoke the certificate. */
  revoke: () => Promise<RevokeResult>;

  /** Manually refresh the installation status and certificate info. */
  refresh: () => Promise<void>;

  /** Whether an `install` or `revoke` operation is currently in progress. */
  isLoading: boolean;

  /** The last error encountered, or `null`. Cleared on the next successful operation. */
  error: PasspointError | null;
}

/** @internal */
export const PasspointContext = createContext<UsePasspointResult | null>(null);

export interface PasspointProviderProps {
  /** SDK configuration. Only `apiKey` is required. */
  config: PasspointConfig;
  children: ReactNode;
}

/**
 * Initialize the Passpoint SDK and make `usePasspoint()` available
 * to all descendant components. State is shared — calling `revoke()`
 * from any component updates `isInstalled` everywhere.
 *
 * ```tsx
 * import { PasspointProvider } from '@helium/passpoint-sdk';
 *
 * export default function App() {
 *   return (
 *     <PasspointProvider config={{ apiKey: 'your-api-key' }}>
 *       <YourApp />
 *     </PasspointProvider>
 *   );
 * }
 * ```
 */
export function PasspointProvider({ config, children }: PasspointProviderProps) {
  const sdk = useMemo(() => {
    return PasspointSDK.configure(config);
  }, [config]);

  const [isInstalled, setIsInstalled] = useState<boolean | null>(null);
  const [certificateInfo, setCertificateInfo] = useState<CertificateInfo | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<PasspointError | null>(null);

  const refresh = useCallback(async () => {
    try {
      const [installed, info] = await Promise.all([
        sdk.isInstalled(),
        sdk.getCertificateInfo(),
      ]);
      setIsInstalled(installed);
      setCertificateInfo(info);
    } catch {
      try {
        const installed = await sdk.isInstalled();
        setIsInstalled(installed);
      } catch {
        // leave state as-is
      }
    }
  }, [sdk]);

  // Check on mount
  useEffect(() => {
    refresh();
  }, [refresh]);

  // Re-check when app comes to foreground
  useEffect(() => {
    const subscription = AppState.addEventListener("change", (state) => {
      if (state === "active") {
        refresh();
      }
    });
    return () => subscription.remove();
  }, [refresh]);

  const install = useCallback(
    async (userIdentifier: string): Promise<InstallResult> => {
      setIsLoading(true);
      setError(null);
      try {
        const result = await sdk.install(userIdentifier);
        setIsInstalled(true);
        await refresh();
        return result;
      } catch (e) {
        const passpointError = PasspointError.fromNative(e);
        setError(passpointError);
        throw passpointError;
      } finally {
        setIsLoading(false);
      }
    },
    [sdk, refresh],
  );

  const revoke = useCallback(async (): Promise<RevokeResult> => {
    setIsLoading(true);
    setError(null);
    try {
      const result = await sdk.revoke();
      setIsInstalled(false);
      setCertificateInfo(null);
      return result;
    } catch (e) {
      const passpointError = PasspointError.fromNative(e);
      setError(passpointError);
      throw passpointError;
    } finally {
      setIsLoading(false);
    }
  }, [sdk]);

  const value = useMemo(
    () => ({
      isInstalled,
      certificateInfo,
      install,
      revoke,
      refresh,
      isLoading,
      error,
    }),
    [isInstalled, certificateInfo, install, revoke, refresh, isLoading, error],
  );

  return <PasspointContext.Provider value={value}>{children}</PasspointContext.Provider>;
}
