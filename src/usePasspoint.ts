import { useContext } from "react";
import { PasspointError } from "./errors";
import type { UsePasspointResult } from "./PasspointProvider";
import { PasspointContext } from "./PasspointProvider";
import { PasspointErrorCode } from "./types";

export type { UsePasspointResult };

/**
 * React hook for Passpoint SDK operations.
 *
 * Must be used inside a `<PasspointProvider>`. State is shared across
 * all components — calling `install()` or `revoke()` from any component
 * updates `isInstalled` everywhere.
 *
 * ```tsx
 * function WifiScreen({ userId }) {
 *   const { isInstalled, install, revoke, isLoading, error } = usePasspoint();
 *
 *   return isInstalled
 *     ? <Button onPress={revoke}>Remove WiFi Profile</Button>
 *     : <Button onPress={() => install(userId)}>Enable WiFi Offload</Button>;
 * }
 * ```
 */
export function usePasspoint(): UsePasspointResult {
  const context = useContext(PasspointContext);
  if (!context) {
    throw new PasspointError(
      PasspointErrorCode.NOT_CONFIGURED,
      "usePasspoint() must be used inside a <PasspointProvider>.",
    );
  }
  return context;
}
