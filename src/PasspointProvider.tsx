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
  RemoteProfileStatus,
  RemoveResult,
} from "./types";

export interface UsePasspointResult {
  /** Whether a Passpoint profile is currently installed. `null` while loading. */
  isInstalled: boolean | null;

  /** Detailed certificate info. `null` while loading or if not installed. */
  certificateInfo: CertificateInfo | null;

  /** Install a Passpoint profile for the given subscriber. */
  install: (subscriberId: string) => Promise<InstallResult>;

  /** Remove the installed Passpoint profile and clean up stored certificates. */
  remove: () => Promise<RemoveResult>;

  /**
   * Query the server for the current profile status of a subscriber.
   * Returns `null` if the server has no active profile for this subscriber.
   */
  getRemoteStatus: (subscriberId: string) => Promise<RemoteProfileStatus | null>;

  /** Manually refresh the local installation status and certificate info. */
  refresh: () => Promise<void>;

  /** Whether an `install` or `remove` operation is currently in progress. */
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
 * to all descendant components. State is shared — calling `remove()`
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
  const { apiKey, environment, eapType, serverCaCertPem, keychainAccessGroup, presetId } =
    config;

  const sdk = useMemo(() => {
    return PasspointSDK.configure({
      apiKey,
      environment,
      eapType,
      serverCaCertPem,
      keychainAccessGroup,
      presetId,
    });
  }, [apiKey, environment, eapType, serverCaCertPem, keychainAccessGroup, presetId]);

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
    async (subscriberId: string): Promise<InstallResult> => {
      setIsLoading(true);
      setError(null);
      try {
        const result = await sdk.install(subscriberId);
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

  const remove = useCallback(async (): Promise<RemoveResult> => {
    setIsLoading(true);
    setError(null);
    try {
      const result = await sdk.remove();
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

  const getRemoteStatus = useCallback(
    async (subscriberId: string): Promise<RemoteProfileStatus | null> => {
      try {
        return await sdk.getRemoteStatus(subscriberId);
      } catch (e) {
        const passpointError = PasspointError.fromNative(e);
        setError(passpointError);
        throw passpointError;
      }
    },
    [sdk],
  );

  const value = useMemo(
    () => ({
      isInstalled,
      certificateInfo,
      install,
      remove,
      getRemoteStatus,
      refresh,
      isLoading,
      error,
    }),
    [
      isInstalled,
      certificateInfo,
      install,
      remove,
      getRemoteStatus,
      refresh,
      isLoading,
      error,
    ],
  );

  return <PasspointContext.Provider value={value}>{children}</PasspointContext.Provider>;
}
